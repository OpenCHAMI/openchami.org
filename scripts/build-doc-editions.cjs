// SPDX-FileCopyrightText: © 2026 OpenCHAMI contributors
// SPDX-License-Identifier: MIT
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const YAML = require('yaml');

const ROOT = path.resolve(__dirname, '..');
const GENERATED = '.generated/doc-editions';
const PUBLISH_BRANCH = 'main';
const posix = path.posix;

function git(root, args, binary = false) {
  try {
    return execFileSync('git', args, { cwd: root, encoding: binary ? undefined : 'utf8', maxBuffer: 32 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    throw new Error(`Git could not read ${args.join(' ')}. Fetch full history and tags before building.\n${error.stderr?.toString().trim() || error.message}`);
  }
}

// Remote-tracking main wins so unpushed local commits cannot publish a tag.
function publishRef(root) {
  for (const ref of [`refs/remotes/origin/${PUBLISH_BRANCH}`, `refs/heads/${PUBLISH_BRANCH}`]) {
    try {
      execFileSync('git', ['rev-parse', '--verify', '--quiet', ref], { cwd: root, stdio: 'ignore' });
      return ref;
    } catch { /* Try the next location. */ }
  }
  throw new Error(`Git has no ${PUBLISH_BRANCH} branch to check documentation tags against. Run npm run docs:fetch-tags.`);
}

function onPublishBranch(root, tag) {
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', `refs/tags/${tag}^{commit}`, publishRef(root)], { cwd: root, stdio: ['ignore', 'ignore', 'pipe'] });
    return true;
  } catch (error) {
    if (error.status === 1) return false;
    throw error;
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
  // Without a slug, the site's :slug permalink falls back to the title, which edition URLs cannot reproduce.
  if (!/(?:^|\/)_index\.md$/.test(relative) && !metadata.slug) throw new Error(`${relative}: chapters require a slug in front matter`);
  const parts = key.split('/');
  if (metadata.slug) parts[parts.length - 1] = String(metadata.slug);
  if (parts.some(part => !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(part))) throw new Error(`Unsupported chapter path/slug: ${relative}`);
  return `${parts.join('/')}/`;
}

function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function rewriteRelative(root, page, pages, family, target) {
  const resolved = posix.normalize(posix.join(posix.dirname(page.source), target)).replace(/\/$/, '');
  const sibling = pages.find(item => item.source === resolved || item.source === `${resolved}/_index.md` || item.source === `${resolved}/index.md`);
  if (sibling) return sibling.url;
  // The theme resolves other links from the source path, then as URLs. Those stay valid inside a
  // section, but editions sit one level deeper, so links leaving the family need absolute targets.
  if (family.source && `${resolved}/`.startsWith(`${family.source}/`)) return null;
  const slash = target.endsWith('/') ? '/' : '';
  if (resolved.startsWith('content/') && [resolved, `${resolved}.md`, `${resolved}/_index.md`, `${resolved}/index.md`].some(name => fs.existsSync(path.join(root, name)))) {
    return `/${resolved.slice('content/'.length)}${slash}`;
  }
  const url = posix.resolve(page.liveURL, target);
  const chapter = pages.find(item => item.liveURL === `${url}/`);
  if (chapter) return chapter.url;
  return family.source && `${url}/`.startsWith(family.url) ? null : `${url}${slash}`;
}

function rewriteProse(text, root, page, pages, family) {
  for (const item of [...pages].sort((a, b) => b.liveURL.length - a.liveURL.length)) {
    const base = escaped(item.liveURL.replace(/\/$/, ''));
    // Match a complete URL token, never a path inside another host's URL. Trailing sentence
    // punctuation is not part of the URL. Only link destinations may drop their host: Markdown
    // autolinks and bare URLs stop being links without one.
    text = text.replace(new RegExp(`(^|[\\s("'<>])((?:https?:)?//(?:www\\.)?openchami\\.org)?${base}/?(?=[#?)"'>\\s]|[.,;:!]+(?:[\\s)"'>]|$)|$)`, 'g'), (_, boundary, host) => boundary + (host && !/[("']/.test(boundary) ? host : '') + item.url);
  }
  const rewrite = (match, open, href, close) => {
    if (/^(?:[a-z][a-z0-9+.-]*:|\/|#|<|(?:abbr|dfn)$)/i.test(href)) return match;
    const [, target, suffix] = href.match(/^([^?#]*)(.*)$/);
    const url = target && rewriteRelative(root, page, pages, family, target);
    return url ? `${open}${url}${suffix}${close}` : match;
  };
  return text.replace(/(\]\()([^\s)]+)([^)]*\))/g, rewrite).replace(/^( {0,3}\[(?!\^)[^\]]+\]:[ \t]*)(\S+)()/gm, rewrite);
}

// Readers copy code verbatim, so only prose is rewritten.
function mapProse(body, transform) {
  const output = [];
  const inline = text => {
    let last = 0;
    for (const span of text.matchAll(/(?<!`)(`+)(?!`)(?:(?!\n[ \t]*\n)[\s\S])*?(?<!`)\1(?!`)/g)) {
      output.push(transform(text.slice(last, span.index)), span[0]);
      last = span.index + span[0].length;
    }
    output.push(transform(text.slice(last)));
  };
  let prose = '';
  let fence = null;
  for (const line of body.match(/[^\n]*\n|[^\n]+$/g) || []) {
    const marker = line.match(/^[\s>]*(?:(?:[-*+]|\d+[.)])\s+)?(`{3,}|~{3,})([^\n]*)/);
    if (fence) {
      output.push(line);
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) fence = null;
    } else if (marker && !(marker[1][0] === '`' && marker[2].includes('`'))) {
      inline(prose);
      prose = '';
      fence = marker[1];
      output.push(line);
    } else {
      prose += line;
    }
  }
  inline(prose);
  return output.join('');
}

function rewriteLinks(body, root, page, pages, family) {
  return mapProse(body, text => rewriteProse(text, root, page, pages, family));
}

function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const name = path.join(directory, entry.name);
    if (entry.isDirectory()) return markdownFiles(name);
    return entry.name.endsWith('.md') ? [name] : [];
  });
}

// Validates live chapters on every build and returns the URL segments they occupy.
function liveSegments(root, source) {
  const base = path.join(root, source);
  return markdownFiles(base).flatMap(file => {
    const parsed = parsePage(fs.readFileSync(file, 'utf8'), path.relative(root, file));
    if (parsed.metadata.draft) return [];
    return pageSuffix(path.relative(base, file).split(path.sep).join('/'), parsed.metadata).split('/').slice(0, 1).filter(Boolean);
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
    // Edition IDs share a URL level with live chapters and section pagination.
    const reserved = new Set(source.endsWith('.md') ? [] : ['page', ...liveSegments(root, source)]);
    const editions = new Map();
    for (const entry of family.bootstrap || []) {
      validID(entry.id);
      if (editions.has(entry.id) || !/^[0-9a-f]{40}$/.test(entry.ref)) throw new Error(`Invalid bootstrap edition: ${familyID}/${entry.id}`);
      editions.set(entry.id, { ...entry, bootstrap: true });
    }
    for (const tag of tags.filter(tag => tag.startsWith(family.tagPrefix))) {
      if (!onPublishBranch(root, tag)) {
        console.warn(`Ignoring ${tag}: its commit is not on ${PUBLISH_BRANCH}.`);
        continue;
      }
      const id = tag.slice(family.tagPrefix.length);
      validID(id);
      const prior = editions.get(id) || {};
      // Matching tags replace only the pinned commit: a legacy source path must not change documents.
      editions.set(id, { ...prior, id, label: family.labels?.[id] || prior.label, ref: tag, tag });
    }
    const liveRef = `/${liveSource.replace(/^content\//, '').replace(/\/_index\.md$|\.md$/g, '')}`;
    registry[familyID] = { title: family.title, editions: [{ id: 'latest', label: 'Latest', pageRef: liveRef, url: family.url }] };
    const ordered = [...editions.values()].sort((a, b) => b.id.localeCompare(a.id, 'en', { numeric: true }));
    const replacements = family.bootstrapReplacements || [];
    const applied = new Set();
    for (const edition of ordered) {
      if (reserved.has(edition.id)) throw new Error(`Edition ID ${edition.id} collides with the live URL ${family.url}${edition.id}/`);
      const commit = git(root, ['rev-parse', '--verify', `${edition.ref}^{commit}`]).trim();
      const editionSource = safeSource(edition.source || source);
      const files = sourceFiles(root, commit, editionSource);
      const single = editionSource.endsWith('.md');
      const base = `docs/editions/${familyID}/${edition.id}`;
      const pages = files.filter(file => file.source.endsWith('.md')).map(file => ({ ...file, ...parsePage(file.bytes.toString('utf8'), file.source) })).filter(page => !page.metadata.draft).map(page => {
        const relative = single ? '_index.md' : posix.relative(editionSource, page.source);
        const suffix = single ? '' : pageSuffix(relative, page.metadata);
        const url = `${family.url}${edition.id}/${suffix}`;
        if (urls.has(url)) throw new Error(`Duplicate edition URL: ${url}`);
        urls.add(url);
        return { ...page, relative, key: single ? '' : pageKey(relative), url, liveURL: `${family.url}${suffix}`, target: single ? `${base}.md` : `${base}/${relative}` };
      });
      if (!pages.some(page => page.key === '')) throw new Error(`${edition.ref}: section requires a root _index.md`);
      for (const page of pages) {
        const metadata = { ...page.metadata, ...(page.key === '' ? edition.metadata : {}), url: page.url, edition_family: familyID, edition_id: edition.id, edition_key: page.key, edition_commit: commit, edition_source: page.source, exclude_search: true, seo: { ...page.metadata.seo, robots: 'noindex, follow' }, outputs: ['html'], build: { list: page.key === '' ? 'never' : 'local', render: 'always' } };
        delete metadata.aliases;
        delete metadata._build;
        if (!page.key && edition.aliases) metadata.aliases = edition.aliases;
        // Replacements are written against the source, so they run before links change.
        let body = page.body;
        if (edition.bootstrap) {
          for (const replacement of replacements) {
            if (body.includes(replacement.from)) applied.add(replacement);
            body = body.split(replacement.from).join(replacement.to);
          }
        }
        body = rewriteLinks(body, root, page, pages, { url: family.url, source: single ? null : editionSource });
        addFile(`content/${page.target}`, `---\n${YAML.stringify(metadata)}---\n${body}`);
      }
      for (const file of files.filter(file => !file.source.endsWith('.md'))) {
        if (!single) addFile(`content/${base}/${posix.relative(editionSource, file.source)}`, file.bytes);
      }
      // Each tag points to exactly the commit used for rendering, even if moved later.
      registry[familyID].editions.push({ id: edition.id, label: edition.label || edition.id, pageRef: `/${base}`, url: `${family.url}${edition.id}/`, commit, ...(edition.tag ? { tag: edition.tag } : { sourceRef: edition.ref }) });
    }
    // A tag may already contain a correction, so only fully pinned sources prove an entry stale.
    if (!ordered.some(edition => edition.bootstrap && edition.tag)) {
      const stale = replacements.find(replacement => !applied.has(replacement));
      if (stale) throw new Error(`Bootstrap replacement in ${familyID} matches no edition: ${JSON.stringify(stale.from)}`);
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
