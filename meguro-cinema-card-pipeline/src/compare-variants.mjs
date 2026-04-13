import React from "react";
import satori from "satori";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

const h = React.createElement;
const W = 1080;
const H = 1440;

function trunc(t, n) {
  if (!t) return "";
  return t.length <= n ? t : t.slice(0, n - 1).trimEnd() + "…";
}

function normItems(items) {
  return (items ?? []).slice(0, 8).map((item) => {
    if (typeof item === "string")
      return { time: "", title: trunc(item, 44), meta: "", note: "" };
    return {
      time: trunc(item.time ?? "", 22),
      title: trunc(item.title ?? "", 30),
      meta: trunc(item.meta ?? "", 52),
      note: trunc(item.note ?? "", 36),
    };
  });
}

async function loadFonts(root) {
  const nm = path.join(root, "node_modules");
  const entries = [
    { name: "Noto Sans JP", weight: 400, style: "normal", file: "@fontsource/noto-sans-jp/files/noto-sans-jp-japanese-400-normal.woff" },
    { name: "Noto Sans JP", weight: 700, style: "normal", file: "@fontsource/noto-sans-jp/files/noto-sans-jp-japanese-700-normal.woff" },
    { name: "Noto Sans SC", weight: 400, style: "normal", file: "@fontsource/noto-sans-sc/files/noto-sans-sc-chinese-simplified-400-normal.woff" },
    { name: "Noto Sans SC", weight: 700, style: "normal", file: "@fontsource/noto-sans-sc/files/noto-sans-sc-chinese-simplified-700-normal.woff" },
    { name: "Inter", weight: 400, style: "normal", file: "@fontsource/inter/files/inter-latin-400-normal.woff" },
    { name: "Inter", weight: 700, style: "normal", file: "@fontsource/inter/files/inter-latin-700-normal.woff" },
  ];
  return Promise.all(
    entries.map(async (e) => ({
      name: e.name,
      weight: e.weight,
      style: e.style,
      data: await readFile(path.join(nm, e.file)),
    })),
  );
}

// --- Sample data (Monday 3/30, 6 items) ---
const card = {
  slug: "2026-03-30",
  kind: "daily",
  dateLabel: "MONDAY",
  weekLabel: "2026-03-30",
  title: "目黑电影院 3/30 周一",
  subtitle: "独立片 + 类型片 + 音乐纪录片的一天",
  schedule: [
    { time: "10:00-12:10", title: "ミーツ・ザ・ワールド", meta: "遇见世界 / Meets the World", note: "开馆 9:30" },
    { time: "12:20-14:30", title: "愚か者の身分", meta: "愚者的身份 / BAKA's Identity | 豆瓣 6.9" },
    { time: "14:40-16:50", title: "ミーツ・ザ・ワールド", meta: "遇见世界 / Meets the World" },
    { time: "17:00-19:00", title: "ジェイコブス・ラダー 4K", meta: "异世浮生 / Jacob's Ladder | 豆瓣 7.6" },
    { time: "19:10-20:50", title: "テレビの中に入りたい", meta: "荧屏在发光 / I Saw the TV Glow | 豆瓣 6.8" },
    { time: "21:00-23:00", title: "レッド・ツェッペリン：ビカミング", meta: "成为齐柏林飞艇 / Becoming Led Zeppelin | 豆瓣 7.2" },
  ],
  highlights: ["异世浮生 7.6", "荧屏在发光 6.8", "开馆 9:30", "晚场适合连看"],
  footer: "目黑电影院官方排片",
};

