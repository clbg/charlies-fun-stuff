import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";
import { loadFonts, renderCardToSvg, CARD_WIDTH } from "./render.mjs";

function parseArgs(argv) {
  const args = {
    input: "input/week.sample.json",
    out: "output/sample-week",
    debugSvg: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--") {
      continue;
    } else if (token === "--input") {
      args.input = argv[i + 1];
      i += 1;
    } else if (token === "--out") {
      args.out = argv[i + 1];
      i += 1;
    } else if (token === "--debug-svg") {
      args.debugSvg = true;
    } else {
      throw new Error(`Unknown argument: ${token}`);
    }
  }

  return args;
}

function assertWeekShape(payload) {
  if (!payload || typeof payload !== "object") {
    throw new Error("Input must be a JSON object.");
  }
  if (!payload.week || typeof payload.week.slug !== "string" || !payload.week.slug) {
    throw new Error("Input must include week.slug.");
  }
  if (!Array.isArray(payload.cards) || payload.cards.length === 0) {
    throw new Error("Input must include a non-empty cards array.");
  }
  for (const card of payload.cards) {
    if (!card.slug || !card.title || !Array.isArray(card.schedule)) {
      throw new Error(`Card is missing required fields: ${JSON.stringify(card)}`);
    }
    for (const item of card.schedule) {
      if (typeof item === "string") {
        continue;
      }
      if (!item || typeof item !== "object" || !item.title) {
        throw new Error(`Schedule item is missing required title: ${JSON.stringify(item)}`);
      }
    }
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectRoot = path.dirname(fileURLToPath(import.meta.url));
  const root = path.resolve(projectRoot, "..");
  const inputPath = path.resolve(root, args.input);
  const outputDir = path.resolve(root, args.out);
  const debugDir = path.join(outputDir, "debug");

  const payload = JSON.parse(await readFile(inputPath, "utf8"));
  assertWeekShape(payload);

  await mkdir(outputDir, { recursive: true });
  if (args.debugSvg) {
    await mkdir(debugDir, { recursive: true });
  }

  const fonts = await loadFonts(root);
  await writeFile(
    path.join(outputDir, "input.snapshot.json"),
    `${JSON.stringify(payload, null, 2)}\n`,
    "utf8",
  );

  for (const card of payload.cards) {
    const svg = await renderCardToSvg(card, fonts);
    if (args.debugSvg) {
      await writeFile(path.join(debugDir, `${card.slug}.svg`), svg, "utf8");
    }

    const resvg = new Resvg(svg, {
      fitTo: {
        mode: "width",
        value: CARD_WIDTH,
      },
    });
    const pngData = resvg.render().asPng();
    await writeFile(path.join(outputDir, `${card.slug}.png`), pngData);
  }

  process.stdout.write(
    `Rendered ${payload.cards.length} cards for ${payload.week.slug} into ${outputDir}\n`,
  );
}

await main();
