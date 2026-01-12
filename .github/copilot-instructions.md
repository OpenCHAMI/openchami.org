# OpenCHAMI.org Copilot Instructions

## Project Overview

**OpenCHAMI.org** is a Hugo-based static documentation site for the [OpenCHAMI project](https://openchami.org), an open-source HPC system management platform. The site uses the **Doks theme** (via `@hyas/doks-core`) to build and deploy technical documentation, blog posts, events, and community contributor profiles.

**Key Tech Stack:**
- Hugo (0.123.7) for static site generation
- Node.js + pnpm for dependency management
- SCSS/CSS for styling (with Tabler Icons)
- Netlify for hosting and CI/CD
- REUSE specification for licensing compliance

## Critical Developer Workflows

### Local Development
```bash
npm install              # Install dependencies (includes Hugo)
npm run dev             # Start dev server at http://localhost:1313
npm run dev:drafts      # Include draft pages (--buildDrafts)
npm run build           # Production build
npm run preview         # Preview production build locally
```

### Content Management
```bash
npm run create path/to/content    # Create new content with archetype scaffolding
npm run lint                       # Run all linters (scripts, styles, markdown)
npm run clean                      # Remove build artifacts and caches
```

### Cleaning Build Issues
The site uses Hugo's build cache which can occasionally cause stale content. If pages don't update or the build fails unexpectedly:
```bash
rm -rf public resources .hugo_build.lock
npm run dev  # Restart server
```

## Content Organization & Conventions

### Directory Structure
- **`content/`** – All markdown content (main source of truth)
  - `blog/` – Blog posts and articles (multiple subdirectories for organization)
  - `docs/` – Technical documentation, guides, architecture
  - `events/` – Conferences and community events
  - `contributors/` – Community member profiles
  - `announcements/` – Press releases and major announcements
  - `about-us/` – General company/project information
  - `news/` – News items
  
- **`layouts/`** – Hugo templates (mostly inherited from Doks)
  - `index.html` – Custom homepage (modified extensively)
  - `_default/`, `docs/`, `partials/`, `shortcodes/`

- **`config/_default/`** – Hugo configuration
  - `hugo.toml` – Core Hugo settings (title, baseURL, outputs)
  - `params.toml` – Theme parameters and Doks customization
  - `languages.toml` – Multilingual config (single language currently)
  - `module.toml` – Asset mounting (mounts node_modules resources)
  - `markup.toml` – Markdown parsing settings

- **`assets/`** – SCSS, JavaScript, images, SVGs (compiled and bundled)

### Front Matter Conventions

**Blog Posts & Documentation:**
```toml
+++
title = "Post Title"
description = "Short summary for SEO"
date = 2024-01-15T10:00:00+00:00
lastmod = 2024-01-15T10:00:00+00:00
draft = false
weight = 50  # Sort order (lower = earlier)
contributors = ["GitHub Username"]
+++
```

**Key Fields:**
- `date` – Publication date (ISO 8601 format)
- `draft` – Set to `true` to hide from production (visible with `npm run dev:drafts`)
- `weight` – Controls ordering in lists and navigation (not always present)
- `contributors` – List of GitHub usernames
- `homepage` – If `true`, featured on homepage (used sparingly)

### Taxonomies
- **Contributors** – Defined in `config/_default/hugo.toml` as taxonomy `contributors`
- **Tags & Categories** – Auto-generated from content organization

## Key Files & Patterns

### Homepage Customization
[layouts/index.html](layouts/index.html) – Heavily customized HTML (not inherited from Doks):
- Three-column feature section (Security, Simplicity, Modularity)
- Call-to-action buttons linking to `/docs/tutorial/`
- Newsletter signup form (Mailerlite integration)
- YouTube video embed shortcode
- **Do NOT edit Doks theme files directly** – customize via parameters in `config/`

### Hugo Configuration Priorities
Hugo loads config in this order (most specific wins):
1. `config/` (base)
2. `config/_default/` (default environment)
3. `config/production/` or `config/next/` (environment-specific)
4. Command-line flags override everything

### Theme Inheritance
- **Base theme**: `@hyas/doks-core` (npm package in `node_modules/`)
- **Customization points**:
  - Override Doks parameters in `config/_default/params.toml`
  - Add custom layouts/partials in `layouts/` (they shadow theme files)
  - Custom SCSS in `assets/scss/` (mounted to override theme CSS)
  - Example: `flexSearch`, `navbarSticky`, `colorMode` parameters control theme behavior

## Search & Navigation Configuration

The site uses **FlexSearch** for full-text search:
- Index generated in JSON format (`hugo_stats.json`, `search-index.json`)
- Configured in `params.toml`: `searchLimit = 99`, `indexSummary = false`
- Excludes content types via `searchExclTypes` (customize as needed)
- Navigation menus in `config/_default/menus/`

## Deployment & Hosting

**Netlify Configuration** ([netlify.toml](netlify.toml)):
- Build command: `pnpm build`
- Publish directory: `public/`
- Environment contexts for production, deploy-preview, branch-deploy, and "next" branch
- Node version: 18.16.1, NPM: 9.5.1

**Manual Deployment Workflow:**
1. Merge to main branch
2. Local testing required before merge (no auto-deploy on PR)
3. Manual release to hosting after approval
4. Deploy via `npm run deploy` (requires S3 credentials)

## Licensing & REUSE Compliance

This project follows the **REUSE specification** (https://reuse.software/):
- Primary license: MIT (`LICENSE`, `LICENSES/MIT.txt`)
- Metadata: `REUSE.toml` in repo root
- All files implicitly licensed MIT by `REUSE.toml` aggregate annotation
- CI check: `.github/workflows/reuse.yml` validates compliance
- To verify: `reuse lint` (requires Python + REUSE tool)

**No need to add license headers** to markdown files – covered by aggregate rule.

## Linting & Code Quality

**Lint Commands:**
- `npm run lint` – Run all linters
- `npm run lint:scripts` – ESLint (JavaScript in `assets/js/`)
- `npm run lint:styles` – Stylelint (SCSS in `assets/scss/`)
- `npm run lint:markdown` – Markdownlint (all `.md` files)

**Cache Management:** Linters cache results in `.eslintcache`, `.stylelintcache`. Use `npm run clean:lint` to reset.

## Branch & Contribution Workflow

- **Branch naming**: `<github-username>/<kebab-case-description>` (enforced by convention)
- **Merge strategy**: Branches deleted after merge; no automatic deploy
- **Testing**: Build locally (`npm run build`) and preview before PR
- **PR validation**: `.github/workflows/validate_pr.yml` runs build check on every PR

## Common Tasks & Patterns

### Adding a Blog Post
1. Create directory: `content/blog/<slug>/`
2. Create `_index.md` with front matter (use archetype: `npm run create blog/<slug>`)
3. Add additional pages as needed (e.g., `introduction.md` for sub-sections)
4. Reference images relative to the directory

### Adding Documentation
- Place in `content/docs/<section>/`
- Use weight to control order
- Link to other docs with relative paths (Hugo rewrites them)
- Include in navigation via `config/_default/menus/`

### Adding Events
- Create in `content/events/<type>/<year>/`
- Example: `content/events/Conferences/2026/HPSFCon26.md`
- Can use `layout = "cards"` for special card-based display

### Custom Shortcodes
Available Doks shortcodes:
- `{{< youtube VIDEO_ID >}}` – Embed YouTube videos
- Check `layouts/shortcodes/` for others

## GitHub Actions Workflows

- **`validate_pr.yml`** – Runs `npm install` + `npm run build` on PRs (blocks merge if build fails)
- **`reuse.yml`** – Validates REUSE compliance
- **`S3_Deploy_Hugo.yml`** – Handles production S3 deployment

## Debugging Tips

**Hugo not found?** Clear install cache:
```bash
npm run clean:install && npm install
```

**Stale content in dev server?** 
```bash
rm -rf public resources .hugo_build.lock && npm run dev
```

**Build passes locally but fails in CI?** Check:
- Node version (18.16.1 on Netlify, verify locally)
- pnpm version (>= 8.10.0)
- Hugo version in `package.json` → `otherDependencies.hugo`
- All dependencies installed: `npm install`

**CSS/JS not updating?** Clear asset cache:
```bash
npm run clean && npm install && npm run dev
```
