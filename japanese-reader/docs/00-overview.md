# 00 - 总体设计

## 用户故事

我贴一段日语进去，看到一段双语翻译。我已经熟的单词和语法点不出现注释，不熟的有下划线提示，点击展开看解释。读完一遍，凡是我点击查看过的、或者主动标"已熟"的，下次再读类似文章就不再打扰我。

## 数据流

```
原文输入                         每日 Cron（06:00 JST）
（手动粘贴）                      抓维基长文 → 分块
    ↓                               ↓
[LLM 拆解 analyze（Gemini 2.5 Flash，经 Hono Worker，分块+重试）]
    ↓
Article JSON（句子 + 单词 + 语法点 + 翻译）→ 存 D1 + 预热每句 TTS（KV）
    ↓
[渲染 React SPA]
    ↓
查询每个单元的熟悉度（D1，经 Hono /api）
    ↓
按阈值决定：纯翻译 / 下划线提示 / 默认展开
    ↓
用户点击 → 调整熟悉度 → 写回 D1
朗读：句级 🔊 / 「▶ 朗读全文」→ /api/tts（Gemini 神经 TTS，KV 缓存）
```

部署形态见 `04-infrastructure.md`：全栈跑在 Cloudflare Workers 上，前端 React SPA + 后端 Hono + D1（状态）+ KV（LLM 缓存），LLM 走 Gemini，整个 app 由 Cloudflare Access 在边缘鉴权（单人自用）。

## 三个核心抽象

### 1. Word（单词）

```
{
  surface: "進んでいます",
  dict_form: "進む",
  reading: "すすむ",
  pos: "verb",
  meaning_zh: "前进，移动",
  familiarity: 3
}
```

`dict_form` 是单词的 canonical key。同一个动词无论变形怎么变，归到同一条记录。

### 2. GrammarPoint（语法点）

```
{
  canonical_id: "g_kamoshirenai",
  display_form: "～かもしれない",
  level_hint: "N4",
  surface_in_text: "降るかもしれません",
  familiarity: 3
}
```

`canonical_id` 是语法点的 stable key。来源是 hanabira.org 的 828 项语法库（CC，N5-N1，详见 `seed.ts`）。同一表面形多含义时（如 `Vている` 进行 vs 结果状态），ID 通过 level 后缀或编号区分（如 `g_you_ni_n3`、`g_you_ni_n3_2`）。

### 3. Sentence（句子）

```
{
  ja: "気象庁によると、台風は沖縄の近くを北に進んでいます。",
  zh: "据气象厅消息，台风正在冲绳附近向北移动。",
  words: [...],
  grammar: [...]
}
```

句子是渲染单位。一篇文章是 `Sentence[]`。

## 熟悉度模型

5 档：

| 等级 | 含义 | 渲染 |
|---|---|---|
| 0 | 没见过 | 默认展开注释 |
| 1 | 见过 1-2 次 | 默认展开注释 |
| 2 | 模糊印象 | 下划线提示，点击展开 |
| 3 | 大致认识 | 下划线提示，点击展开 |
| 4 | 熟练 | 不显示注释，但悬停可看 |
| 5 | 完全掌握 | 完全不标注 |

阈值用户可调（slider 范围 2–5，默认 5）。渲染按相对阈值的三档：`fam ≥ 阈值`=熟（无标注）；`阈值-2 ≤ fam < 阈值`=半生（虚线）；`fam < 阈值-2`=生（实线+底色）。

## 渲染策略

每个句子渲染两层：

```
日语原文（带可点击的 word/grammar 标注）
↓
中文翻译（始终显示）
↓
[展开的注释面板，按 word 和 grammar 分类]
```

熟悉度低的标注默认展开。熟悉度高的折叠。点击切换。

## 关键设计决策

### 为什么不用 Anki

Anki 是抽卡式记忆，强调"主动召回"。这个项目是"阅读式遭遇"，强调在真实语境中反复见到，被动巩固。两者互补，不冲突。

### 为什么 grammar canonical_id 不直接用日语字符串

