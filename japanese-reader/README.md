# Japanese Reader

自适应日语阅读器。粘贴日语 → 双语翻译 + 词/语法注释，按熟悉度自动展开或隐藏。

```
┌─────────────────────────┐
│ 输入框（贴日语）          │
└─────────────────────────┘
         ↓
   src/analyze.ts (Bedrock)  ←──  data/familiarity.db: grammar_points (828)
         ↓
   Article JSON              ──→  data/familiarity.db: articles + occurrences
         ↓
   prototype.html
   （按 familiarity 阈值渲染）   ←→  data/familiarity.db: familiarity
```

> **架构说明**：上图是**早期本地原型**（Express + better-sqlite3 + Bedrock + prototype.html），本 README 描述如何在本地跑它，仅作历史参考。
> **现已全面迁移到 Cloudflare 并上线**：https://jr-app.chengpeng.press （Workers + Hono + D1 + KV + Gemini + React，Cloudflare Access 鉴权，每日自动抓文 + 全文朗读）。
> 云端代码在 **`cf/`**（见 `cf/README.md`），架构设计见 `docs/04-infrastructure.md`。

---

## 30 秒上手

```bash
cd ~/projects/charlies-fun-stuff/japanese-reader

# 1. 确保 AWS 凭证还活着（Bedrock 用）
aws sts get-caller-identity --profile default || \
  ada credentials update --once --account 022717054722 --role IibsAdminAccess-DO-NOT-DELETE --provider conduit --profile default

# 2. 启动服务器
pnpm server

# 3. 浏览器
open http://localhost:5151
```

粘贴日语 → 点 Analyze。完。

---

## 首次设置

```bash
pnpm install              # 装依赖（含 better-sqlite3 native build）
pnpm seed                 # 灌 828 语法 + 7895 词到 SQLite
```

DB 在 `data/familiarity.db`，第一次启动 server 时自动建表。

---

## 文件干嘛的

| 文件 | 作用 | 多久碰一次 |
|---|---|---|
| `src/server.ts` | Express 服务，SQLite 持久化 + `/api/analyze` 入口 | 启动时 |
| `src/analyze.ts` | LLM 拆解日语 → JSON。命令行可单跑 | 改 prompt 时 |
| `src/seed.ts` | 从 hanabira/JLPT csv 灌参考表 | 数据源换了才跑 |
| `src/db.ts` | SQLite schema + open helper（共享） | 改 schema 时 |
| `prototype.html` | 前端单文件。可 `file://` 打开（离线降级到 localStorage） | UI 调整 |
| `data/familiarity.db` | 5 张表全在这（见下） | 不要 git |
| `data/hanabira_grammar/` | 语法源数据 5 个 JSON（N5-N1，CC by hanabira.org） | 几乎不动 |
| `docs/` | 设计文档 | 改架构时同步 |

---

## 数据库长什么样

| 表 | 行数 | 含义 |
|---|---|---|
| `vocab` | 7895 | 参考：JLPT 词汇表（dict_form 主键，含读音、英文、级别） |
| `grammar_points` | 828 | 参考：N5-N1 语法（canonical_id 主键，含 display_form、level、英文 short/long、formation、examples JSON） |
| `articles` | n | 你分析过的每篇文章（raw_text + 完整 json_data） |
| `occurrences` | n | 文章里每个 word/grammar 的出现记录（用于"我见过几次"） |
| `familiarity` | n | 熟悉度评分（item_type, item_key, score 0-5） |

完整 schema 见 `docs/01-data-model.md`，或 `sqlite3 data/familiarity.db ".schema"`。

### 常用查询

```bash
# 现在数据库里有啥
sqlite3 -header -column data/familiarity.db "
  SELECT 'vocab' AS t, COUNT(*) FROM vocab
  UNION ALL SELECT 'grammar_points', COUNT(*) FROM grammar_points
  UNION ALL SELECT 'articles', COUNT(*) FROM articles
  UNION ALL SELECT 'occurrences', COUNT(*) FROM occurrences
  UNION ALL SELECT 'familiarity', COUNT(*) FROM familiarity;
"

# 我熟悉度还不够 3 的语法点
sqlite3 -header -column data/familiarity.db "
  SELECT g.canonical_id, g.display_form, g.level_hint, COALESCE(f.score, 0) AS score
  FROM grammar_points g
  LEFT JOIN familiarity f ON f.item_type='grammar' AND f.item_key=g.canonical_id
  WHERE COALESCE(f.score, 0) < 3
  ORDER BY g.level_hint LIMIT 20;
"

# 某篇文章里所有出现
sqlite3 -header -column data/familiarity.db "
  SELECT sentence_idx, item_type, item_key, surface_form
  FROM occurrences WHERE article_id=1;
"
```