// ============================================================
//  A — Editorial: white, typographic, thin-rule rhythm
// ============================================================
function editorialCard(c, fonts) {
  const items = normItems(c.schedule);
  const bg = "#FAFAF7";
  const fg = "#1C1917";
  const accent = "#8B6D4A";
  const muted = "#908980";
  const ruleLine = "#DDD9D2";
  const ff = '"Noto Sans JP", "Noto Sans SC", "Inter"';
  const ffL = '"Inter", "Noto Sans JP", "Noto Sans SC"';

  const hr = (key) =>
    h("div", { key, style: { width: "100%", height: 1, backgroundColor: ruleLine } });

  // schedule rows interleaved with thin rules
  const rows = [];
  items.forEach((item, i) => {
    if (i > 0) rows.push(hr(`rule-${i}`));
    rows.push(
      h("div", { key: `s-${i}`, style: { display: "flex", flexDirection: "column", gap: 5, padding: "18px 0" } }, [
        h("div", { key: "row", style: { display: "flex", width: "100%", alignItems: "baseline", gap: 16 } }, [
          h("div", { key: "t", style: { display: "flex", minWidth: 155, fontSize: 18, fontWeight: 700, letterSpacing: 1, color: accent, fontFamily: ffL } }, item.time),
          h("div", { key: "n", style: { display: "flex", flex: 1, fontSize: 26, fontWeight: 700, lineHeight: 1.2, fontFamily: ff } }, item.title),
        ]),
        item.meta ? h("div", { key: "m", style: { display: "flex", fontSize: 20, lineHeight: 1.35, color: "#5A534C", fontFamily: ff, paddingLeft: 171 } }, item.meta) : null,
        item.note ? h("div", { key: "o", style: { display: "flex", fontSize: 16, color: accent, fontFamily: ff, paddingLeft: 171 } }, item.note) : null,
      ]),
    );
  });

  const hlText = (c.highlights ?? []).join("  ·  ");

  return satori(
    h("div", { style: { display: "flex", flexDirection: "column", width: W, height: H, padding: "52px 64px", backgroundColor: bg, color: fg, fontFamily: ff, justifyContent: "space-between" } }, [
      // — header —
      h("div", { key: "hd", style: { display: "flex", flexDirection: "column", gap: 16 } }, [
        h("div", { key: "b", style: { display: "flex", fontSize: 15, fontWeight: 700, letterSpacing: 5, color: muted, fontFamily: ffL } }, "MEGURO CINEMA"),
        hr("hr-top"),
        h("div", { key: "d", style: { display: "flex", fontSize: 17, fontWeight: 700, letterSpacing: 6, color: accent, fontFamily: ffL, paddingTop: 4 } }, c.dateLabel),
        h("div", { key: "ti", style: { display: "flex", fontSize: 52, fontWeight: 700, lineHeight: 1.1, letterSpacing: -1 } }, trunc(c.title, 30)),
        h("div", { key: "w", style: { display: "flex", fontSize: 17, fontWeight: 600, letterSpacing: 2, color: accent, fontFamily: ffL } }, c.weekLabel),
        h("div", { key: "su", style: { display: "flex", fontSize: 22, lineHeight: 1.4, color: "#5A534C" } }, trunc(c.subtitle, 52)),
      ]),
      // — schedule —
      h("div", { key: "sc", style: { display: "flex", flexDirection: "column" } }, [
        h("div", { key: "lb", style: { display: "flex", fontSize: 13, fontWeight: 700, letterSpacing: 5, color: muted, fontFamily: ffL, paddingBottom: 6 } }, "SCHEDULE"),
        hr("hr-sch"),
        ...rows,
      ]),
      // — footer —
      h("div", { key: "ft", style: { display: "flex", flexDirection: "column", gap: 12 } }, [
        hr("hr-ft"),
        h("div", { key: "hl", style: { display: "flex", fontSize: 17, color: muted, lineHeight: 1.5, fontFamily: ff } }, hlText),
        h("div", { key: "fo", style: { display: "flex", justifyContent: "space-between", fontSize: 16, color: muted } }, [
          h("div", { key: "l" }, trunc(c.footer, 36)),
          h("div", { key: "r", style: { fontWeight: 700, color: accent, fontFamily: ffL } }, c.slug),
        ]),
      ]),
    ]),
    { width: W, height: H, fonts },
  );
}