同一个表面形（如 `そうだ`）对应多个语法点（样态 vs 传闻）。用 stable key 隔离。

### 为什么用 React + Cloudflare（而非早期的单文件 HTML）

项目原型阶段是单文件 `prototype.html`（vanilla JS + localStorage，可 `file://` 直接打开），本地配 Express + SQLite。这一阶段已完成它的使命。上公网自用后改为：

- **前端 React + Vite + responsive**：组件化，移动端适配；Vite 产物用 Workers Assets 托管。
- **后端 Hono on Workers**：替代 Express（Workers 跑不了 Node 进程式框架）。
- **零安装、随处可用**：浏览器打开一个 URL 即可，不再依赖本地起 server。

完整迁移决议、被否方案、成本核算见 `04-infrastructure.md`。

### 数据存哪

状态数据在 **D1**（Cloudflare 的 SQLite），schema 与原 better-sqlite3 一致（见 `01-data-model.md`）。两类：

- **参考表**（不可变，从外部源 seed）：`vocab`、`grammar_points`
- **状态表**（用户产生）：`articles`、`occurrences`、`familiarity`

参考表用 `wrangler d1` 迁移脚本一次性灌入，可放心重灌；状态表是阅读和打分产生的真实数据，要备份。LLM 拆解结果缓存在 **KV**（key→json blob），替代原本地 `data/cache/`。

前端不直接连 D1 —— React SPA 与 Hono Worker 走 REST（`/api/*`）。鉴权由 Cloudflare Access 在边缘完成，app 本身不写鉴权代码（见 `04-infrastructure.md`）。

## 当前阶段

### 原型阶段（本地，已完成）

- [x] 项目结构搭建
- [x] prototype.html（含示例数据，可独立或与 server 配合）
- [x] Article JSON schema + 台风文章示例
- [x] 语法 registry：hanabira 828 项（N5-N1，CC by hanabira.org）
- [x] vocab：JLPT 词表 7895 行（来自 study-japanese-vocabulary）
- [x] analyze.ts：AWS Bedrock + 自动 token 偏移修正 + LLM 缓存
- [x] server.ts：Express + better-sqlite3 持久化 + /api/analyze
- [x] seed.ts：从 hanabira/JLPT 数据灌参考表，幂等
- [x] 全栈 TS / Node（已废弃 Python 版本）

### 上云阶段（已上线，详见 `04-infrastructure.md`）

线上：https://jr-app.chengpeng.press

- [x] 工作区清理（删 `../.next`、`../.playwright-mcp` 等遗留产物）
- [x] 前端：`prototype.html` → React + Vite + responsive
- [x] 后端：Express → Hono；SQLite → D1；本地 cache → KV
- [x] LLM：Bedrock → Gemini 2.5 Flash（fetch-based，分块 + 重试）
- [x] TTS：**Gemini 神经 TTS**（`/api/tts`，PCM→WAV，KV 缓存，带重试）；浏览器 Web Speech 仅作回退。`tts.ts` 保留（最初计划的"Web Speech only / 删 tts.ts"已反转）
- [x] 鉴权：Cloudflare Access（自定义域名 `jr-app.chengpeng.press`，Cloudflare 账号登录 + Instant Auth，可 passkey）
- [x] CI/CD：GitHub Actions + `cloudflare/wrangler-action`（push main 自动部署）
- [x] 多文章管理：侧栏列表 / 切换 / 删除
- [x] 每日文章任务：Cron 每天抓维基长文 → 分块 analyze → 存 D1 → 预热 TTS（`/api/daily` 可手动触发，支持指定 `title`）
- [x] 全文朗读：「▶ 朗读全文」顺序连播 + 当前句高亮

### 功能 backlog

- [ ] `grammar_points.meaning_zh` 中文释义批量回填
- [ ] 别名/变体匹配（很多语法 LLM 用变体写法，可做 fuzzy match）
- [ ] 复习模式（按 familiarity 倒序展示句子）
- [ ] 数据导出 / 备份命令（D1 export → R2/本地）
