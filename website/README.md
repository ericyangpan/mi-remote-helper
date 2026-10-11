# Product website

**English** · [简体中文](README.zh-CN.md)

The bilingual product website is built as static HTML and deployed with Cloudflare Workers Static Assets. English lives at `/`, Simplified Chinese at `/zh/`. It is independent of the Xcode build.

## Local preview

Requires Node.js 22 or later. From this directory:

```sh
npm ci
npm run dev
```

Open [the local website](http://localhost:8787/). Source changes require rebuilding with `npm run build`; reload the browser afterwards.

```sh
npm run build
npm run check
npx wrangler deploy --dry-run
```

The checker verifies local links, language metadata, image variants, font licenses and security headers. A dry run validates the deployment configuration without publishing.

## Configuration and deployment

`src/content.mjs` contains both translations and the download version. Downloads point to the public GitHub Release. The build reads app screenshots from `../docs/images/`, the app icon from `../Design/`, and the bundled fonts and original licenses from the app's design directory. Generated WebP images, fonts and HTML go into ignored `dist/`; do not commit generated output.

`SITE_URL` sets the canonical HTTPS origin; its default is `https://mi-remote.yangpan.com`. This is a build default, not a published domain. `GA_MEASUREMENT_ID` optionally enables Google Analytics using an existing GA4 ID. Analytics is disabled when omitted. Set these variables during each build, including deployment:

```sh
SITE_URL=https://mi-remote.yangpan.com npm run deploy
# Optional analytics:
SITE_URL=https://mi-remote.yangpan.com GA_MEASUREMENT_ID=G-YOURID npm run deploy
```

`npm run deploy` publishes the site to the selected Cloudflare account and may update an existing Worker named `mi-remote-helper-website`. Authenticate with `npx wrangler login` first. Run Wrangler outside the sandbox. Before publishing, verify the destination account and update `SITE_URL` to the chosen domain. Bind the custom domain in Cloudflare after publishing. No domain route or account identifier is committed.

The site requires no dynamic handler or secrets. `_headers` supplies the security policy. HTML includes canonical URLs, reciprocal language alternates and structured data; `robots.txt` and `sitemap.xml` are generated. This layout assumes a domain root; hosting under a path requires adapting asset URLs and language routes.

## Rights

Website code uses the repository's GPL-3.0-only license. The app screenshots include third-party Xiaomi imagery, whose rights and removal notice are separate from GPL. Fonts retain their original SIL Open Font License files in the generated assets. See [third-party notices](../THIRD_PARTY_NOTICES.md).