// ============================================================
//  B — Dark Cinema Poster: dark bg, gold accent, cinematic
// ============================================================
function posterCard(c, fonts) {
  const items = normItems(c.schedule);
  const bg = "#0D1117";
  const fg = "#E6E1D8";
  const gold = "#C9A655";
  const orange = "#E07A42";
  const muted = "#6D675E";
  const cardBg = "#161B24";
  const ff = '"Noto Sans JP", "Noto Sans SC", "Inter"';
  const ffL = '"Inter", "Noto Sans JP", "Noto Sans SC"';

  const schedRows = items.map((item, i) =>
    h("div", { key: `s-${i}`, style: { display: "flex", flexDirection: "column", gap: 5, padding: "14px 20px", borderRadius: 14, backgroundColor: cardBg } }, [
      h("div", { key: "row", style: { display: "flex", width: "100%", alignItems: "baseline", gap: 14 } }, [
        h("div", { key: "t", style: { display: "flex", minWidth: 150, fontSize: 18, fontWeight: 700, color: gold, fontFamily: ffL } }, item.time),
        h("div", { key: "n", style: { display: "flex", flex: 1, fontSize: 25, fontWeight: 700, lineHeight: 1.2, color: fg, fontFamily: ff } }, item.title),
      ]),
      item.meta ? h("div", { key: "m", style: { display: "flex", fontSize: 19, lineHeight: 1.3, color: "#9B9488", fontFamily: ff, paddingLeft: 164 } }, item.meta) : null,
      item.note ? h("div", { key: "o", style: { display: "flex", fontSize: 16, color: orange, fontFamily: ff, paddingLeft: 164 } }, item.note) : null,
    ]),
  );

  const pills = (c.highlights ?? []).slice(0, 4).map((line, i) =>
    h("div", { key: `p-${i}`, style: { display: "flex", padding: "9px 16px", borderRadius: 999, borderWidth: 2, borderStyle: "solid", borderColor: i % 2 === 0 ? gold : orange, color: i % 2 === 0 ? gold : orange, fontSize: 17, fontWeight: 700, fontFamily: ff } }, trunc(line, 26)),
  );

  return satori(
    h("div", { style: { display: "flex", flexDirection: "column", width: W, height: H, padding: 52, backgroundColor: bg, color: fg, fontFamily: ff, justifyContent: "space-between", position: "relative", overflow: "hidden" } }, [
      // subtle glow
      h("div", { key: "glow", style: { position: "absolute", right: -200, top: -200, width: 500, height: 500, borderRadius: 500, backgroundColor: `${gold}0A` } }),
      // — header —
      h("div", { key: "hd", style: { display: "flex", flexDirection: "column", gap: 14 } }, [
        h("div", { key: "b", style: { display: "flex", alignItems: "center", gap: 10 } }, [
          h("div", { key: "dot", style: { width: 10, height: 10, borderRadius: 10, backgroundColor: gold } }),
          h("div", { key: "lb", style: { fontSize: 15, fontWeight: 700, letterSpacing: 4, color: muted, fontFamily: ffL } }, "MEGURO CINEMA"),
        ]),
        h("div", { key: "dr", style: { display: "flex", justifyContent: "space-between", alignItems: "baseline" } }, [
          h("div", { key: "d", style: { display: "flex", fontSize: 19, fontWeight: 700, letterSpacing: 5, color: gold, fontFamily: ffL } }, c.dateLabel),
          h("div", { key: "w", style: { display: "flex", fontSize: 17, fontWeight: 600, letterSpacing: 1.5, color: muted, fontFamily: ffL } }, c.weekLabel),
        ]),
        h("div", { key: "ti", style: { display: "flex", fontSize: 52, fontWeight: 700, lineHeight: 1.08, letterSpacing: -1.5, color: "#FFFFFF" } }, trunc(c.title, 30)),
        h("div", { key: "su", style: { display: "flex", fontSize: 21, lineHeight: 1.4, color: "#9B9488" } }, trunc(c.subtitle, 52)),
      ]),
      // — schedule —
      h("div", { key: "sc", style: { display: "flex", flexDirection: "column", gap: 9 } }, [
        h("div", { key: "lb", style: { display: "flex", fontSize: 13, fontWeight: 700, letterSpacing: 5, color: muted, fontFamily: ffL, paddingBottom: 2 } }, "SCHEDULE"),
        ...schedRows,
      ]),
      // — footer —
      h("div", { key: "ft", style: { display: "flex", flexDirection: "column", gap: 12 } }, [
        h("div", { key: "pls", style: { display: "flex", flexWrap: "wrap", gap: 10 } }, pills),
        h("div", { key: "fo", style: { display: "flex", justifyContent: "space-between", fontSize: 16, color: muted } }, [
          h("div", { key: "l" }, trunc(c.footer, 36)),
          h("div", { key: "r", style: { fontWeight: 700, color: gold, fontFamily: ffL } }, c.slug),
        ]),
      ]),
    ]),
    { width: W, height: H, fonts },
  );
}

