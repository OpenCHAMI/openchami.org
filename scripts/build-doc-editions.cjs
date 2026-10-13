// SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
// SPDX-License-Identifier: MIT
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const YAML = require('yaml');

const ROOT = path.resolve(__dirname, '..');
const GENERATED = '.generated/doc-editions';
const posix = path.posix;

function git(root, args, binary = false) {
  try {
    return execFileSync('git', args, { cwd: root, encoding: binary ? undefined : 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    throw new Error(`Git could not read ${args.join(' ')}. Fetch full history and tags before building.\n${error.stderr?.toString().trim() || error.message}`);
  }
}

function parsePage(text, source) {
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)([\s\S]*)$/);
  if (!match) throw new Error(`${source}: expected YAML front matter`);
  const metadata = YAML.parse(match[1], { uniqueKeys: true });
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) throw new Error(`${source}: invalid front matter`);
  return { metadata, body: match[2] };
}

function safeSource(source) {
  if (typeof source !== 'string' || !source.startsWith('content/') || source.includes('\\') || source.split('/').some(part => part === '..' || part === '.' || !part)) {
    throw new Error(`Invalid edition source path: ${source}`);
  }
  return source;
}

function validID(id) {
  if (typeof id !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(id) || id === 'latest') throw new Error(`Invalid edition ID: ${id}`);
  if (/^\d{4}-\d{2}-\d{2}$/.test(id) && (Number.isNaN(Date.parse(id)) || new Date(id).toISOString().slice(0, 10) !== id)) throw new Error(`Invalid edition date: ${id}`);
}

function pageKey(relative) {
  return relative.replace(/(?:^|\/)_?index\.md$/, '').replace(/\.md$/, '');
}

function pageSuffix(relative, metadata) {
  const key = pageKey(relative);
  if (!key) return '';
  const parts = key.split('/');
  if (metadata.slug) parts[parts.length - 1] = String(metadata.slug);
  if (parts.some(part => !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(part))) throw new Error(`Unsupported chapter path/slug: ${relative}`);
  return `${parts.join('/')}/`;
}

function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function rewriteLinks(body, source, pages) {
  for (const page of [...pages].sort((a, b) => b.liveURL.length - a.liveURL.length)) {
    const base = escaped(page.liveURL.replace(/\/$/, ''));
    body = body.replace(new RegExp(`(?:https?://(?:www\\.)?openchami\\.org)?${base}/?(?=[#)"'\\s]|$)`, 'g'), page.url);
  }
  // Keep relative links to sibling chapters within their tagged edition.
  return body.replace(/(\]\()([^\s)]+)([^)]*\))/g, (match, open, href, close) => {
    if (/^(?:[a-z]+:|\/|#)/i.test(href)) return match;
    const [target, fragment] = href.split('#', 2);
    const resolved = posix.normalize(posix.join(posix.dirname(source), target));
    const page = pages.find(item => item.source === resolved || item.source === `${resolved}/_index.md` || item.source === `${resolved}/index.md`);
    return page ? `${open}${page.url}${fragment ? `#${fragment}` : ''}${close}` : match;
  });
}

function sourceFiles(root, commit, source) {
  const entries = git(root, ['ls-tree', '-r', '-z', commit, '--', source]).split('\0').filter(Boolean);
  if (!entries.length) throw new Error(`No documentation at ${commit}:${source}`);
  return entries.map(entry => {
    const [header, name] = entry.split('\t');
    if (!header.startsWith('100') || !header.includes(' blob ')) throw new Error(`Unsupported Git entry: ${name}`);
    return { source: name, bytes: git(root, ['show', `${commit}:${name}`], true) };
  });
}

function write(root, name, value) {
  const target = path.join(root, name);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, value);
}

