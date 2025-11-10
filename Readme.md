# OpenCHAMI.org website

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
npm run preview
```

Clean (safe)
```bash
rm -rf public
```

## Organization

Most items can be changed directly by updating the markdown files in the [content/](content/) directory. The homepage is more custom and needs to be updated in HTML at [layouts/index.html](layouts/index.html).

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
