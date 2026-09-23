import { createRequire } from "node:module";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const require = createRequire(import.meta.url);
const sharp = require(process.env.STACKS_SHARP_MODULE ?? "sharp");
const webRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const appAssets = path.resolve(webRoot, "../Stacks/Assets.xcassets");
const source = path.join(webRoot, "assets/beanies-transparent-sheet.png");
const names = [
  "BrownScript", "GreenStripe", "RustVintage",
  "BlueLogo", "BurgundyBird", "CoralWave",
  "BlackColumbia", "LimeStripe", "BlackWool",
  "TealStripe", "MauveMonogram", "SlateBird",
  "NavyOval", "LilacMountain", "OrangeBird",
];
const columnEdges = [0, 310, 635, 941];
const rowEdges = [0, 360, 690, 1010, 1325, 1672];

for (const [index, name] of names.entries()) {
  const column = index % 3;
  const row = Math.floor(index / 3);
  const left = columnEdges[column];
  const top = rowEdges[row];
  const width = columnEdges[column + 1] - left;
  const height = rowEdges[row + 1] - top;
  const cell = await sharp(source)
    .extract({ left, top, width, height })
    .png()
    .toBuffer();
  const cutout = await sharp(cell)
    .trim({ background: "#00000000", threshold: 7 })
    .extend({ top: 8, right: 8, bottom: 8, left: 8, background: "#00000000" })
    .png()
    .toBuffer();
  const webAsset = `beanie-${name.replace(/[A-Z]/g, (letter, position) => `${position ? "-" : ""}${letter.toLowerCase()}`)}.webp`;
  await sharp(cutout).webp({ quality: 86, effort: 6 }).toFile(path.join(webRoot, "public/assets", webAsset));
  const imageSet = path.join(appAssets, `Beanie${name}.imageset`);
  await mkdir(imageSet, { recursive: true });
  await writeFile(path.join(imageSet, `Beanie${name}.png`), cutout);
  await writeFile(path.join(imageSet, "Contents.json"), JSON.stringify({
    images: [{ filename: `Beanie${name}.png`, idiom: "universal" }],
    info: { author: "xcode", version: 1 },
  }, null, 2) + "\n");
  console.log(`${name}: ${webAsset}`);
}
