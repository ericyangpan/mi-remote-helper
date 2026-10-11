import { mkdir, readFile, writeFile, copyFile, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import sharp from "sharp";
import { createHash } from "node:crypto";
import { project, languages } from "../src/content.mjs";
const root = fileURLToPath(new URL("../", import.meta.url));
const repo = path.resolve(root, "..");
const out = path.join(root, "dist");
const origin = new URL(process.env.SITE_URL || "https://mi-remote.yangpan.com");
if (
  origin.protocol !== "https:" ||
  origin.pathname !== "/" ||
  origin.search ||
  origin.hash ||
  origin.username ||
  origin.password
)
  throw Error("SITE_URL must be an HTTPS origin");
const ga = process.env.GA_MEASUREMENT_ID || "";
if (ga && !/^G-[A-Z0-9]+$/.test(ga)) throw Error("Invalid GA_MEASUREMENT_ID");
const esc = (value) =>
  String(value).replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        ch
      ],
  );
const url = (route) => new URL(route, origin).href;
const paths = {
  mic: "M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0V5Z M5 10v2a7 7 0 0 0 14 0v-2 M12 19v3 M8 22h8",
  keys: "M3 4h18v16H3Z M7 8h1 M12 8h1 M17 8h1 M7 12h1 M12 12h1 M17 12h1 M8 16h8",
  sliders: "M4 6h16 M4 12h16 M4 18h16 M8 4v4 M16 10v4 M10 16v4",
  download: "M12 3v12 M7 10l5 5 5-5 M4 16v5h16v-5",
  arrow: "M4 12h16 M14 6l6 6-6 6",
  check: "m5 12 4 4L19 6",
  press: "M8 13V5a2 2 0 0 1 4 0v6l3-1 4 3-2 8H9l-5-7 2-2 2 1",
  release:
    "M9 14V7a2 2 0 0 1 4 0v5l3-1 4 3-2 7H10l-5-6 2-2 2 1 M3 5l2 2 M6 2l1 2 M18 3l-2 2",
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.arrow}"/></svg>`;
await rm(out, { recursive: true, force: true });
await mkdir(path.join(out, "assets"), { recursive: true });
const design = path.join(repo, "MiRemoteHelper/MiRemoteHelper/Design");
await copyFile(
  path.join(repo, "Design/AppIcon.svg"),
  path.join(out, "assets/icon.svg"),
);
for (const font of [
  "Poppins-Regular.ttf",
  "Poppins-SemiBold.ttf",
  "Arvo-Bold.ttf",
  "Poppins-OFL.txt",
  "Arvo-OFL.txt",
])
  await copyFile(
    path.join(design, "Fonts", font),
    path.join(out, "assets", font),
  );
for (const lang of ["en", "zh-CN"])
  for (const name of ["voice-input", "button-mapping"])
    for (const width of [1280, 2400])
      await sharp(path.join(repo, `docs/images/${name}.${lang}.png`))
        .resize({ width })
        .webp({ quality: 86 })
        .toFile(path.join(out, `assets/${name}.${lang}-${width}.webp`));
await sharp(path.join(repo, "Design/AppIcon.svg"))
  .resize(180, 180)
  .png()
  .toFile(path.join(out, "assets/apple-touch-icon.png"));
for (const language of ["en", "zh-CN"])
  await sharp(path.join(repo, `docs/images/voice-input.${language}.png`))
    .resize(1200, 630, { fit: "contain", background: "#f9f7f2" })
    .png()
    .toFile(path.join(out, `assets/social.${language}.png`));
const sourceFiles = {};
for (const file of ["site.css", "site.js"]) {
  const content = await readFile(path.join(root, "src", file));
  const hash = createHash("sha256").update(content).digest("hex").slice(0, 12);
  sourceFiles[file] = file.replace(".", `-${hash}.`);
  await writeFile(path.join(out, "assets", sourceFiles[file]), content);
}
let analyticsFile;
if (ga) {
  const content = `window.dataLayer = window.dataLayer || []; function gtag(){dataLayer.push(arguments);} gtag('js',new Date()); gtag('config',${JSON.stringify(ga)});\n`;
  analyticsFile = `analytics-${createHash("sha256").update(content).digest("hex").slice(0, 12)}.js`;
  await writeFile(path.join(out, "assets", analyticsFile), content);
}
const download = (c) =>
  `<a class="button primary" href="${project.download}">${icon("download")}${esc(c.download)}</a>`;
const brand =
  '<img src="/assets/icon.svg" width="40" height="40" alt=""><span>Mi Remote Helper</span>';
