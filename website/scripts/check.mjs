import { readFile, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import assert from "node:assert/strict";
const out = fileURLToPath(new URL("../dist/", import.meta.url));
for (const file of ["index.html", "zh/index.html", "404.html"]) {
  const html = await readFile(path.join(out, file), "utf8");
  assert(!html.includes("undefined"), `${file}: missing content`);
  assert.equal((html.match(/<h1>/g) || []).length, 1);
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
  assert.equal(new Set(ids).size, ids.length, `${file}: duplicate IDs`);
  assert(html.includes("application/ld+json"));
  for (const json of html.matchAll(
    /<script type="application\/ld\+json">(.*?)<\/script>/g,
  ))
    JSON.parse(json[1]);
  for (const [, ref] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
    if (ref.startsWith("#")) {
      assert(
        html.includes(`id="${ref.slice(1)}"`),
        `${file}: missing anchor ${ref}`,
      );
      continue;
    }
    if (!ref.startsWith("/")) continue;
    const [route, fragment] = ref.split("#");
    const target = path.join(
      out,
      route.endsWith("/") ? `${route}index.html` : route,
    );
    if (fragment)
      assert((await readFile(target, "utf8")).includes(`id="${fragment}"`));
    assert((await stat(target)).isFile(), `${file}: missing ${ref}`);
  }
  if (file !== "404.html") {
    assert(html.includes('hreflang="zh-CN"'));
    assert(html.includes('rel="canonical"'));
    const language = file.startsWith("zh/") ? "zh-CN" : "en";
    assert(html.includes(`<html lang="${language}">`));
    assert(html.includes(`/assets/social.${language}.png`));
    assert(
      html.includes(
        `id="mapping-preview" src="/assets/button-mapping.${language}-2400.webp"`,
      ),
    );
    assert(html.includes(">Pan YANG</a>"));
  }
  for (const [, candidates] of html.matchAll(/srcset="([^"]+)"/g))
    for (const candidate of candidates.split(","))
      assert(
        (await stat(path.join(out, candidate.trim().split(/\s+/)[0]))).isFile(),
      );
  const stylesheet = html.match(/rel="stylesheet" href="([^"]+)"/)[1];
  const css = await readFile(path.join(out, stylesheet), "utf8");
  for (const [, asset] of css.matchAll(/url\(["']?([^"')]+)["']?\)/g))
    assert(
      (await stat(path.join(out, asset))).isFile(),
      `Missing CSS asset ${asset}`,
    );
}
for (const language of ["en", "zh-CN"])
  for (const image of ["voice-input", "button-mapping"])
    for (const size of [1280, 2400])
      assert(
        (await stat(path.join(out, `assets/${image}.${language}-${size}.webp`)))
          .size > 1000,
      );
for (const license of ["Arvo-OFL.txt", "Poppins-OFL.txt"])
  assert(
    (await readFile(path.join(out, "assets", license), "utf8")).includes(
      "SIL OPEN FONT LICENSE",
    ),
  );
assert(
  (await readFile(path.join(out, "_headers"), "utf8")).includes(
    "frame-ancestors 'none'",
  ),
);
console.log(
  "Checked bilingual pages, local links, metadata, screenshots, font licenses and security headers.",
);
