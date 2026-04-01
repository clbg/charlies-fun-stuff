# Spec

## Goal

Build a deterministic Node.js pipeline that can generate Meguro Cinema social cards without relying on prompt-time layout improvisation.

## Why this exists

The Obsidian vault skill is responsible for gathering schedule data and deciding that cards should be generated.
This project is responsible for everything implementation-specific after that point:
- input schema
- normalization rules
- layout system
- font handling
- raster export
- output paths
- reproducibility checks

## Scope boundary

### In the vault skill

The skill should only do these things:
- decide the requested date window
- fetch or pass schedule data and metadata into this project
- call this project's CLI
- save returned assets and note outputs back into the vault when needed

The skill should not be the source of truth for rendering internals.

### In this project

This project must contain enough information for another agent or engineer to implement the whole pipeline without relying on vault-local context.

## Functional requirements

1. Accept structured input describing:
   - week range
   - daily schedules
   - film metadata
   - optional Xiaohongshu copy guidance
2. Generate:
   - one cover card
   - one daily card per date
3. Export final artifacts as PNG.
4. Optionally emit intermediate SVG or JSON for debugging, but PNG is the publishing target.
5. Keep layout deterministic.
6. Provide a CLI that the vault skill can call without relying on prompt-time layout decisions.

## Determinism requirements

Same input JSON must produce the same:
- file names
- card count
- card dimensions
- line breaks, within the same renderer/font environment
- output hashes unless assets or code changed

To support that, the renderer should:
- use bundled or explicitly pinned fonts
- avoid browser-dependent CSS layout
- avoid remote font fetching at render time
- avoid random colors, random placement, or current-time-dependent text

## Proposed architecture

### 1. Input contract

Use a JSON file as the renderer input.

Suggested files:
- `input/week.json` for one weekly run
- optional `input/theme.json` for reusable palette and typography settings

Current concrete contract:

```json
{
  "week": {
    "slug": "2026-03-30_to_2026-04-05",
    "title": "Meguro Cinema Weekly Schedule",
    "startDate": "2026-03-30",
    "endDate": "2026-04-05",
    "timezone": "Asia/Tokyo",
    "sourceUrl": "http://www.okura-movie.co.jp/meguro_cinema/now_showing.html"
  },
  "cards": [
    {
      "slug": "2026-04-05",
      "kind": "daily",
      "dateLabel": "SUNDAY",
      "weekLabel": "2026-04-05",
      "title": "目黑电影院 4/5 周日",
      "subtitle": "野村萬斎映画祭特别日",
      "schedule": [
        {
          "time": "11:00-12:40",
          "title": "バーフバリ エピック4K 前半",
          "meta": "巴霍巴利王：史诗 / Baahubali: The Epic",
          "note": "开馆 10:30；中场休息 15 分钟"
        }
      ],
      "highlights": ["Talk Event"],
      "footer": "目黑电影院官方排片",
      "palette": ["#F1ECE4", "#1F1917", "#9E3D37", "#6B7F62"]
    }
  ]
}
```

Required fields:
- `week.slug`
- `cards[]`
- for each card: `slug`, `title`, `schedule[]`

Schedule item shape:
- cover cards may use plain strings
- daily cards should prefer objects:
  - `time`: recommended `HH:MM-HH:MM`
  - `title`: main film or event title
  - `meta`: foreign title and Douban status line
  - `note`: optional secondary note such as `在线预约可`, `完全入替`, `Talk Event`

Missing metadata policy:
- if foreign title is unavailable, omit it
- if Douban rating is unavailable, omit it
- do not render placeholder copy such as `未确认` or `暂无评分`

### 2. Normalization layer

A Node module should convert source data into a canonical internal shape:
- sorted by date then time
- normalized title strings
- normalized rating strings
- normalized notes and highlight tokens

For the current implementation, the vault skill is allowed to do source-side normalization before passing JSON into this project.
This project remains the source of truth for rendering constraints and output shape.

### 3. Renderer

The renderer should work from the canonical shape only.

Suggested responsibilities:
- cover composition
- daily card composition
- deterministic text wrapping
- overflow handling
- highlight badge rendering
- footer rendering

Current implementation guarantees:
- fixed canvas `1080x1440`
- pinned local Noto Sans JP / SC font files
- max title, subtitle, schedule, and highlight lengths with deterministic truncation
- fixed layer coordinates and fixed palette slots
- daily schedule rows render as structured blocks: time range, title, metadata, note

### 4. Raster export

The renderer should export PNG directly or render to SVG and then deterministically rasterize to PNG using a pinned renderer.

## Recommended tool direction

Preferred direction:
- Node.js renderer
- a deterministic rendering stack such as `satori + @resvg/resvg-js`, or another Node-native solution with predictable text layout
- bundled Noto CJK fonts or another explicitly pinned font set

Current implementation:
- `satori`
- `@resvg/resvg-js`
- `@fontsource/noto-sans-jp`
- `@fontsource/noto-sans-sc`

## Non-goals

- no prompt-driven one-off image layout
- no dependence on the Obsidian vault for implementation details
- no manual copy-paste as a required step in the pipeline

## Output contract

Expected outputs for one week:
- `output/<week-slug>/cover.png`
- `output/<week-slug>/<date>.png` for each day
- optional `output/<week-slug>/input.snapshot.json`
- optional `output/<week-slug>/debug/*.svg`

Current CLI also accepts a custom `--out` directory, so the vault skill can route output back into the vault if needed.

## CLI contract

Run:

```bash
node src/cli.mjs --input input/week.sample.json --out output/sample-week --debug-svg
```

Arguments:
- `--input <path>` input JSON path, default `input/week.sample.json`
- `--out <path>` output directory, default `output/sample-week`
- `--debug-svg` also emit SVG debug files

Success condition:
- exit code `0`
- stdout line `Rendered <N> cards for <week-slug> into <path>`

## Remaining tasks

1. move from sample JSON to vault-produced JSON handoff
2. add snapshot tests in CI
3. define a stricter JSON schema validator
4. document font upgrade procedure
5. add an optional theme layer if card variants expand
