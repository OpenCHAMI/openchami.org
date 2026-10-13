// SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
// SPDX-License-Identifier: MIT
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const YAML = require('yaml');
const { generate, parsePage } = require('../scripts/build-doc-editions.cjs');

function fixture(t, families) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'doc-editions-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  git('init', '--initial-branch=main');
  git('config', 'user.name', 'Edition test');
  git('config', 'user.email', 'edition-test@example.invalid');
  git('config', 'commit.gpgsign', 'false');
  git('config', 'tag.gpgsign', 'false');
  git('config', 'core.hooksPath', '/dev/null');
  const write = (name, body) => {
    const target = path.join(root, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, body);
  };
  const config = { families: families || { tutorial: { title: 'Tutorial', source: 'content/docs/tutorial.md', url: '/docs/tutorial/', tagPrefix: 'tutorial-' } } };
  const saveConfig = () => write('scripts/doc-editions.config.yaml', YAML.stringify(config));
  saveConfig();
  write('content/docs/tutorial.md', '---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\nOriginal tutorial.\n');
  const commit = () => { git('add', '--all'); git('commit', '-m', 'Documentation'); return git('rev-parse', 'HEAD'); };
  commit();
  return { root, git, write, commit, config, saveConfig, read: name => fs.readFileSync(path.join(root, '.generated/doc-editions', name), 'utf8') };
}

const tutorial = id => `content/docs/editions/tutorial/${id}.md`;

test('no matching tags produces Latest, unrelated tags are ignored', t => {
  const f = fixture(t);
  f.git('tag', 'v0.2.0');
  assert.deepEqual(generate(f.root).tutorial.editions.map(entry => entry.id), ['latest']);
});

test('annotated and lightweight tags extract frozen content in newest-first order', t => {
  const f = fixture(t);
  f.git('tag', '-a', 'tutorial-2026-08-06', '-m', 'Snapshot');
  f.write('content/docs/tutorial.md', '---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\nSecond edition.\n');
  f.commit(); f.git('tag', 'tutorial-2026-10-12');
  f.write('content/docs/tutorial.md', '---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\nUncommitted Latest.\n');
  const editions = generate(f.root).tutorial.editions;
  assert.deepEqual(editions.map(entry => entry.id), ['latest', '2026-10-12', '2026-08-06']);
  const old = parsePage(f.read(tutorial('2026-08-06')), 'old');
  assert.equal(old.body, 'Original tutorial.\n');
  assert.equal(old.metadata.edition_commit, f.git('rev-parse', 'tutorial-2026-08-06^{commit}'));
  assert.equal(old.metadata.edition_source, 'content/docs/tutorial.md');
  assert.equal(old.metadata.exclude_search, true);
  assert.equal(old.metadata.build.list, 'never');
  assert.match(f.read(tutorial('2026-10-12')), /Second edition\./);
  assert.doesNotMatch(f.read(tutorial('2026-10-12')), /Uncommitted/);
});

test('release-shaped IDs work and stale outputs disappear on regeneration', t => {
  const f = fixture(t); f.git('tag', 'tutorial-v0.2.0');
  generate(f.root); assert.match(f.read(tutorial('v0.2.0')), /Original tutorial/);
  f.git('tag', '-d', 'tutorial-v0.2.0'); generate(f.root);
  assert.equal(fs.existsSync(path.join(f.root, '.generated/doc-editions', tutorial('v0.2.0'))), false);
});

test('bootstrap sources preserve legacy URLs, matching tags supersede their content', t => {
  const f = fixture(t);
  f.write('content/docs/archive/legacy.md', '---\ntitle: Old title\n---\nLegacy services.\n');
  const ref = f.commit();
  f.config.families.tutorial.bootstrap = [{ id: '2025-10-06', label: 'Legacy services', ref, source: 'content/docs/archive/legacy.md', aliases: ['/docs/archive/tutorial-legacy/'] }];
  f.saveConfig();
  generate(f.root); assert.match(f.read(tutorial('2025-10-06')), /Legacy services\./);
  f.git('tag', 'tutorial-2025-10-06');
  const registry = generate(f.root);
  assert.match(f.read(tutorial('2025-10-06')), /Original tutorial\./);
  assert.equal(registry.tutorial.editions[1].label, 'Legacy services');
  assert.deepEqual(parsePage(f.read(tutorial('2025-10-06')), 'snapshot').metadata.aliases, ['/docs/archive/tutorial-legacy/']);
});

