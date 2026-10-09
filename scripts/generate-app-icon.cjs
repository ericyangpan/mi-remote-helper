// Requires sharp on Node's module search path (for example via NODE_PATH).
// Run from any directory: node scripts/generate-app-icon.cjs
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const root = path.resolve(__dirname, '..');
  const svg = await fs.readFile(path.join(root, 'Design/AppIcon.svg'));
  const artwork = path.join(root, 'MiRemoteHelper/MiRemoteHelper/AppIcon.icon/Assets/AppIconArtwork.png');
  // Icon Composer owns the system mask, padding and legacy icon renditions.
  await sharp(svg, { density: 144 }).resize(1024, 1024).png().toFile(artwork);
  console.log('Updated Icon Composer artwork from Design/AppIcon.svg');
  for (const name of ['MenuBarRemote', 'MenuBarRemoteActive']) {
    const source = await fs.readFile(path.join(root, `Design/${name}.svg`));
    const assetDirectory = path.join(root, `MiRemoteHelper/MiRemoteHelper/Assets.xcassets/${name}.imageset`);
    await fs.mkdir(assetDirectory, { recursive: true });
    const representations = [];
    for (const scale of [1, 2]) {
      const filename = `${name}${scale === 2 ? '@2x' : ''}.png`;
      await sharp(source).resize(22 * scale, 22 * scale).png().toFile(path.join(assetDirectory, filename));
      representations.push({ filename, idiom: 'mac', scale: `${scale}x` });
    }
    await fs.writeFile(path.join(assetDirectory, 'Contents.json'), JSON.stringify({
      images: representations,
      info: { author: 'xcode', version: 1 },
      properties: { 'template-rendering-intent': 'template' },
    }, null, 2) + '\n');
    console.log(`Generated template menu bar asset ${name}`);
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
