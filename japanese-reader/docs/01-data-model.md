# 01 - 数据模型

数据流：

```
日语原文
  → analyze（Gemini + grammar_points 查询）
  → JSON Article
  → Hono Worker 写入 articles + occurrences（D1）
  → React SPA 渲染（叠加 familiarity）
```

参考表（`vocab`、`grammar_points`）由 D1 迁移脚本一次性灌入；状态表（`articles`、`occurrences`、`familiarity`）由用户使用产生。

> Schema 在原型阶段跑在 better-sqlite3 上，上云后跑在 **D1**（同为 SQLite 方言）。下面的 `CREATE TABLE` 原样适用于 D1 迁移；数据访问从同步 `prepare().get()/.all()/.run()` 改为 D1 的异步 `await`，`COUNT(DISTINCT)` 等关系查询原样保留。详见 `04-infrastructure.md`。

---

## JSON Schema（analyze.ts 输出 / 渲染输入）

### Article（顶层）

```json
{
  "title": "短い説明",
  "source": "user input",
  "sentences": [Sentence, ...]
}
```

### Sentence

```json
{
  "id": "s1",
  "ja": "気象庁によると、台風は沖縄の近くを北に進んでいます。",
  "zh": "据气象厅消息，台风正在冲绳附近向北移动。",
  "tokens": [Token, ...],
  "grammar": [GrammarRef, ...]
}
```

### Token

```json
{
  "surface": "進んでいます",
  "dict_form": "進む",
  "reading": "すすむ",
  "pos": "verb",
  "meaning_zh": "前进",
  "start": 18,
  "end": 24
}
```

`start`/`end` 是字符级偏移。LLM **不输出** offsets —— `assignOffsets()` 用 `ja.indexOf(surface)` 自动计算。这避开了 LLM 数 emoji / surrogate pair 算错的常见问题。

非内容词（助词、标点）整个不输出，prompt 里有明确指示。

### GrammarRef

```json
{
  "canonical_id": "g_kamoshirenai",
  "display_form": "～かもしれない",
  "meaning_zh": "也许，可能",
  "explanation": "「降るかもしれません」表示对明天下雨的不确定推测"
}
```

LLM 输出 `canonical_id`（必须从 `grammar_points` 表选）+ 一句上下文相关 explanation。`display_form` / `meaning_zh` 也由 LLM 生成（冗余，但避免渲染时再 join 一次 DB）。

匹配不到 registry 时 LLM 写 `g_unregistered`，控制台 warn 列出，方便后续手动添加。

---

## SQLite / D1 Schema（actual）

```sql
-- 参考表（D1 迁移脚本灌入，可重灌）

CREATE TABLE vocab (
    dict_form TEXT PRIMARY KEY,        -- 7895 行，来自 jlpt_vocab.csv
    reading TEXT,
    meaning_en TEXT,
    meaning_zh TEXT,                    -- 暂时为空，CSV 是英文源
    jlpt_level TEXT,                    -- N1..N5
    pos TEXT,
    notes TEXT
);
CREATE INDEX idx_vocab_jlpt ON vocab(jlpt_level);
CREATE INDEX idx_vocab_reading ON vocab(reading);

CREATE TABLE grammar_points (
    canonical_id TEXT PRIMARY KEY,     -- 828 行，来自 hanabira CC 数据
    display_form TEXT NOT NULL,        -- 日语形如 "～かもしれない"
    meaning_zh TEXT,                    -- 暂时为空
    function_tag TEXT,                  -- 暂时为空
    level_hint TEXT,                    -- N1..N5
    aliases TEXT,                       -- JSON array of strings
    examples TEXT,                      -- JSON array of {ja, en, romaji, zh}
    notes TEXT                          -- 含 short / formation / long / source attribution
);
CREATE INDEX idx_grammar_level ON grammar_points(level_hint);

-- 状态表（用户使用产生，不要随意 truncate）

CREATE TABLE articles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    source TEXT,
    raw_text TEXT NOT NULL,
    json_data TEXT NOT NULL,            -- 完整的 Article JSON 序列化存进来
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE occurrences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    article_id INTEGER NOT NULL,
    sentence_idx INTEGER NOT NULL,
    item_type TEXT NOT NULL,            -- 'word' | 'grammar'
    item_key TEXT NOT NULL,             -- dict_form 或 canonical_id
    surface_form TEXT NOT NULL,
    FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE
);
CREATE INDEX idx_occ_article ON occurrences(article_id);
CREATE INDEX idx_occ_item ON occurrences(item_type, item_key);

CREATE TABLE familiarity (
    item_type TEXT NOT NULL,            -- 'word' | 'grammar'
    item_key TEXT NOT NULL,             -- dict_form 或 canonical_id
    score INTEGER NOT NULL DEFAULT 0,   -- 0..5
    seen_count INTEGER NOT NULL DEFAULT 0,
    last_seen TEXT,
    notes TEXT,
    PRIMARY KEY (item_type, item_key)
);
```

