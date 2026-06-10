# 04 - 基础设施与部署

> 目标：本地自用阅读器上公网，**单人使用、低成本（目标 $0/月）**，顺带把前端从单文件
> `prototype.html` 重写为 React + responsive。本文档是部署架构的权威设计。

> ✅ **已上线（2026-06-08）**：https://jr-app.chengpeng.press
> 全栈跑在 Cloudflare Workers，代码在 `cf/`，旧本地原型（`prototype.html` + Express）原样保留。
> 实测：Gemini 在线分析、D1 全量数据（5 文章 / 1888 熟悉度 / 828 语法）、KV 缓存、React 桌面+移动端、
> Cloudflare Access（Cloudflare 账号登录 + Instant Auth，仅本人，未登录 302 拦截）全部通过。
> 下方"未决点"已全部落定，保留作决策记录。

## 目标架构：全 Cloudflare

```
┌─────────────────────────────────────────────┐
│  Cloudflare（一个账号，全在免费额度内）          │
│                                               │
│  [Cloudflare Access] ← 边缘鉴权，请求进 Worker  │
│         │              之前就拦下（见 §鉴权）    │
│  ┌──────▼───────┐   静态资源                    │
│  │ React SPA    │ ← Vite build，Workers Assets  │
│  │ (responsive) │     托管（替代 prototype.html）│
│  └──────┬───────┘                              │
│         │ fetch /api/*                         │
│  ┌──────▼───────┐                              │
│  │ Hono on      │ ← 替代 Express，端点逐个平移，  │
│  │ Workers      │    全部改 async               │
│  └──┬────┬───┬──┘                              │
│   ┌─▼─┐ ┌▼─┐ │  D1: articles/occurrences/      │
│   │D1 │ │KV│ │      familiarity（强一致，SQL    │
│   └───┘ └──┘ │      原样，COUNT DISTINCT 保留）  │
│              │  KV: LLM 结果缓存（替代           │
│              │       data/cache/*.json）        │
└──────────────┼───────────────────────────────┘
               │ fetch（公网 HTTPS）
        ┌──────▼──────┐
        │ Gemini API  │ ← 替代 Bedrock
        │ 2.5 Flash   │
        └─────────────┘

   TTS → /api/tts（Gemini neural TTS，PCM→WAV，KV 缓存）
         前端失败时回退浏览器 Web Speech
```

## 决议逐项

| 维度 | 原型阶段（本地/内部） | 目标 | 理由 |
|---|---|---|---|
| **托管** | 本地 Express | **Cloudflare Workers** | 全免费额度内，CI/CD 是强项 |
| **DB** | better-sqlite3 + 本地 .db | **D1** | 同为 SQLite/异步/强一致，`prepare().all()/.get()/.run()` 几乎 1:1 加 `await`，`COUNT(DISTINCT)` 原样保留，比改 KV 工作量更小 |
| **缓存** | `data/cache/*.json` | **KV** | LLM 结果天生 key→json blob，最贴合 KV |
| **Web 框架** | Express（346 行） | **Hono** | Workers 跑不了 Express，端点逐个平移 + async 化 |
| **LLM** | Bedrock `claude-sonnet-4-6`（ada/midway 内部凭证） | **Gemini 2.5 Flash**（fetch-based） | 内部凭证上云必失效；Gemini Flash $0.30/$2.50 且有免费额度，单人几乎吃不完；AWS SDK 在 Workers 上很难跑 |
| **TTS** | AWS Polly neural（内部凭证） | **Gemini TTS（neural）+ /api/tts + KV 缓存** | 同一个 Gemini key、fetch 调用；PCM 包 WAV 返回；Web Speech 作回退。比浏览器系统语音自然 |
| **前端** | 单文件 `prototype.html`（vanilla JS） | **React + Vite + responsive** | 组件化、移动端适配；产物用 Workers Assets 托管 |
| **CI/CD** | 无 | **GitHub Actions + `cloudflare/wrangler-action@v3`** | 比 Workers Builds 黑盒更可控：部署前能跑 build/test/Gemini 冒烟测试/D1 migration |
| **鉴权** | 跳过（全本地） | **Cloudflare Access** | 公网必须做，否则任何人知道 URL 就能烧 Gemini key、读学习数据 |

## 鉴权（Cloudflare Access）

- **原理**：网络边缘拦截，请求到 Worker **之前**就要求登录。未登录看到登录页，根本加载不到 app。app 本身**一行鉴权代码都不用写**。
- **价格**：$0 永久，免费 50 用户/50 app，不要信用卡。
- **保护范围**：前端 SPA + 所有 `/api/*` 一起罩住。
- **登录方式**：**Cloudflare 账号**（2026-05 新增的内置 IdP，用你已有的 CF 账号登录，不需第三方 OAuth、不需邮箱验证码；可复用账号上的 passkey / Touch ID）。也支持 Google / GitHub / One-Time PIN 等任选。
- **策略**：一条 `Action: Allow` + `Emails: 本人邮箱`；IdP 侧再开"限制为帐户成员"加一层。
- **⚠️ 前提**：域名 DNS 要托管在 Cloudflare。`*.workers.dev` 默认域名套不上 Access，**需绑自定义域名**走 Cloudflare DNS（≈$10/年，本方案唯一可能费用）。
- **退路**（不想要域名时）：Hono 加 ~20 行共享密码中间件，校验请求头密钥。够单人用，但体验/安全差一档。

