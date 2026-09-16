# TigerBeetle Explorer landing page

Marketing site for [TigerBeetle Explorer](https://github.com/golobitch/tb-explorer), an independent, open-source, read-only macOS app for browsing TigerBeetle clusters.

It's a static [Astro](https://astro.build) site styled with Tailwind CSS v4.

## Development

Requires Node 20 or later.

```sh
npm install          # install dependencies
npm run dev          # dev server at http://localhost:4321/tb-explorer/
npm run build        # static build into dist/
npm run preview      # serve the dist/ build at http://localhost:4321/tb-explorer/
```

The site is configured for its GitHub Pages address, `https://golobitch.github.io/tb-explorer/`. That's why it's served under `/tb-explorer/` locally too. To host it elsewhere, override both values at build time:

```sh
SITE_URL=https://example.com BASE_PATH=/ npm run build
```

Links to public files and pages go through `withBase()` in `src/lib/url.ts`, so they keep working under any base path.

## Deploying

The site lives in the `website/` folder of the [tb-explorer](https://github.com/golobitch/tb-explorer) repo. The `pages` workflow there builds it and deploys `dist/` to GitHub Pages on every push to `main` that touches `website/`. It can also be run by hand from the Actions tab.

## Layout

```
src/pages/index.astro         page composition
src/components/sections/      Hero, Features, ReadOnly, Compatibility, OpenSource
src/components/elements/      Navbar, Footer
src/utils/data.ts             links, nav items and feature copy
src/lib/url.ts                base-path aware links
src/assets/                   app screenshot and icon (optimized at build time)
public/                       favicons and Open Graph image
```

Page copy should stay in line with the app's [README](https://github.com/golobitch/tb-explorer#readme).

## Credits

Based on the [AgenceX Astro theme](https://github.com/uno-forge-hub/agency-landing-page-Astrojs) by John Kat, used under the MIT License. See [LICENCE.md](LICENCE.md).