### 设计要点

- **参考表 vs 状态表分离**：删 `vocab` / `grammar_points` 安全（重跑 `pnpm seed` 即可恢复）；删状态表会丢用户数据。
- **`articles.json_data` 存全量 JSON**：避免渲染时多次 join。代价是同样的 token meta 在两个地方（json_data 里 + occurrences 里），但 occurrences 是查询索引，json_data 是渲染源。
- **`familiarity` 主键 `(item_type, item_key)`**：词和语法共用一张表，避免后续加新 item 类型（如汉字、片假名外来语）时改 schema。
- **没有外键到参考表**：`occurrences.item_key` 不强约束在 `vocab.dict_form` 或 `grammar_points.canonical_id`，因为 LLM 可能产生 registry 没有的 item（例如新词、新语法），保持灵活。后续要"找文章里所有 unregistered grammar"用 LEFT JOIN 检测。

---

## 常用查询

```sql
-- 我熟悉度还不到 3 的语法点
SELECT g.canonical_id, g.display_form, g.level_hint, COALESCE(f.score, 0) AS score
FROM grammar_points g
LEFT JOIN familiarity f ON f.item_type='grammar' AND f.item_key=g.canonical_id
WHERE COALESCE(f.score, 0) < 3
ORDER BY g.level_hint, g.canonical_id LIMIT 30;

-- 这篇文章里见过哪些 N3+ 语法
SELECT g.canonical_id, g.display_form, g.level_hint, COUNT(*) AS times
FROM occurrences o
JOIN grammar_points g ON o.item_key = g.canonical_id
WHERE o.article_id = ? AND o.item_type = 'grammar'
  AND g.level_hint IN ('N3','N2','N1')
GROUP BY g.canonical_id ORDER BY times DESC;

-- LLM 标了但 registry 里没有的语法（unregistered detect）
SELECT DISTINCT o.item_key, o.surface_form, COUNT(*) AS times
FROM occurrences o
LEFT JOIN grammar_points g ON o.item_key = g.canonical_id
WHERE o.item_type = 'grammar' AND g.canonical_id IS NULL
GROUP BY o.item_key ORDER BY times DESC;

-- 用户标记过的所有 item，按熟悉度
SELECT item_type, item_key, score, last_seen
FROM familiarity ORDER BY score DESC, last_seen DESC;
```

---

## 前端本地状态

上云后 **D1 是熟悉度的唯一真相源**，React SPA 启动时从 `/api/familiarity` 拉取。localStorage 只用于纯客户端偏好（如阈值），不再承担数据持久化：

```js
{
  "jr_threshold": 3   // 仅 UI 偏好，权威数据在 D1
}
```

> 原型阶段 `prototype.html` 支持 `file://` 离线模式（probe `/api/health` 失败则降级到 localStorage，并提供一键 import 到 SQLite）。上云后取消离线模式——app 始终经 Cloudflare Access 鉴权后访问 Worker，不存在脱离服务器运行的场景。KV 缓存（LLM 结果）见 `02-llm-pipeline.md`。