## CI/CD（GitHub Actions）

`git push main` → Actions 跑 build/test → `wrangler deploy`。用官方 `cloudflare/wrangler-action@v3`：

```yaml
# .github/workflows/deploy.yml
name: Deploy Worker
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm test          # Vite build / Gemini JSON 冒烟测试 塞这
      - uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: deploy
```

- **API token**：Cloudflare 后台建 scoped token（仅 `Edit Cloudflare Workers`），存进 GitHub repo Secrets。Account ID 不是机密（后台 URL 里就有），token 才是钥匙，别提交别打日志。
- **⚠️ Secrets 不随 Actions 走**：`GEMINI_API_KEY` 用 `wrangler secret put` 一次性设到 Workers，**不要**放 wrangler.toml。
- **⚠️ D1 migration 不随 deploy 自动走**：deploy 前加一步 `wrangler d1 migrations apply <db> --remote`，或手动跑。首次建库 + 灌 828 条语法那次建议本地手动跑更稳。
- 备选：Cloudflare 原生 **Workers Builds**（连 Git 自动部署，零 YAML），但黑盒，塞不进 build/test/migration 步骤——故选 Actions。

## 成本估算（单人、约 30 篇/月）

| 项 | 月成本 | 免费额度 |
|---|---|---|
| Workers + D1 + KV | $0 | D1 5GB / 5M 行读·日 / 10万行写·日；KV 10万读·日 |
| Gemini 2.5 Flash | $0 | 在免费额度内 |
| Web Speech TTS | $0 | 浏览器本地合成 |
| Cloudflare Access | $0 | 50 用户永久免费 |
| **域名**（若用 Access） | **~$10/年** | 唯一可能费用 |

## 迁移工作量（4 块）

1. **DB → D1**：不难，`prepare` 调用加 `await`，`occurrences` 关系查询原样保留。
2. **Express → Hono**：路由重写，346 行逐端点平移。
3. **全链路 sync → async**。
4. **AWS SDK（Bedrock + Polly）→ Gemini fetch + Web Speech**：provider 替换。

## GPT 独立核实结论（2026-06-08）

让 GPT 搜官方价格页逐条核实，方向全对，3 处修正已纳入上文：

1. **Cloudflare Containers** 能跑普通容器/Node，但磁盘 ephemeral（睡眠清空）、最低 $5/月，不适合 SQLite 文件持久化——故仍选纯 Workers + D1。
2. **prompt caching 的 0.1× 不能无脑套**：Claude cache 写入 5min TTL 1.25×、1h 2×；Gemini explicit cache 还有 $1/M tokens·小时存储费，低频反而亏。本方案靠 KV 结果缓存，不依赖 token 级 cache。
3. **Fly.io ~$1–2/月**成立但价格要看休眠 + volume，已非首选。

GPT 补充的备选（已评估不选）：Oracle Cloud Always Free（真免费但运维/账户风控麻烦）、Railway（volume 仅 0.5GB，TTS/缓存不够用）。

## 被否决的方案

| 方案 | 否决理由 |
|---|---|
| **AWS Lightsail/EC2 + 个人 AWS 账号** | 改动最小（LLM/TTS provider 都不换，仅换个人 IAM 凭证），$3.5–5/月固定。但**不是 $0**，且未选全 Cloudflare 的免费 + CI/CD + Access 组合。⭐ 是最省事的回退选项：嫌 Cloudflare 重写量大时可走它（Bedrock + Polly 原样保留） |
| **Fly.io + SQLite** | 后端几乎不动（better-sqlite3 原样），~$1–2/月。同样非 $0，最终选了更彻底的 Cloudflare |
| **Railway / Render** | $5/月，不免费 |
| **Cloudflare Containers** | $5/月起 + 磁盘 ephemeral，不适合 SQLite 文件持久化 |

## 未决点 → 已全部落定（2026-06-08）

1. **域名** ✅：用 `chengpeng.press`（你的 Cloudflare zone）。
   - 注意：自定义域名必须是**一级子域名**（`jr-app.chengpeng.press`），因为免费 Universal SSL 只覆盖 apex + 一级；两级（`jr.app.…`）会 TLS 握手失败，需付费 ACM。
   - 选了 Cloudflare Access（零鉴权代码），未用共享密码中间件。
2. **Gemini JSON 输出质量** ✅：实测真实日语文章，原生 JSON mode（`responseSchema`）输出干净，无 ASCII 引号问题。`repairInnerQuotes` 已保留作兜底，实际未触发。
3. **Gemini 免费额度区域政策** ✅：在日本，复用 vault 的 `GEMINI_API_KEY`，实测可用。
4. **Workers CPU 限制**：免费版每次调用 10ms CPU。实测正常文章无问题；超长文章理论上有擦边风险，暂未遇到。