function head(c, noindex = false) {
  const schema = [
    {
      "@context": "https://schema.org",
      "@type": "WebSite",
      name: project.name,
      url: url("/"),
      inLanguage: ["en", "zh-CN"],
    },
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: project.name,
      operatingSystem: "macOS 14+",
      applicationCategory: "UtilitiesApplication",
      downloadUrl: project.download,
      softwareVersion: project.version,
      license: "https://www.gnu.org/licenses/gpl-3.0.html",
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
  ];
  return `<!doctype html><html lang="${c.lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(c.title)}</title><meta name="description" content="${esc(c.description)}">${noindex ? '<meta name="robots" content="noindex">' : `<link rel="canonical" href="${url(c.path)}"><link rel="alternate" hreflang="en" href="${url("/")}"><link rel="alternate" hreflang="zh-CN" href="${url("/zh/")}"><link rel="alternate" hreflang="x-default" href="${url("/")}">`}<meta property="og:type" content="website"><meta property="og:title" content="${esc(c.title)}"><meta property="og:description" content="${esc(c.description)}"><meta property="og:url" content="${url(c.path)}"><meta property="og:image" content="${url(`/assets/social.${c.screenshot}.png`)}"><meta name="twitter:card" content="summary_large_image"><meta name="theme-color" content="#f9f7f2"><link rel="icon" type="image/svg+xml" href="/assets/icon.svg"><link rel="apple-touch-icon" href="/assets/apple-touch-icon.png"><link rel="stylesheet" href="/assets/${sourceFiles["site.css"]}"><script type="application/ld+json">${JSON.stringify(schema).replace(/</g, "\\u003c")}</script><script defer src="/assets/${sourceFiles["site.js"]}"></script>${ga ? `<script async src="https://www.googletagmanager.com/gtag/js?id=${ga}"></script><script defer src="/assets/${analyticsFile}"></script>` : ""}</head><body><a class="skip" href="#main">${esc(c.skip)}</a><div class="wrap"><header class="header"><a class="brand" href="${c.path}">${brand}</a><nav aria-label="${c.lang === "en" ? "Main navigation" : "主导航"}"><a class="nav-section" href="${noindex ? "/" : ""}#features">${esc(c.nav[0])}</a><a class="nav-section" href="${noindex ? "/" : ""}#setup">${esc(c.nav[1])}</a><a href="${project.repository}">GitHub</a><a class="language" lang="${c.lang === "en" ? "zh-CN" : "en"}" href="${c.other}">${c.otherLabel}</a></nav></header>`;
}
function page(c) {
  return `${head(c)}<main id="main"><section class="hero"><div class="eyebrow">${esc(c.eyebrow)}</div><h1>${esc(c.headline[0])}<br><span>${esc(c.headline[1])}</span></h1><p class="hero-intro">${esc(c.intro)}</p><div class="actions">${download(c)}<a class="button secondary" href="${project.repository}">${esc(c.source)}${icon("arrow")}</a></div><p class="compatibility">${esc(c.compatibility)}</p></section><section class="showcase" aria-label="${esc(c.preview)}"><div class="preview-top"><div><h2 class="preview-heading">${esc(c.preview)}</h2><p>${esc(c.previewNote)}</p></div><div class="tabs" role="tablist" aria-label="${esc(c.preview)}">${c.tabs.map((label, i) => `<button id="preview-${i}" role="tab" aria-selected="${i === 0}" aria-controls="preview-panel" tabindex="${i === 0 ? 0 : -1}" data-preview="${i === 0 ? "voice-input" : "button-mapping"}" data-alt="${esc(c.screenshotAlt[i])}">${esc(label)}</button>`).join("")}</div></div><div class="screen" id="preview-panel" role="tabpanel" aria-labelledby="preview-0" tabindex="0"><img id="app-preview" src="/assets/voice-input.${c.screenshot}-2400.webp" srcset="/assets/voice-input.${c.screenshot}-1280.webp 1280w, /assets/voice-input.${c.screenshot}-2400.webp 2400w" sizes="(max-width:760px) calc(100vw - 44px), (max-width:1180px) calc(100vw - 64px), 1116px" width="2520" height="1824" alt="${esc(c.screenshotAlt[0])}" fetchpriority="high"></div><p class="preview-caption">${esc(c.previewCaption)}</p></section><section class="section" id="features"><p class="eyebrow">${esc(c.featuresEyebrow)}</p><h2>${esc(c.featuresTitle)}</h2><div class="feature-grid">${c.features.map(([n, title, body, symbol]) => `<article class="feature"><div class="feature-top"><span>${n}</span>${icon(symbol)}</div><h3>${esc(title)}</h3><p>${esc(body)}</p></article>`).join("")}</div></section><section class="section showcase" aria-labelledby="mapping-title"><div class="preview-top"><div><h2 id="mapping-title" class="preview-heading">${esc(c.mappingTitle)}</h2><p>${esc(c.mappingNote)}</p></div></div><div class="screen"><img id="mapping-preview" src="/assets/button-mapping.${c.screenshot}-2400.webp" srcset="/assets/button-mapping.${c.screenshot}-1280.webp 1280w, /assets/button-mapping.${c.screenshot}-2400.webp 2400w" sizes="(max-width:760px) calc(100vw - 44px), (max-width:1180px) calc(100vw - 64px), 1116px" width="2520" height="1824" alt="${esc(c.screenshotAlt[1])}" loading="lazy" decoding="async"></div></section><section class="workflow"><div><p class="eyebrow">${esc(c.workflowEyebrow)}</p><h2>${esc(c.workflowTitle)}</h2><p class="note">${esc(c.workflowNote)}</p></div><div class="gesture-list">${c.workflow.map((label, i) => `${i ? '<span class="gesture-arrow" aria-hidden="true">→</span>' : ""}<div class="gesture"><div class="symbol">${icon(["press", "mic", "release"][i])}</div>${esc(label)}</div>`).join("")}</div></section><section class="section" id="setup"><div class="setup-heading"><div><p class="eyebrow">${esc(c.setupEyebrow)}</p><h2>${esc(c.setupTitle)}</h2></div><p>${esc(c.setupIntro)}</p></div><div class="setup-content"><div><ol class="steps">${c.steps.map(([title, body], i) => `<li><span class="step-number" aria-hidden="true">${i + 1}</span><div><h3>${esc(title)}</h3><p>${esc(body)}</p></div></li>`).join("")}</ol><div class="setup-links"><a class="text-link" href="https://existential.audio/blackhole/">${esc(c.blackhole)}${icon("arrow")}</a><a class="text-link" href="${project.repository}/blob/main/README${c.lang === "en" ? "" : ".zh-CN"}.md">${esc(c.guide)}${icon("arrow")}</a></div></div><aside class="requirements"><h3>${esc(c.requirementsTitle)}</h3><ul>${c.requirements.map((item) => `<li>${icon("check")}<span>${esc(item)}</span></li>`).join("")}</ul><p>${esc(c.requirementsNote)}</p></aside></div></section><section class="section faq"><h2>${esc(c.faqTitle)}</h2><div class="faq-list">${c.faqs.map(([q, a]) => `<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join("")}</div></section><section class="closing"><h2>${esc(c.closing)}</h2><p>${esc(c.closingNote)}</p>${download(c)}</section></main><footer class="footer"><div class="footer-top"><a class="brand" href="${c.path}">${brand}</a><div class="footer-links"><a href="https://yangpan.com">${esc(c.builtBy)}</a><a href="${project.repository}/blob/main/LICENSE">${esc(c.license)}</a><a href="${project.repository}/blob/main/THIRD_PARTY_NOTICES${c.lang === "en" ? "" : ".zh-CN"}.md">${esc(c.notices)}</a></div></div><p class="footer-credits">${esc(c.credits)}</p></footer></div></body></html>`;
}
for (const c of Object.values(languages)) {
  const dir = path.join(out, c.path);
  await mkdir(dir, { recursive: true });
  await writeFile(path.join(dir, "index.html"), page(c));
}
await writeFile(
  path.join(out, "404.html"),
  `${head(languages.en, true)}<main id="main" class="not-found"><h1>${languages.en.notFound}</h1><div class="actions"><a class="button primary" href="/">${languages.en.back}</a><a class="button secondary" href="/zh/">中文首页</a></div></main></div></body></html>`,
);
await writeFile(
  path.join(out, "robots.txt"),
  `User-agent: *\nAllow: /\nSitemap: ${url("/sitemap.xml")}\n`,
);
await writeFile(
  path.join(out, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${Object.values(
    languages,
  )
    .map((c) => `<url><loc>${url(c.path)}</loc></url>`)
    .join("")}</urlset>\n`,
);
await writeFile(
  path.join(out, "_headers"),
  `/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: camera=(), microphone=(), geolocation=()\n  Content-Security-Policy: default-src 'self'; script-src 'self'${ga ? " https://www.googletagmanager.com" : ""}; style-src 'self'; img-src 'self'${ga ? " https://*.google-analytics.com https://*.googletagmanager.com" : ""}; font-src 'self'; connect-src 'self'${ga ? " https://*.google-analytics.com https://*.analytics.google.com https://*.googletagmanager.com" : ""}; object-src 'none'; base-uri 'none'; frame-ancestors 'none'\n/assets/*\n  Cache-Control: public, max-age=3600\n`,
);
console.log(
  `Built English and Chinese pages for ${origin.origin}; analytics ${ga ? "enabled" : "disabled"}.`,
);
