# OpenCHAMI.org website

## Container (optional)

A container can be used to perform development.

For development:

```bash
docker run -p 1313:1313 -u node -it node:22 bash
```

For preview:

```bash
docker run -p 8080:8080 -u node -it node:22 bash
```

## To develop locally

1. Clone this repository
2. Install npm dependencies with `npm install`
3. Run the development server with `npm run dev`
4. Visit http://localhost:1313

_NB:_ To avoid branch conflicts, please use username/description-in-kebab-case for naming branches. 

```bash
git branch <github-username/description-in-kebab-case>
```

We delete branches after merges and release to our hosting provider manually once merges have been approved and tested locally.

## Common tasks

Install
```bash
npm install
```

Develop
```bash
npm run dev
```

Build (production)
```bash
npm run build
```

Preview production build
```bash
npm install http-server
npm run preview
```

Clean (safe)
```bash
rm -rf public
```

## Organization

Most items can be changed directly by updating the markdown files in the [content/](content/) directory. The homepage is more custom and needs to be updated in HTML at [layouts/index.html](layouts/index.html).

## Documentation editions from Git tags

Edit the Tutorial and Handbook normally on `main`. The **Version** selector keeps
**Latest** at the existing URL and adds editions from matching tags in this
website repository:

- `tutorial-2026-10-12` → `/docs/tutorial/2026-10-12/`
- `handbook-2026-11-01` → `/docs/handbook/2026-11-01/`

To publish an edition, commit and merge the documentation changes, then create an
annotated tag on that commit and push that specific tag. For example:

```bash
git tag -a tutorial-2026-10-12 -m "Tutorial edition 2026-10-12" <commit>
git push origin tutorial-2026-10-12
```

Published tags must stay fixed. Publish corrections under a new dated tag. The
S3 workflow rebuilds on matching tag pushes, checks out current `main`, and
renders **all** editions together using the current theme. Local and PR builds do
not deploy. Tags created on commits predating this workflow may require a normal
push to `main` to trigger deployment.

`npm run build`, `npm run dev`, and `npm run dev:drafts` first generate editions.
Generation is offline and requires a full Git checkout with the desired tags:

```bash
npm run docs:fetch-tags # fetch origin tags; unshallow the checkout if needed
npm run docs:prepare    # generate editions without running Hugo
npm run test:editions   # isolated Git-repository tests
npm run build
python3 scripts/check_doc_editions.py
```

The output lives under `.generated/doc-editions/`, is ignored by Git, and is
mounted into Hugo as content and data. Do not edit or commit generated snapshots.
Run `npm run docs:prepare` before invoking Hugo directly, and restart the dev
server after fetching or creating tags. The build fails on a shallow checkout,
missing tagged content, invalid dates/IDs, and conflicting chapter URLs rather
than silently omitting editions. The output is validated before it is replaced.
The Python output checker requires PyYAML (`python3 -m pip install 'PyYAML>=6,<7'`).

`scripts/doc-editions.config.yaml` defines independent document families, their
source paths, public URLs, and tag prefixes. Both files (Tutorial) and complete
sections (Handbook) are supported. Tag suffixes become stable URL IDs, ordered
newest-first for dates. Safe release names such as `tutorial-v0.2.0` also work;
optional `labels` keyed by edition ID customize display names without changing
URLs. Unrelated repository tags are ignored.

The live landing page must declare its `edition_family` and `edition_id: latest`.
For a section, cascade these fields to its chapters, as the Handbook does.
Generated editions receive hidden-list/search metadata, stable chapter URLs, and
source links to the exact Git commit. Chapter switching uses source paths
relative to the section root; matching chapters are retained, with the edition
landing page as fallback when a chapter is missing or renamed. Relative Markdown
chapter links and links to canonical
OpenCHAMI documentation URLs are rewritten into the tagged edition. Section
resources are copied from Git; global site assets and Hugo shortcodes use the
current site implementation. Historical documents must use YAML front matter.

The existing 2026-08-06 and 2025-10-06 Tutorial editions are migration entries
pinned to a full Git commit, with the legacy source path and redirect preserved.
These labels came from existing front matter; they do not claim an exact historic
publication date. A matching tag supersedes the pinned content while retaining
its label and alias. This migration preserves existing links without creating or
pushing historical tags. New editions require only tags, with no copied Markdown
or registry edits.

## Troubleshooting

Sometimes the renderer fails to delete expired pages from the cache. Stopping the server and deleting the [public](public/) directory before restarting is safe. If a build lock persists, remove `.hugo_build.lock` and retry.

This site uses [Doks](https://getdoks.org/) which has its own documentation for customization and organization of things like images.

## License and REUSE compliance

This repository follows the REUSE specification for licensing metadata.

- Primary license: MIT (see `LICENSE` and `LICENSES/MIT.txt`)
- Repository-wide licensing metadata: `.reuse/dep5`
- CI check: GitHub Actions workflow at `.github/workflows/reuse.yml`

To verify locally (optional):

```bash
# Install the REUSE tool (requires Python)
pipx install reuse  # or: pip install --user reuse

# From the repo root
reuse lint
```

Learn more: https://reuse.software/
