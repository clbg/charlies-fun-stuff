import React from "react";
import satori from "satori";
import { readFile } from "node:fs/promises";
import path from "node:path";

export const CARD_WIDTH = 1080;
export const CARD_HEIGHT = 1440;
const MAX_SCHEDULE_LINES = 8;
const MAX_HIGHLIGHTS = 4;

function truncateText(text, maxChars) {
  if (!text) return "";
  if (text.length <= maxChars) return text;
  return `${text.slice(0, Math.max(0, maxChars - 1)).trimEnd()}…`;
}

function clampList(items, maxItems, maxChars) {
  return (items ?? []).slice(0, maxItems).map((item) => truncateText(item, maxChars));
}

function normalizeScheduleItems(card) {
  return (card.schedule ?? []).slice(0, MAX_SCHEDULE_LINES).map((item) => {
    if (typeof item === "string") {
      return {
        time: "",
        title: truncateText(item, card.kind === "cover" ? 56 : 44),
        meta: "",
        note: "",
      };
    }

    const time = truncateText(item.time ?? "", 22);
    const title = truncateText(item.title ?? "", card.kind === "cover" ? 56 : 28);
    const meta = truncateText(item.meta ?? "", card.kind === "cover" ? 70 : 42);
    const note = truncateText(item.note ?? "", card.kind === "cover" ? 70 : 36);

    return { time, title, meta, note };
  });
}

function palette(card) {
  const defaults = ["#F7F1E8", "#1E1B18", "#D96B2B", "#A63C2F"];
  const colors = [...(card.palette ?? [])];
  while (colors.length < 4) colors.push(defaults[colors.length]);
  return {
    background: colors[0],
    foreground: colors[1],
    accent: colors[2],
    accentAlt: colors[3],
  };
}

export async function loadFonts(projectRoot) {
  const fontDir = path.join(projectRoot, "node_modules");
  const fontFiles = [
    {
      name: "Noto Sans JP",
      weight: 400,
      style: "normal",
      file: path.join(
        fontDir,
        "@fontsource",
        "noto-sans-jp",
        "files",
        "noto-sans-jp-japanese-400-normal.woff",
      ),
    },
    {
      name: "Noto Sans JP",
      weight: 700,
      style: "normal",
      file: path.join(
        fontDir,
        "@fontsource",
        "noto-sans-jp",
        "files",
        "noto-sans-jp-japanese-700-normal.woff",
      ),
    },
    {
      name: "Noto Sans SC",
      weight: 400,
      style: "normal",
      file: path.join(
        fontDir,
        "@fontsource",
        "noto-sans-sc",
        "files",
        "noto-sans-sc-chinese-simplified-400-normal.woff",
      ),
    },
    {
      name: "Noto Sans SC",
      weight: 700,
      style: "normal",
      file: path.join(
        fontDir,
        "@fontsource",
        "noto-sans-sc",
        "files",
        "noto-sans-sc-chinese-simplified-700-normal.woff",
      ),
    },
  ];

  return Promise.all(
    fontFiles.map(async (entry) => ({
      name: entry.name,
      weight: entry.weight,
      style: entry.style,
      data: await readFile(entry.file),
    })),
  );
}

function sectionTitle(text, color) {
  return React.createElement(
    "div",
    {
      style: {
        fontSize: 22,
        fontWeight: 700,
        letterSpacing: 3,
        color,
      },
    },
    text,
  );
}

