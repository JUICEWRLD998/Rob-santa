// Renders the store icons in icons.html to art/icons/<id>.png (512x512) with headless Chrome,
// plus art/icons/sheet.png (all of them side by side, and at a small size for a legibility check).
// Run: node tools/icons/render.mjs
// The fonts (Luckiest Guy, Fredoka One) are copied from the local Roblox Studio install into
// tools/icons/fonts/ (gitignored), so the icons use the same fonts as the game's UI.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..", "..");
const outDir = path.join(repo, "art", "icons");
const chrome = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const ids = ["vip", "bigsack", "speedboots", "wrapmaster", "bailout", "luckywrap", "blizzard",
  "coins_small", "coins_medium", "coins_large", "advent"];

function copyFonts() {
  const fontDir = path.join(here, "fonts");
  fs.mkdirSync(fontDir, { recursive: true });
  const versions = path.join(process.env.LOCALAPPDATA ?? "", "Roblox", "Versions");
  const candidates = fs.existsSync(versions)
    ? fs.readdirSync(versions).map((v) => path.join(versions, v, "content", "fonts"))
      .filter((dir) => fs.existsSync(path.join(dir, "LuckiestGuy-Regular.ttf")))
      .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)
    : [];
  for (const file of ["LuckiestGuy-Regular.ttf", "FredokaOne-Regular.ttf"]) {
    const target = path.join(fontDir, file);
    if (fs.existsSync(target)) continue;
    if (candidates.length === 0) throw new Error(`No Roblox install with ${file}; copy it into ${fontDir}`);
    fs.copyFileSync(path.join(candidates[0], file), target);
  }
}

function shoot(id, width, height, file) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "icons-chrome-"));
  const url = `${pathToFileURL(path.join(here, "icons.html")).href}?id=${id}`;
  try {
    execFileSync(chrome, [
      "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
      `--user-data-dir=${profile}`, `--window-size=${width},${height}`,
      "--virtual-time-budget=3000", `--screenshot=${file}`, url,
    ], { stdio: "pipe" });
  } finally {
    fs.rmSync(profile, { recursive: true, force: true });
  }
}

copyFonts();
fs.mkdirSync(outDir, { recursive: true });
for (const id of ids) {
  shoot(id, 512, 512, path.join(outDir, `${id}.png`));
  console.log(`art/icons/${id}.png`);
}
shoot("sheet", 2200, 1900, path.join(outDir, "sheet.png"));
console.log("art/icons/sheet.png");
