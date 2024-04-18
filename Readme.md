# OpenCHAMI.org website

## To develop locally

1. Clone this repository
2. Install npm dependencies with `npm install`
3. Run the development webserver with `npm run dev`
4. visit http://localhost:1313 to see your progress

_NB:_ To avoid branch conflicts, please use username/description-in-kebab-case for naming branches. 

```bash
git branch <github-username/description-in-kebab-case>
```

We delete branches after merges and release to our hosting provider manually once merges have been approved and tested locally

## Organization

Most items can be changed directly by updating the markdown files in the [content/](content/) directory.  The homepage is more custom and needs to be updated in html format in [layouts/_index.html](layouts/index.html).

## Troubleshooting

Sometimes the renderer fails to delete expired pages from the cache.  Stopping the webserver and deleting the [public](/public/) directory before restarting is perfectly safe.

This site uses [Doks](https://getdoks.org/) which has its own documentation for customization and organization of things like images.
