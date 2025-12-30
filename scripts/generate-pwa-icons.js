const path = require('path');
const fs = require('fs');

async function main() {
  // jimp is devDependency; used only for generating icon files.
  const { Jimp, HorizontalAlign, VerticalAlign } = require('jimp');

  const src = path.join(__dirname, '..', 'assets', 'img', 'logo', 'logoprincipal.png');
  const outDir = path.join(__dirname, '..', 'assets', 'img', 'pwa');

  await fs.promises.mkdir(outDir, { recursive: true });

  const img = await Jimp.read(src);
  const sizes = [180, 192, 512];

  for (const size of sizes) {
    const out = path.join(outDir, `icon-${size}.png`);
    const clone = img.clone();
    await clone.contain({
      w: size,
      h: size,
      align: HorizontalAlign.CENTER | VerticalAlign.MIDDLE,
      background: 0x00000000,
    });
    await clone.write(out);
  }

  // Maskable icons: add padding so icon doesn't get clipped.
  for (const size of sizes) {
    if (size === 180) continue;
    const out = path.join(outDir, `icon-maskable-${size}.png`);
    const base = await Jimp.read(src);

    const padding = Math.round(size * 0.15);
    const canvas = new Jimp({ width: size, height: size, color: 0x00000000 });

    await base.contain({
      w: size - padding * 2,
      h: size - padding * 2,
      align: HorizontalAlign.CENTER | VerticalAlign.MIDDLE,
      background: 0x00000000,
    });

    canvas.composite(base, padding, padding);
    await canvas.write(out);
  }

  console.log('PWA icons generated in assets/img/pwa');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
