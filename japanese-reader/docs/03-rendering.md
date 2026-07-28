# 03 - 渲染和交互

> **状态**：渲染逻辑在原型阶段（`prototype.html`，vanilla JS）已验证；上云阶段重写为 **React + responsive**。
> 本文档描述的渲染层级、CSS 分档、交互、token 切片算法**与实现框架无关**，React 版原样沿用——下面的 `state` 对象映射到 React state/context，`renderSentence` 模板映射到组件。具体见 `04-infrastructure.md`。

## 页面布局

```
┌─────────────────────────────────────────┐
│  Japanese Reader                        │
│  熟悉度阈值: [5] (≥此值不显示注释)        │
├─────────────────────────────────────────┤
│  [输入框: 粘贴日语原文]                   │
│  [Analyze 按钮]                         │
├─────────────────────────────────────────┤
│  Article view:                          │
│                                         │
│  気象庁によると、台風は沖縄の近くを        │
│  ↑                ↑                     │
│  (语法点tag)      (单词下划线)            │
│  北に進んでいます。                       │
│  据气象厅消息，台风正在冲绳附近向北移动。   │
│                                         │
│  [展开 ▾] (默认折叠/展开按熟悉度决定)      │
│  • 進む (すすむ) - 前进 [熟] [生]         │
│  • Vている - 正在…… [熟] [生]            │
│                                         │
│  ─── 下一句 ───                         │
└─────────────────────────────────────────┘
```

## 渲染层级

每个 sentence block 三行内容：

1. **日语原文行**：每个 token 是一个 `<span>`，class 标记类型和熟悉度
2. **中文翻译行**：纯文本
3. **注释面板**（折叠/展开）：列出 sentence 内所有 word + grammar 的释义

## CSS class 约定（实际，见 `cf/web/src/App.tsx` + `styles.css`）

```css
.token             /* token 基础样式 */
/* 六级熟悉度背景（红→橙→黄→绿→透明），只表示学习状态 */
.tok-fam-0         /* 没见过：深红底 */
.tok-fam-1         /* 见过 1-2 次：浅红/橙底 */
.tok-fam-2         /* 模糊印象：琥珀底 */
.tok-fam-3         /* 大致认识：浅黄底 */
.tok-fam-4         /* 熟练：极浅绿底 */
.tok-fam-5         /* fam >= threshold：透明 */
.link-0..4         /* 句内对应关系色：token/grammar chip 下划线 + note chip 边框 */
.grammar-chip      /* 语法点：JA 行下方独立一排可点 chip（不是 overlay） */

details.notes      /* 注释面板（原生 <details>，open 态即展开） */
.note-list         /* 注释条目的 responsive grid：词条按列排列，长语法项跨列 */
.note-item         /* 单个释义条目 */
.note-item.highlight /* 点 token/chip 时高亮对应条目 */
.sentence.reading  /* 全文朗读时当前句的高亮光圈 */
```

> 注：类名前缀 `tok-fam-`（0–5 对应熟悉度分数）只表达学习状态；`link-0`–`link-4` 是另一套句内临时属性，只表达「原文 token / grammar chip 对应哪一个完整显示的 note card」。两套颜色不能复用，也不能由 familiarity score 推导。已折叠进「已熟悉 N 项」摘要、下方没有完整卡片的项目，不显示 link 色。语法点是 JA 行下方的一排 **grammar-chip**（可点击聚焦注释），不是覆盖在原文上的 overlay。

## 交互

### Token / grammar chip 点击

- 点击任意 token 或 grammar chip → 展开注释面板并高亮（`.highlight`）对应释义条目

### 注释条目里的熟悉度操作（实际 UI）

- **＋1 按钮**：familiarity += 1（capped at 5）
- **五点评分 dot**（淘宝式）：点第 N 个 dot → 设为 N；再点当前最高 dot → 清零
- **🔊 朗读按钮**：词条朗读（走 `/api/tts`）
- 评分控件固定在 note card 底部，不占标题行空间；词条朗读按钮可保留在标题右侧。
- 调整后乐观更新 + POST `/api/familiarity` 写回 D1，立即重渲染
- 只有预置 `vocab` / `grammar_points` 里的项目能评分；公司名、日期、未注册专名等非学习项默认隐藏，且不参与 `link-*` 对应色。顶部「显示无评分项」开关打开后才显示这些无评分卡片；后端仍拒绝把它们写入 `familiarity`。
- 熟悉度 5/5 的注释默认合并成一个「已熟悉 N 项」紧凑块；展开后仍可查看完整条目和修改评分。若点击原文里的已熟项，该条会临时显示为完整高亮行。

### Sentence-level 折叠