test('sections preserve chapter keys, dated links, local cards, and bundled resources', t => {
  const f = fixture(t, { handbook: { title: 'Handbook', source: 'content/docs/handbook', url: '/docs/handbook/', tagPrefix: 'handbook-' } });
  f.write('content/docs/handbook/_index.md', '---\ntitle: Handbook\nlayout: cards\nedition_family: handbook\nedition_id: latest\n---\n[Install](1-installation.md)\n');
  f.write('content/docs/handbook/1-installation.md', '---\ntitle: Installation\nslug: installation\naliases: [/docs/old-install/]\n---\n[Home](/docs/handbook/) [Self](https://openchami.org/docs/handbook/installation/#setup)\n');
  f.write('content/docs/handbook/config/index.md', '---\ntitle: Config\n---\n![Diagram](diagram.png)\n');
  f.write('content/docs/handbook/config/diagram.png', Buffer.from([0, 1, 2, 255]));
  f.commit(); f.git('tag', 'handbook-2026-10-12');
  generate(f.root);
  const base = 'content/docs/editions/handbook/2026-10-12';
  const chapter = parsePage(f.read(`${base}/1-installation.md`), 'chapter');
  assert.equal(chapter.metadata.edition_key, '1-installation');
  assert.equal(chapter.metadata.url, '/docs/handbook/2026-10-12/installation/');
  assert.equal(chapter.metadata.build.list, 'local');
  assert.equal(chapter.metadata.aliases, undefined);
  assert.match(chapter.body, /\[Home\]\(\/docs\/handbook\/2026-10-12\/\)/);
  assert.match(chapter.body, /\[Self\]\(\/docs\/handbook\/2026-10-12\/installation\/#setup\)/);
  assert.match(f.read(`${base}/_index.md`), /\[Install\]\(\/docs\/handbook\/2026-10-12\/installation\/\)/);
  assert.deepEqual(fs.readFileSync(path.join(f.root, '.generated/doc-editions', base, 'config/diagram.png')), Buffer.from([0, 1, 2, 255]));
});

test('canonical links stay within snapshots without rewriting existing edition URLs', t => {
  const f = fixture(t);
  f.write('content/docs/tutorial.md', '---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\n[Self](https://www.openchami.org/docs/tutorial/#setup) [Old](/docs/tutorial/2025-10-06/)\n');
  f.commit(); f.git('tag', 'tutorial-2026-10-12'); generate(f.root);
  const body = parsePage(f.read(tutorial('2026-10-12')), 'snapshot').body;
  assert.match(body, /\[Self\]\(\/docs\/tutorial\/2026-10-12\/#setup\)/);
  assert.match(body, /\[Old\]\(\/docs\/tutorial\/2025-10-06\/\)/);
});

test('canonical URL rewriting preserves external hosts, queries, and path prefixes', t => {
  const f = fixture(t);
  const unchanged = [
    'https://example.org/docs/tutorial/',
    '//example.org/docs/tutorial/#setup',
    'https://example.org/?next=/docs/tutorial/',
    '/other/docs/tutorial/',
    'https://openchami.org.evil.example/docs/tutorial/',
    '/docs/tutorial/2025-10-06/',
  ];
  const canonical = ['/docs/tutorial/', 'https://openchami.org/docs/tutorial/', 'http://www.openchami.org/docs/tutorial/', '//openchami.org/docs/tutorial/'];
  f.write('content/docs/tutorial.md', `---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\n${unchanged.map(url => `[External](${url})`).join('\n')}\n${canonical.map(url => `[Self](${url}#setup)`).join('\n')}\n<a href="/docs/tutorial/">HTML</a>\n`);
  f.commit(); f.git('tag', 'tutorial-2026-10-12'); generate(f.root);
  const body = parsePage(f.read(tutorial('2026-10-12')), 'snapshot').body;
  for (const url of unchanged) assert.ok(body.includes(`[External](${url})`), url);
  assert.equal(body.split('[Self](/docs/tutorial/2026-10-12/#setup)').length - 1, canonical.length);
  assert.ok(body.includes('<a href="/docs/tutorial/2026-10-12/">HTML</a>'));
});

test('historical section sidebars retain removed and nested chapters in their edition', t => {
  const f = fixture(t, { handbook: { title: 'Handbook', source: 'content/docs/handbook', url: '/docs/handbook/', tagPrefix: 'handbook-' } });
  f.write('content/docs/handbook/_index.md', '---\ntitle: Handbook\nedition_family: handbook\nedition_id: latest\ncascade:\n  edition_family: handbook\n  edition_id: latest\n---\n');
  for (const name of ['first', 'removed', 'nested/child']) {
    f.write(`content/docs/handbook/${name}.md`, `---\ntitle: ${name}\n---\nChapter.\n`);
  }
  f.write('content/docs/handbook/nested/_index.md', '---\ntitle: Nested\n---\n');
  f.commit(); f.git('tag', 'handbook-2026-10-12');
  f.git('rm', 'content/docs/handbook/removed.md');
  f.write('content/docs/handbook/new.md', '---\ntitle: New\n---\n');
  generate(f.root);
  fs.cpSync(path.join(f.root, '.generated/doc-editions/content'), path.join(f.root, 'content'), { recursive: true });
  fs.cpSync(path.join(f.root, '.generated/doc-editions/data'), path.join(f.root, 'data'), { recursive: true });
  f.write('content/docs/tutorial.md', '---\ntitle: Tutorial\n---\n');
  f.write('hugo.toml', 'baseURL = "https://example.org/"\ndisableKinds = ["taxonomy", "term", "RSS", "sitemap"]\n');
  for (const name of ['single', 'list']) f.write(`layouts/_default/${name}.html`, '{{ partial "sidebar/section-menu.html" . }}');
  const repo = path.resolve(__dirname, '..');
  for (const name of ['sidebar/section-menu.html', 'docs/edition-context.html']) {
    f.write(`layouts/_partials/${name}`, fs.readFileSync(path.join(repo, 'layouts/_partials', name)));
  }
  f.write('layouts/_partials/sidebar/render-section-menu.html', fs.readFileSync(path.join(repo, 'node_modules/@thulite/doks-core/layouts/_partials/sidebar/render-section-menu.html')));
  execFileSync(path.join(repo, 'node_modules/.bin/hugo'), ['--source', f.root], { stdio: 'pipe' });
  for (const chapter of ['first', 'removed', 'nested/child']) {
    const html = fs.readFileSync(path.join(f.root, 'public/docs/handbook/2026-10-12', chapter, 'index.html'), 'utf8');
    for (const sibling of ['first', 'removed', 'nested/child']) assert.ok(html.includes(`href="/docs/handbook/2026-10-12/${sibling}/"`), sibling);
    assert.match(html, new RegExp(`aria-current="page"\\s+href="/docs/handbook/2026-10-12/${chapter}/"`));
    assert.ok(!html.includes('href="/docs/handbook/new/"'));
    assert.ok(!html.includes('href="/docs/handbook/first/"'));
  }
  const latest = fs.readFileSync(path.join(f.root, 'public/docs/handbook/first/index.html'), 'utf8');
  assert.ok(latest.includes('href="/docs/handbook/new/"'));
  assert.ok(!latest.includes('/2026-10-12/'));
});

test('invalid dates and reserved IDs fail without removing the previous output', t => {
  const f = fixture(t); generate(f.root);
  const prior = f.read('data/doc_editions.json');
  for (const tag of ['tutorial-2026-02-30', 'tutorial-latest']) {
    f.git('tag', tag);
    assert.throws(() => generate(f.root), /Invalid edition/);
    assert.equal(f.read('data/doc_editions.json'), prior);
    f.git('tag', '-d', tag);
  }
});

test('missing tagged source fails clearly rather than silently dropping an edition', t => {
  const f = fixture(t); f.git('rm', 'content/docs/tutorial.md'); f.commit(); f.git('tag', 'tutorial-2026-10-12');
  f.write('content/docs/tutorial.md', '---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\nLatest.');
  assert.throws(() => generate(f.root), /No documentation at/);
});

test('duplicate chapter URLs and unsafe source paths are rejected', t => {
  const f = fixture(t);
  f.config.families.tutorial.source = 'content/../secrets'; f.saveConfig();
  assert.throws(() => generate(f.root), /Invalid edition source path/);
  f.config.families.tutorial.source = 'content/docs/handbook'; f.config.families.tutorial.url = '/docs/handbook/'; f.saveConfig();
  f.write('content/docs/handbook/_index.md', '---\ntitle: Handbook\nedition_family: tutorial\nedition_id: latest\n---\n');
  for (const name of ['one', 'two']) f.write(`content/docs/handbook/${name}.md`, '---\ntitle: Chapter\nslug: duplicate\n---\n');
  f.commit(); f.git('tag', 'tutorial-2026-10-12');
  assert.throws(() => generate(f.root), /Duplicate edition URL/);
});

test('shallow checkouts fail with instructions to fetch history and tags', t => {
  const f = fixture(t);
  const clone = `${f.root}-shallow`;
  t.after(() => fs.rmSync(clone, { recursive: true, force: true }));
  execFileSync('git', ['clone', '--depth=1', `file://${f.root}`, clone], { stdio: 'pipe' });
  assert.throws(() => generate(clone), /git fetch --unshallow --tags/);
});

test('hosted-build fetcher obtains old tags and full history from a shallow checkout', t => {
  const f = fixture(t);
  f.git('tag', 'tutorial-2026-08-06');
  f.write('content/docs/tutorial.md', '---\ntitle: Tutorial\nedition_family: tutorial\nedition_id: latest\n---\nUpdated.\n');
  f.commit();
  const clone = `${f.root}-fetch`;
  t.after(() => fs.rmSync(clone, { recursive: true, force: true }));
  execFileSync('git', ['clone', '--depth=1', `file://${f.root}`, clone], { stdio: 'pipe' });
  const fetcher = path.join(clone, 'scripts/fetch-doc-tags.cjs');
  fs.copyFileSync(path.join(__dirname, '../scripts/fetch-doc-tags.cjs'), fetcher);
  execFileSync(process.execPath, [fetcher], { stdio: 'pipe' });
  assert.equal(execFileSync('git', ['rev-parse', '--is-shallow-repository'], { cwd: clone, encoding: 'utf8' }).trim(), 'false');
  assert.equal(execFileSync('git', ['tag', '--list'], { cwd: clone, encoding: 'utf8' }).trim(), 'tutorial-2026-08-06');
  f.git('tag', 'tutorial-2026-10-12');
  execFileSync(process.execPath, [fetcher], { stdio: 'pipe' });
  assert.match(execFileSync('git', ['tag', '--list'], { cwd: clone, encoding: 'utf8' }), /tutorial-2026-10-12/);
});