export async function renderCardToSvg(card, fonts) {
  const colors = palette(card);
  const schedules = normalizeScheduleItems(card);
  const highlights = clampList(card.highlights, MAX_HIGHLIGHTS, 26);
  const title = truncateText(card.title, card.kind === "cover" ? 34 : 30);
  const subtitle = truncateText(card.subtitle, card.kind === "cover" ? 60 : 52);
  const footer = truncateText(card.footer, 36);
  const dateLabel = truncateText(card.dateLabel, 26);
  const weekLabel = truncateText(card.weekLabel, 34);

  const badge = React.createElement(
    "div",
    {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "16px 24px",
        borderRadius: 999,
        backgroundColor: "rgba(255,255,255,0.7)",
        color: colors.foreground,
        fontSize: 22,
        fontWeight: 700,
        letterSpacing: 1.5,
      },
    },
    [
      React.createElement(
        "div",
        {
          key: "dot",
          style: {
            width: 14,
            height: 14,
            borderRadius: 999,
            backgroundColor: colors.accent,
          },
        },
      ),
      React.createElement("div", { key: "label" }, "MEGURO CINEMA"),
    ],
  );

  const scheduleItems = schedules.map((entry, index) =>
    React.createElement(
      "div",
      {
        key: `${index}-${entry.time}-${entry.title}`,
        style: {
          display: "flex",
          flexDirection: "column",
          gap: card.kind === "cover" ? 0 : 6,
          width: "100%",
          padding: card.kind === "cover" ? "18px 22px" : "16px 20px",
          borderRadius: 22,
          backgroundColor: "rgba(255,255,255,0.72)",
          color: colors.foreground,
        },
      },
      card.kind === "cover"
        ? React.createElement(
            "div",
            {
              style: {
                display: "flex",
                width: "100%",
                fontSize: 28,
                lineHeight: 1.25,
                fontWeight: 600,
              },
            },
            entry.title,
          )
        : [
            React.createElement(
              "div",
              {
                key: "head",
                style: {
                  display: "flex",
                  width: "100%",
                  justifyContent: "space-between",
                  alignItems: "flex-start",
                  gap: 16,
                },
              },
              [
                React.createElement(
                  "div",
                  {
                    key: "time",
                    style: {
                      display: "flex",
                      minWidth: 176,
                      fontSize: 20,
                      lineHeight: 1.15,
                      fontWeight: 700,
                      color: colors.accentAlt,
                    },
                  },
                  entry.time || "时间未确认",
                ),
                React.createElement(
                  "div",
                  {
                    key: "title",
                    style: {
                      display: "flex",
                      flex: 1,
                      fontSize: 26,
                      lineHeight: 1.15,
                      fontWeight: 700,
                    },
                  },
                  entry.title,
                ),
              ],
            ),
            entry.meta
              ? React.createElement(
                  "div",
                  {
                    key: "meta",
                    style: {
                      display: "flex",
                      width: "100%",
                      fontSize: 16,
                      lineHeight: 1.2,
                      fontWeight: 500,
                      color: "#4E4741",
                    },
                  },
                  entry.meta,
                )
              : null,
            entry.note
              ? React.createElement(
                  "div",
                  {
                    key: "note",
                    style: {
                      display: "flex",
                      width: "100%",
                      fontSize: 15,
                      lineHeight: 1.2,
                      fontWeight: 500,
                      color: colors.accent,
                    },
                  },
                  entry.note,
                )
              : null,
          ],
    ),
  );

  const highlightPills = highlights.map((line, index) =>
    React.createElement(
      "div",
      {
        key: `${index}-${line}`,
        style: {
          display: "flex",
          padding: "12px 18px",
          borderRadius: 999,
          backgroundColor: index % 2 === 0 ? colors.accent : colors.accentAlt,
          color: "#FFF8F1",
          fontSize: 22,
          lineHeight: 1.2,
          fontWeight: 700,
        },
      },
      line,
    ),
  );

  return satori(
    React.createElement(
      "div",
      {
        style: {
          display: "flex",
          width: CARD_WIDTH,
          height: CARD_HEIGHT,
          position: "relative",
          overflow: "hidden",
          padding: 48,
          backgroundColor: colors.background,
          color: colors.foreground,
          fontFamily: '"Noto Sans JP", "Noto Sans SC"',
        },
      },
      [
        React.createElement("div", {
          key: "bg-circle-a",
          style: {
            position: "absolute",
            right: -180,
            top: -110,
            width: 520,
            height: 520,
            borderRadius: 520,
            backgroundColor: `${colors.accent}1F`,
          },
        }),
        React.createElement("div", {
          key: "bg-circle-b",
          style: {
            position: "absolute",
            left: -120,
            bottom: -180,
            width: 460,
            height: 460,
            borderRadius: 460,
            backgroundColor: `${colors.accentAlt}22`,
          },
        }),
        React.createElement(
          "div",
          {
            key: "frame",
            style: {
              display: "flex",
              flexDirection: "column",
              width: "100%",
              height: "100%",
              padding: 44,
              borderRadius: 42,
              background:
                "linear-gradient(180deg, rgba(255,255,255,0.92) 0%, rgba(255,255,255,0.74) 100%)",
              border: "1px solid rgba(255,255,255,0.6)",
              justifyContent: "space-between",
            },
          },
          [
            React.createElement(
              "div",
              {
                key: "top",
                style: {
                  display: "flex",
                  flexDirection: "column",
                  gap: 24,
                },
              },
              [
                badge,
                React.createElement(
                  "div",
                  {
                    key: "headings",
                    style: {
                      display: "flex",
                      flexDirection: "column",
                      gap: 14,
                    },
                  },
                  [
                    React.createElement(
                      "div",
                      {
                        key: "date",
                        style: {
                          fontSize: 28,
                          fontWeight: 700,
                          letterSpacing: 1.5,
                          color: colors.accentAlt,
                        },
                      },
                      dateLabel,
                    ),
                    React.createElement(
                      "div",
                      {
                        key: "title",
                        style: {
                          fontSize: card.kind === "cover" ? 66 : 60,
                          fontWeight: 700,
                          lineHeight: 1.06,
                          letterSpacing: -1.5,
                        },
                      },
                      title,
                    ),
                    React.createElement(
                      "div",
                      {
                        key: "week",
                        style: {
                          fontSize: 24,
                          fontWeight: 700,
                          letterSpacing: 1.4,
                          color: colors.accent,
                        },
                      },
                      weekLabel,
                    ),
                    React.createElement(
                      "div",
                      {
                        key: "subtitle",
                        style: {
                          fontSize: 28,
                          lineHeight: 1.35,
                          fontWeight: 500,
                          color: "#3C352F",
                        },
                      },
                      subtitle,
                    ),
                  ],
                ),
              ],
            ),
            React.createElement(
              "div",
              {
                key: "middle",
                style: {
                  display: "flex",
                  flexDirection: "column",
                  gap: 18,
                },
              },
              [
                sectionTitle("SCHEDULE", colors.accentAlt),
                React.createElement(
                  "div",
                  {
                    key: "schedule",
                    style: {
                      display: "flex",
                      flexDirection: "column",
                      gap: card.kind === "cover" ? 14 : 10,
                    },
                  },
                  scheduleItems,
                ),
              ],
            ),
            React.createElement(
              "div",
              {
                key: "bottom",
                style: {
                  display: "flex",
                  flexDirection: "column",
                  gap: 18,
                },
              },
              [
                sectionTitle("HIGHLIGHTS", colors.accentAlt),
                React.createElement(
                  "div",
                  {
                    key: "highlights",
                    style: {
                      display: "flex",
                      flexWrap: "wrap",
                      gap: 12,
                    },
                  },
                  highlightPills,
                ),
                React.createElement(
                  "div",
                  {
                    key: "footer",
                    style: {
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      paddingTop: 10,
                      fontSize: 20,
                      lineHeight: 1.25,
                      color: "#514943",
                    },
                  },
                  [
                    React.createElement(
                      "div",
                      {
                        key: "source",
                        style: { display: "flex", maxWidth: 720 },
                      },
                      footer,
                    ),
                    React.createElement(
                      "div",
                      {
                        key: "slug",
                        style: {
                          display: "flex",
                          fontWeight: 700,
                          color: colors.accent,
                        },
                      },
                      truncateText(card.slug, 16).toUpperCase(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    {
      width: CARD_WIDTH,
      height: CARD_HEIGHT,
      fonts,
    },
  );
}