---

## 离线模式

不启服务器也能用：

```bash
open prototype.html
```

直接浏览器打开。熟悉度存 localStorage。Analyze 按钮灰掉（没 LLM）。可以加载内置示例文章看渲染。

---

## 命令行 Analyze（不走服务器）

```bash
pnpm analyze "今日は天気がいいです。"
pnpm analyze -- --file input.txt --out data/samples/foo.json
pnpm analyze "..." -- --model opus      # 难句切 Opus
pnpm analyze "..." -- --no-cache        # 跳过 LLM 缓存
```

输出 JSON 到 stdout 或 `--out`。`data/cache/` 里有按 (registry hash, text hash) 缓存，重跑同样输入是免费的。

> 注：`pnpm` 的 `--` 把后续 flag 转给脚本而非 pnpm 自己。直接 `pnpm analyze "..."`（无 flag）也行。

---

## API 端点（server.ts）

| 路径 | 方法 | 干嘛 |
|---|---|---|
| `/api/health` | GET | 健康检查 |
| `/api/analyze` | POST `{text}` | LLM 拆解 + 写入 articles/occurrences |
| `/api/familiarity` | GET / POST | 拉取 / 设置单条评分 |
| `/api/familiarity/import` | POST | 从 localStorage 批量导入 |
| `/api/familiarity/reset` | POST | 清空所有评分 |
| `/api/articles` | GET / `<id>` GET / DELETE | 文章列表/详情/删除 |
| `/api/stats` | GET | 总数统计 |

---

## 技术选型摘要

| 层 | 选什么 | 理由 |
|---|---|---|
| LLM 调用 | AWS Bedrock + `@aws-sdk/client-bedrock-runtime` | 走 ada profile，不需要外部 API key（同 undercurrent） |
| 默认模型 | `us.anthropic.claude-sonnet-4-6` | 速度/成本/质量平衡；难句切 opus |
| 后端 | Express + better-sqlite3 | 单文件 DB，无需 server，本地优先；同步 API、零回调 |
| 运行 | tsx（直跑 .ts，无需编译） | 开发快；想生产化也可 `tsc && node dist/...` |
| 前端 | 单 HTML + 原生 JS | 零依赖，可独立 file://，可 server-served |
| 鉴权 | 跳过 | 全本地 |

---

## 已知坑

- **`AWS_BEARER_TOKEN_BEDROCK`**：vault `.env` 里曾设过，会让 AWS SDK 优先用它而忽略 IAM profile。`analyze.ts:stripBearerToken()` 调用时主动 delete 掉，确保走 ada profile。
- **JSON 中的 ASCII 双引号**：LLM 偶尔在中文里写 `"今天"`。Prompt 里禁止了，解析失败时启发式把 CJK 间的 `"` 替换为 `」` 重试（见 `repairInnerQuotes`）。
- **AWS token 过期**：每天要 `ada credentials update` 一次。30 秒上手那段已经包含。
- **`grammar_points.meaning_zh` 全空**：hanabira 是英文源。LLM 当场生成的中文写在 `articles.json_data` 里，没回填到参考表。后续可以批量翻译。
- **`pnpm install` 第一次 native module 不 build**：pnpm 默认拒绝运行未授权的 install scripts。`pnpm-workspace.yaml` 里已经把 `better-sqlite3` 和 `esbuild` 加进 `onlyBuiltDependencies`，正常 install 即可。如果 binding 找不到，跑 `pnpm rebuild better-sqlite3` 修复。

---

## 设计文档

| 文档 | 看点 |
|---|---|
| `docs/00-overview.md` | 总体设计 + 数据流 + 当前阶段 |
| `docs/01-data-model.md` | JSON schema、SQLite 表设计 |
| `docs/02-llm-pipeline.md` | Prompt 结构、Bedrock 调用、踩过的坑 |
| `docs/03-rendering.md` | 渲染策略和交互细节 |

---

## 下一步候选（按价值排）

1. 给 `grammar_points.meaning_zh` 批量补中文（让 LLM 翻译 828 条 short_explanation 一次性入库）
2. 多文章管理 UI（列表 / 切换 / 删除）
3. 别名匹配（很多语法 LLM 会用变体写法标 canonical_id，可以做 fuzzy match）
4. 复习模式（按 familiarity 倒序展示历史出现的句子）
