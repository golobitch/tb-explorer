# TigerBeetle Explorer landing page

Marketing site for [TigerBeetle Explorer](https://github.com/golobitch/tb-explorer), an independent, open-source, read-only macOS app for browsing TigerBeetle clusters.

It's a static [Astro](https://astro.build) site styled with Tailwind CSS v4.

## Development

Requires Node 20 or later.

```sh
npm install          # install dependencies
npm run dev          # dev server at http://localhost:4321
npm run build        # static build into dist/
npm run preview      # serve the dist/ build locally
```

Set `SITE_URL` when building for production so canonical and Open Graph URLs are absolute:

```sh
SITE_URL=https://example.com npm run build
```

## Deploying

`npm run build` writes a fully static site to `dist/`. Upload that folder to any static host, such as GitHub Pages, Cloudflare Pages, Netlify or an S3 bucket behind a CDN.

## Layout

```
src/pages/index.astro         page composition
src/components/sections/      Hero, Features, ReadOnly, Compatibility, OpenSource
src/components/elements/      Navbar, Footer
src/utils/data.ts             links, nav items and feature copy
src/assets/                   app screenshot and icon (optimized at build time)
public/                       favicons and Open Graph image
```

Page copy should stay in line with the app's [README](https://github.com/golobitch/tb-explorer#readme).

## Credits

Based on the [AgenceX Astro theme](https://github.com/uno-forge-hub/agency-landing-page-Astrojs) by John Kat, used under the MIT License. See [LICENCE.md](LICENCE.md).