## 鉴权落地细节（实际配置，2026-06-10 更新）

- **登录方式**：**Cloudflare 账号 IdP**（内置，开了"限制为帐户成员"）。app 的身份提供商设为**仅 Cloudflare** + **Instant Auth 开**（跳过选择页，直达 Cloudflare 登录）。登录靠 Cloudflare 账号本身的安全（含 passkey / Touch ID）。
  - 演进：上线初期用 One-time PIN（输邮箱验证码）→ 后改为 Cloudflare 账号登录（更省事、可 passkey）。One-time PIN 这个 IdP **保留未删**，作为备用（出问题可在后台一键切回）。
- **应用**：Self-hosted，目标 = 公共主机名 `jr-app.chengpeng.press`。
- **策略**：`Only me`，Action=Allow，Include=电子邮件 `charlie.pengcheng@hotmail.com`。
- **会话**：24 小时。
- **验证**：登出后重新访问 → 302 跳 Cloudflare 登录 → 用 CF 账号（passkey）认证 → 回到 app，全程无邮箱验证码。未登录 `curl` 返回 302 → `chengpeng.cloudflareaccess.com`。
- **passkey 提醒**：passkey 体验取决于你 **Cloudflare 账号本身**设了 passkey；账号是整个基础设施（Workers/DNS/域名）的总钥匙，本就该设强 MFA。

## CI/CD（已启用并验证通过 ✅）

> 2026-06-08 实测：push 到 main 自动触发，typecheck → build → D1 迁移 → deploy 全绿。
> 注：Actions 用 Node 22（wrangler v4 要求 ≥22）。

- Workflow 在**仓库根** `.github/workflows/japanese-reader-deploy.yml`（GitHub Actions 只读根目录的 `.github/workflows/`）。
- 触发：push 到 `main` 且改动 `japanese-reader/cf/**`，或手动 `workflow_dispatch`。
- 步骤：`npm ci` → typecheck → `build:web` → `wrangler d1 migrations apply --remote` → `wrangler deploy`。
- **需在 GitHub repo Secrets 配两项**：`CLOUDFLARE_API_TOKEN`（scoped: Edit Workers + D1）、`CLOUDFLARE_ACCOUNT_ID`（= `c9946d3a7e65a9a72585b395c19c8ea7`）。
- `GEMINI_API_KEY` 不在 Actions 里，已通过 `wrangler secret put` 存在 Worker 上。
- 仍可随时手动 `npm run deploy`（二者不冲突）。

## 每日文章任务（Cron + TTS 预热）

每天早上自动放一篇长文，点开即读、语音秒播。

- **触发**：Cloudflare Cron Trigger，`wrangler.toml` `[triggers] crons=["0 21 * * *"]`（21:00 UTC = 06:00 JST）。云端跑，不依赖本机开机。
- **流程**（`src/daily.ts` → `runDaily`）：
  1. 从 `ja.wikipedia.org` MediaWiki API 取随机长文（CC BY-SA，不封爬虫）；循环直到 ≥300 字，截到 ≤700 字的句子边界
  2. **分块 analyze**：按 ~300 字句子边界切块，逐块调 Gemini 再合并句子。一次性分析长文会 MAX_TOKENS 截断/超时/JSON 损坏——分块让每次调用回到短文那种稳定快速区间
  3. 存 D1（articles + occurrences），进侧栏历史
  4. **预热 TTS**：遍历每句调 `synthesize`（带重试）灌 KV → 点朗读/全文朗读是缓存命中（实测 ~7ms），无延迟
- **入口**：
  - 自动：cron（每天，随机文章）
  - 手动：`POST /api/daily`，可选 `?title=` 或 `{title}` body 指定维基条目（不传则随机）；供 skill / 调试
  - skill：`~/.claude/skills/japanese-reader-daily`（"放一篇"/"来篇新文章"/指定主题）
- **为何是维基不是 NHK**：NHK Easy 2025-10 改收费、NHK 普通新闻封爬虫+禁再分发；维基是稳定合法的长文源。
- **可靠性**：
  - analyze：429/503/超时/网络断 重试 5 次（指数退避 0.8→6.4s）+ 每次 **120s** 超时；MAX_TOKENS 显式报错；JSON 三级兜底（直接 parse → 内引号修复 → 控制字符剥离）。
  - TTS：`synthesize` 同款重试（4 次 / 60s 超时）。长文（20+ 句）连发预热偶尔仍被瞬时限流，未灌满的句子点开时即时合成（略延迟），不影响功能。失败计数体现在 `/api/daily` 返回的 `tts_failed`。

## 相关文档

- `00-overview.md` 总体设计与数据流
- `01-data-model.md` JSON schema、D1 表设计
- `02-llm-pipeline.md` Gemini 调用与 prompt 结构
- `03-rendering.md` React 渲染策略