- 注释面板默认展开条件：该句最低熟悉度 `minFam < threshold - 2`（即有"生"词才默认展开）；否则折叠
- 用户可手动 toggle（原生 `<details>`）

### 句级 / 全文朗读

- 每句 JA 行右侧 🔊「朗读整句」
- 文章顶部「▶ 朗读全文」：见下方 §全文朗读

### 全局阈值滑块

- 顶部 slider，范围 **2–5**（默认 5），实时改变所有渲染
- 阈值存 localStorage（仅此 UI 偏好存本地，熟悉度权威在 D1）

### 分析等待反馈

- 点 Analyze 后按钮显示「分析中… Ns」实时计时 + 「首次分析约需 10–20 秒」提示

## State 管理（React）

概念模型（原型阶段是单个 vanilla `state` 对象，React 版拆成 state/context）：

```ts
// 概念形状——React 里用 useState/useContext + react-query 之类管理
const state = {
  article: null,        // 当前 Article
  familiarity: {},      // 从 /api/familiarity（D1）拉取，非 localStorage
  threshold: 3,         // 仅此项存 localStorage（UI 偏好）
  expandedSentences: new Set(),  // 用户手动展开的句子 id
};

function getFamiliarity(type, key) {
  return state.familiarity[`${type}:${key}`] ?? 0;
}

// 设置熟悉度：乐观更新本地 state，POST /api/familiarity 写回 D1
async function setFamiliarity(type, key, value) {
  const v = Math.max(0, Math.min(5, value));
  // optimistic: 立即更新 React state 并重渲染受影响 token
  await fetch("/api/familiarity", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ type, key, score: v }),
  });
}
```

> 与原型差异：熟悉度权威源是 **D1**（经 `/api/familiarity`），不再是 localStorage。写入走乐观更新（先改 UI 再 POST）。Cloudflare Access 已在边缘保证只有本人能访问，前端无需自带鉴权。

## 渲染算法

下面是逻辑伪码（原型用模板字符串）。React 版把它拆成 `<Sentence>` / `<TokenSpan>` / `<NotePanel>` 组件，`<details>` 折叠态用受控 state，逻辑不变：

```js
function renderSentence(sent) {
  // 1. 把 ja 字符串按 token 偏移切片，每个 token 包成 <span>
  const spans = buildTokenSpans(sent.ja, sent.tokens, sent.grammar);

  // 2. 决定注释面板默认展开/折叠
  const minFam = computeMinFamiliarity(sent);
  const isOpen = state.expandedSentences.has(sent.id) || minFam < state.threshold - 2;

  // 3. 注释列表（合并 word + grammar）
  const notes = buildNotes(sent.tokens, sent.grammar);

  return `
    <div class="sentence" data-id="${sent.id}">
      <div class="ja-line">${spans}</div>
      <div class="zh-line">${sent.zh}</div>
      <details class="note-panel" ${isOpen ? "open" : ""}>
        <summary>注释 (${notes.length})</summary>
        ${notes.map(renderNote).join("")}
      </details>
    </div>
  `;
}
```

## Token span 构建

文本切片按 `start`/`end` 排序，token 之间的部分（助词、标点）不加 class，原样输出。
grammar **不做覆盖渲染**：原文行只对 word token 加下划线；语法点单独渲染成 JA 行下方的一排 `.grammar-chip`（可点击聚焦注释），避免与 token 区间重叠的复杂度。

## 移动端

- token 触摸目标 ≥ 32px 高
- 注释面板默认就是全宽展开，不需要 hover

## 暗色模式

```css
@media (prefers-color-scheme: dark) {
  body { background: #1a1a1a; color: #e8e8e8; }
  .token-unknown { background: #3a2a1a; }
  ...
}
```

## 性能

- 一篇文章通常 10-50 句，渲染量小，全 DOM 重建即可
- 阈值 slider 实时更新：用 CSS 变量传 threshold，所有 token 通过 `data-fam` + CSS 选择器决定样式，不重建 DOM

## 全文朗读（read-all）

文章区顶部的 sticky「▶ 朗读全文」播放条：顺序朗读每句（`speakSequence`），当前句加 `.reading` 高亮并自动滚动到视图中央。播放条在文章滚动范围内保持可见，可随时「暂停 / 继续 / 停止」，并提供「上一句 / 重播当前句 / 下一句 / 当前句后退 5s / 当前句前进 5s」控制；切换文章、重新分析、或点击单句/词条朗读会自动停止全文朗读状态。语音走 `/api/tts`（每日任务已预热进 KV，连播流畅），失败回退 Web Speech。Web Speech fallback 支持暂停/继续，但不支持精确 5s seek。
