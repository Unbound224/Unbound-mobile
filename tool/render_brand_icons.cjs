// Renders the approved brand SVGs to the PNG sources in assets/branding/ (art unchanged).
// Needs Node and Playwright's Chromium:  node tool/render_brand_icons.cjs brand/icon.svg brand/mark.svg assets/branding
// Then regenerate platform icons:      dart run flutter_launcher_icons
const fs = require('fs');
const { chromium } = require('playwright');
const [iconSvg, markSvg, outDir] = process.argv.slice(2);
const icon = fs.readFileSync(iconSvg, 'utf8');
const mark = fs.readFileSync(markSvg, 'utf8');
// iOS/legacy launcher: same art on a full-bleed square (the OS applies its own corner mask; no alpha allowed on iOS).
const square = icon.replace('rx="96" ', '');
const svgBody = (s) => s.replace(/<svg[^>]*>/, '').replace('</svg>', '');
const shots = [
  ['app_icon.png', 1024, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="1024" height="1024">${svgBody(square)}</svg>`, '#10092E'],
  // Adaptive foreground: mark inside the adaptive safe zone (the generated XML adds a 16% inset) on transparency; background colour comes from config.
  ['app_icon_foreground.png', 1024, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-80 -80 672 672" width="1024" height="1024">${svgBody(mark)}</svg>`, 'transparent'],
  ['splash_mark.png', 384, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="384" height="384">${svgBody(mark)}</svg>`, 'transparent'],
];
(async () => {
  const b = await chromium.launch();
  for (const [name, size, svg, bg] of shots) {
    const p = await b.newPage({ viewport: { width: size, height: size } });
    await p.setContent(`<html><body style="margin:0;background:${bg}">${svg}</body></html>`);
    await p.screenshot({ path: `${outDir}/${name}`, omitBackground: bg === 'transparent' });
    await p.close();
  }
  await b.close();
})();
