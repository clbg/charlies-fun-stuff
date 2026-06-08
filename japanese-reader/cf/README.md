# Japanese Reader — Cloudflare edition

全栈跑在 Cloudflare Workers 上的日语阅读器。React SPA + Hono API + D1 + KV + Gemini。
架构设计见 `../docs/04-infrastructure.md`。

```
React SPA (web/) ──Vite build──▶ web/dist ──┐
                                            ├─▶ Worker (src/index.ts, Hono)
/api/* ─────────────────────────────────────┘     ├─ D1  (state + reference tables)
                                                   ├─ KV  (LLM result cache)
                                                   └─ Gemini 2.5 Flash (analyze)
```

## 本地开发

```bash
npm install

# 1. 建本地 D1 并灌数据（迁移含原 familiarity.db 的全部行）
npm run d1:local            # wrangler d1 migrations apply japanese-reader --local

# 2. 本地 Gemini key（仅本地，已 gitignore）
echo "GEMINI_API_KEY=..." > .dev.vars

# 3a. 一体跑（Worker 同时托管 API + 构建好的 SPA）
npm run dev                 # build:web && wrangler dev → http://localhost:8787

# 3b. 或前后端分离热重载
#     terminal A:
npx wrangler dev --local --port 8787
#     terminal B（Vite，/api 代理到 :8787）:
npm run dev:web
```

迁移文件 `migrations/`：
- `0001_schema.sql` 表结构（同原 better-sqlite3）
- `0002`–`0006` 从原 `data/familiarity.db` 导出的种子数据
  （grammar 828 / vocab 7895 / articles / occurrences / familiarity 1888）

## 部署（首次需要你的凭证）

```bash
# 1. 建远端 D1 + KV（输出真实 id，填进 wrangler.toml 的 PLACEHOLDER）
npx wrangler d1 create japanese-reader
npx wrangler kv namespace create CACHE

# 2. 灌远端 D1
npm run d1:remote

# 3. 设 Gemini key（不进 git / wrangler.toml）
npx wrangler secret put GEMINI_API_KEY

# 4. 部署
npm run deploy              # build:web && wrangler deploy
```

CI/CD：`.github/workflows/deploy.yml`（push main 自动 typecheck→build→migrate→deploy）。
需在 GitHub repo Secrets 设 `CLOUDFLARE_API_TOKEN`（scoped: Edit Workers + D1）和 `CLOUDFLARE_ACCOUNT_ID`。

## 鉴权

公网部署后用 **Cloudflare Access** 在边缘罩住整个 app（零代码，需自定义域名）。
详见 `../docs/04-infrastructure.md` §鉴权。

## 与原型的差异

| | 原型（`../`） | 本目录 |
|---|---|---|
| 前端 | `prototype.html`（vanilla JS） | React + Vite + responsive |
| 后端 | Express + better-sqlite3 | Hono on Workers + D1 |
| LLM | AWS Bedrock（内部凭证） | Gemini 2.5 Flash（fetch + JSON mode） |
| LLM 缓存 | `data/cache/*.json` | KV |
| TTS | AWS Polly | 浏览器 Web Speech API |
| 鉴权 | 无（本地） | Cloudflare Access |