// ============================================================
//  C — Refined Current: warm cream, left-bar timeline, glass
// ============================================================
function refinedCard(c, fonts) {
  const items = normItems(c.schedule);
  const bg = "#F3EDE3";
  const fg = "#1E1B18";
  const accent = "#C46A3D";
  const accentAlt = "#5C7A8A";
  const muted = "#7A736B";
  const ff = '"Noto Sans JP", "Noto Sans SC", "Inter"';
  const ffL = '"Inter", "Noto Sans JP", "Noto Sans SC"';

  const schedRows = items.map((item, i) =>
    h("div", { key: `s-${i}`, style: { display: "flex", flexDirection: "row", width: "100%" } }, [
      // left accent bar
      h("div", { key: "bar", style: { display: "flex", width: 4, borderRadius: 2, backgroundColor: i % 2 === 0 ? accent : accentAlt, flexShrink: 0 } }),
      // content
      h("div", { key: "c", style: { display: "flex", flexDirection: "column", flex: 1, gap: 4, paddingLeft: 16, paddingTop: 6, paddingBottom: 6 } }, [
        h("div", { key: "row", style: { display: "flex", width: "100%", alignItems: "baseline", gap: 14 } }, [
          h("div", { key: "t", style: { display: "flex", minWidth: 148, fontSize: 19, fontWeight: 700, color: accentAlt, fontFamily: ffL } }, item.time),
          h("div", { key: "n", style: { display: "flex", flex: 1, fontSize: 26, fontWeight: 700, lineHeight: 1.18, fontFamily: ff } }, item.title),
        ]),
        item.meta ? h("div", { key: "m", style: { display: "flex", fontSize: 20, lineHeight: 1.3, color: "#4E4741", fontFamily: ff } }, item.meta) : null,
        item.note ? h("div", { key: "o", style: { display: "flex", fontSize: 17, color: accent, fontFamily: ff } }, item.note) : null,
      ]),
    ]),
  );

  const pills = (c.highlights ?? []).slice(0, 4).map((line, i) =>
    h("div", { key: `p-${i}`, style: { display: "flex", padding: "9px 16px", borderRadius: 10, backgroundColor: i % 2 === 0 ? accent : accentAlt, color: "#FFF8F1", fontSize: 18, fontWeight: 700, fontFamily: ff } }, trunc(line, 26)),
  );

  return satori(
    h("div", { style: { display: "flex", width: W, height: H, position: "relative", overflow: "hidden", padding: 44, backgroundColor: bg, color: fg, fontFamily: ff } }, [
      // background circles
      h("div", { key: "ca", style: { position: "absolute", right: -140, top: -90, width: 420, height: 420, borderRadius: 420, backgroundColor: `${accent}12` } }),
      h("div", { key: "cb", style: { position: "absolute", left: -100, bottom: -140, width: 380, height: 380, borderRadius: 380, backgroundColor: `${accentAlt}14` } }),
      // glass frame
      h("div", { key: "fr", style: { display: "flex", flexDirection: "column", width: "100%", height: "100%", padding: "38px 38px", borderRadius: 32, background: "linear-gradient(180deg, rgba(255,255,255,0.90) 0%, rgba(255,255,255,0.70) 100%)", borderWidth: 1, borderStyle: "solid", borderColor: "rgba(255,255,255,0.55)", justifyContent: "space-between" } }, [
        // — header —
        h("div", { key: "hd", style: { display: "flex", flexDirection: "column", gap: 14 } }, [
          h("div", { key: "b", style: { display: "flex", alignItems: "center", gap: 10, padding: "10px 18px", borderRadius: 999, backgroundColor: "rgba(255,255,255,0.6)" } }, [
            h("div", { key: "dot", style: { width: 11, height: 11, borderRadius: 11, backgroundColor: accent } }),
            h("div", { key: "lb", style: { fontSize: 17, fontWeight: 700, letterSpacing: 2, fontFamily: ffL } }, "MEGURO CINEMA"),
          ]),
          h("div", { key: "hg", style: { display: "flex", flexDirection: "column", gap: 8 } }, [
            h("div", { key: "d", style: { display: "flex", fontSize: 20, fontWeight: 700, letterSpacing: 3, color: accentAlt, fontFamily: ffL } }, c.dateLabel),
            h("div", { key: "ti", style: { display: "flex", fontSize: 52, fontWeight: 700, lineHeight: 1.08, letterSpacing: -1 } }, trunc(c.title, 30)),
            h("div", { key: "w", style: { display: "flex", fontSize: 19, fontWeight: 700, letterSpacing: 1.5, color: accent, fontFamily: ffL } }, c.weekLabel),
            h("div", { key: "su", style: { display: "flex", fontSize: 23, lineHeight: 1.35, color: "#3C352F" } }, trunc(c.subtitle, 52)),
          ]),
        ]),
        // — schedule —
        h("div", { key: "sc", style: { display: "flex", flexDirection: "column", gap: 12 } }, [
          h("div", { key: "lb", style: { display: "flex", fontSize: 14, fontWeight: 700, letterSpacing: 4, color: accentAlt, fontFamily: ffL } }, "SCHEDULE"),
          h("div", { key: "items", style: { display: "flex", flexDirection: "column", gap: 8 } }, schedRows),
        ]),
        // — footer —
        h("div", { key: "ft", style: { display: "flex", flexDirection: "column", gap: 12 } }, [
          h("div", { key: "hl", style: { display: "flex", fontSize: 14, fontWeight: 700, letterSpacing: 4, color: accentAlt, fontFamily: ffL } }, "HIGHLIGHTS"),
          h("div", { key: "pls", style: { display: "flex", flexWrap: "wrap", gap: 10 } }, pills),
          h("div", { key: "fo", style: { display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: 6, fontSize: 17, color: "#514943" } }, [
            h("div", { key: "l" }, trunc(c.footer, 36)),
            h("div", { key: "r", style: { fontWeight: 700, color: accent, fontFamily: ffL } }, c.slug),
          ]),
        ]),
      ]),
    ]),
    { width: W, height: H, fonts },
  );
}

// ============================================================
//  Main
// ============================================================
async function main() {
  const projRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const outDir = path.join(projRoot, "output", "variants");
  await mkdir(outDir, { recursive: true });
  const fonts = await loadFonts(projRoot);

  const variants = [
    ["a-editorial", editorialCard],
    ["b-poster", posterCard],
    ["c-refined", refinedCard],
  ];

  for (const [name, fn] of variants) {
    const svg = await fn(card, fonts);
    await writeFile(path.join(outDir, `${name}.svg`), svg, "utf8");
    const resvg = new Resvg(svg, { fitTo: { mode: "width", value: W } });
    await writeFile(path.join(outDir, `${name}.png`), resvg.render().asPng());
    process.stdout.write(`✓ ${name}.png\n`);
  }
}

await main();