function generate(root = ROOT, configPath = path.join(root, 'scripts/doc-editions.config.yaml')) {
  const config = YAML.parse(fs.readFileSync(configPath, 'utf8'), { uniqueKeys: true });
  if (!config?.families || typeof config.families !== 'object') throw new Error('Edition configuration requires families');
  if (git(root, ['rev-parse', '--is-shallow-repository']).trim() === 'true') throw new Error('Documentation editions require full Git history. Run git fetch --unshallow --tags.');
  const tags = git(root, ['tag', '--list']).split('\n').filter(Boolean);
  const registry = {};
  const output = new Map();
  const usedPrefixes = new Set();
  const urls = new Set();
  const addFile = (name, bytes) => {
    if (output.has(name)) throw new Error(`Duplicate generated content path: ${name}`);
    output.set(name, bytes);
  };
  for (const [familyID, family] of Object.entries(config.families)) {
    if (!/^[a-z][a-z0-9-]*$/.test(familyID) || !family.title || !/^([a-z][a-z0-9-]*)-$/.test(family.tagPrefix || '') || [...usedPrefixes].some(prefix => prefix.startsWith(family.tagPrefix) || family.tagPrefix.startsWith(prefix))) throw new Error(`Invalid or duplicate family configuration: ${familyID}`);
    usedPrefixes.add(family.tagPrefix);
    const source = safeSource(family.source);
    if (!/^\/docs\/(?:[a-zA-Z0-9._-]+\/)+$/.test(family.url)) throw new Error(`Invalid family URL: ${family.url}`);
    const liveSource = source.endsWith('.md') ? source : `${source}/_index.md`;
    const live = parsePage(fs.readFileSync(path.join(root, liveSource), 'utf8'), liveSource);
    if (live.metadata.edition_family !== familyID || live.metadata.edition_id !== 'latest') throw new Error(`${liveSource} must declare edition_family: ${familyID} and edition_id: latest`);
    const editions = new Map();
    for (const entry of family.bootstrap || []) {
      validID(entry.id);
      if (editions.has(entry.id) || !/^[0-9a-f]{40}$/.test(entry.ref)) throw new Error(`Invalid bootstrap edition: ${familyID}/${entry.id}`);
      editions.set(entry.id, { ...entry, bootstrap: true });
    }
    for (const tag of tags.filter(tag => tag.startsWith(family.tagPrefix))) {
      const id = tag.slice(family.tagPrefix.length);
      validID(id);
      const prior = editions.get(id) || {};
      // Matching tags become authoritative, using the family's normal source.
      editions.set(id, { id, label: family.labels?.[id] || prior.label, aliases: prior.aliases, ref: tag, tag });
    }
    const liveRef = `/${liveSource.replace(/^content\//, '').replace(/\/_index\.md$|\.md$/g, '')}`;
    registry[familyID] = { title: family.title, editions: [{ id: 'latest', label: 'Latest', pageRef: liveRef, url: family.url }] };
    const ordered = [...editions.values()].sort((a, b) => b.id.localeCompare(a.id, 'en', { numeric: true }));
    for (const edition of ordered) {
      const commit = git(root, ['rev-parse', '--verify', `${edition.ref}^{commit}`]).trim();
      const editionSource = safeSource(edition.source || source);
      const files = sourceFiles(root, commit, editionSource);
      const single = editionSource.endsWith('.md');
      const base = `docs/editions/${familyID}/${edition.id}`;
      const pages = files.filter(file => file.source.endsWith('.md')).map(file => {
        const relative = single ? '_index.md' : posix.relative(editionSource, file.source);
        const parsed = parsePage(file.bytes.toString('utf8'), file.source);
        const suffix = single ? '' : pageSuffix(relative, parsed.metadata);
        const url = `${family.url}${edition.id}/${suffix}`;
        if (urls.has(url)) throw new Error(`Duplicate edition URL: ${url}`);
        urls.add(url);
        return { ...file, ...parsed, relative, key: single ? '' : pageKey(relative), url, liveURL: `${family.url}${suffix}`, target: single ? `${base}.md` : `${base}/${relative}` };
      }).filter(page => !page.metadata.draft);
      if (!pages.some(page => page.key === '')) throw new Error(`${edition.ref}: section requires a root _index.md`);
      for (const page of pages) {
        const metadata = { ...page.metadata, ...(page.key === '' ? edition.metadata : {}), url: page.url, edition_family: familyID, edition_id: edition.id, edition_key: page.key, edition_commit: commit, edition_source: page.source, exclude_search: true, build: { list: page.key === '' ? 'never' : 'local', render: 'always' } };
        delete metadata.aliases;
        delete metadata._build;
        if (!page.key && edition.aliases) metadata.aliases = edition.aliases;
        let body = rewriteLinks(page.body, page.source, pages);
        if (edition.bootstrap) {
          for (const replacement of family.bootstrapReplacements || []) body = body.split(replacement.from).join(replacement.to);
        }
        addFile(`content/${page.target}`, `---\n${YAML.stringify(metadata)}---\n${body}`);
      }
      for (const file of files.filter(file => !file.source.endsWith('.md'))) {
        if (!single) addFile(`content/${base}/${posix.relative(editionSource, file.source)}`, file.bytes);
      }
      // Each tag points to exactly the commit used for rendering, even if moved later.
      registry[familyID].editions.push({ id: edition.id, label: edition.label || edition.id, pageRef: `/${base}`, url: `${family.url}${edition.id}/`, commit, ...(edition.tag ? { tag: edition.tag } : { sourceRef: edition.ref }) });
    }
    if (ordered.length) addFile(`content/docs/editions/${familyID}/_index.md`, '---\ntitle: Documentation editions\nbuild: {list: never, render: never}\n---\n');
  }
  addFile('content/docs/editions/_index.md', '---\ntitle: Documentation editions\nbuild: {list: never, render: never}\n---\n');
  addFile('data/doc_editions.json', `${JSON.stringify(registry, null, 2)}\n`);
  // Validate everything before replacing the previous generated output.
  const destination = path.join(root, GENERATED);
  fs.rmSync(destination, { recursive: true, force: true });
  for (const [name, bytes] of output) write(destination, name, bytes);
  return registry;
}

if (require.main === module) {
  try {
    const registry = generate();
    const count = Object.values(registry).reduce((sum, family) => sum + family.editions.length - 1, 0);
    console.log(`Generated ${count} Git documentation editions in ${GENERATED}.`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { generate, parsePage };
