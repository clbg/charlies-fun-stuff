# 03 - 渲染和交互

> **状态**：渲染逻辑在原型阶段（`prototype.html`，vanilla JS）已验证；上云阶段重写为 **React + responsive**。
> 本文档描述的渲染层级、CSS 分档、交互、token 切片算法**与实现框架无关**，React 版原样沿用——下面的 `state` 对象映射到 React state/context，`renderSentence` 模板映射到组件。具体见 `04-infrastructure.md`。

## 页面布局

```
┌─────────────────────────────────────────┐
│  Japanese Reader                        │
│  熟悉度阈值: [3] (≥此值不显示注释)        │
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

## CSS class 约定

```css
.token             /* 默认 token 样式 */
.token-known       /* familiarity >= threshold，无装饰 */
.token-fuzzy       /* familiarity 2-3，下划线虚线 */
.token-unknown     /* familiarity 0-1，下划线实线 + 浅色背景 */
.token-grammar     /* 语法点 token，与 word 区分（用色） */

.note-panel        /* 注释面板 */
.note-panel--open  /* 展开状态 */
.note-item         /* 单个释义条目 */
```

## 交互

### Token 点击

- 点击任意 token → 弹出/聚焦该项的释义
- 释义面板内有 [熟] [生] 按钮：
  - [熟]：familiarity += 1（capped at 5）
  - [生]：familiarity = max(0, familiarity - 1)
- 调整后立即重渲染该 token 的 class

### Sentence-level 折叠

- 注释面板默认状态由该句最低熟悉度决定：
  - 任何一个 token 熟悉度 < threshold → 默认展开
  - 全部 ≥ threshold → 默认折叠
- 用户可手动 toggle（覆盖默认）

### 全局阈值滑块

- 顶部一个 slider，0-5，实时改变所有渲染
- 阈值存 localStorage

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
  const isOpen = state.expandedSentences.has(sent.id) || minFam < state.threshold;

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
重叠区间（grammar 经常覆盖多个 token）：grammar 用 `<span class="grammar-overlay">` 包外层，word token 还是单独 `<span>`。

简化版：MVP 阶段 grammar 不做覆盖渲染，只在注释面板里列出。原文行只标 word token。

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
