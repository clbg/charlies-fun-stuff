# 02 - LLM 拆解流程

## 任务

输入：一段日语原文
输出：符合 `01-data-model.md` schema 的 JSON

## Prompt 结构

```
[System]
You are a Japanese language analyzer for an adaptive reader.

<grammar_registry>
g_a_demo_b | A。でも、～B。 | N5 | Used to express contrast ...
g_a_dewa_b | A。 では、～B。 | N5 | Indicates a contrast or comparison ...
... (828 lines: id | display_form | level | short_explanation)
</grammar_registry>

Output a JSON object with this schema: {...}
Rules: ...

[User]
（原文）
```

Registry 不再喂整个 markdown 文件，改成从 `grammar_points` 表查询出 compact 格式（一行一条 ~30K tokens）。registry 从 D1 读出后在 Worker 内存缓存（按 schema 版本失效），读取 O(1)。

## 输出约束（provider 无关）

- **强制 JSON**：Gemini 用原生 JSON mode（`responseMimeType: "application/json"` + `responseSchema`）约束输出 schema，比 prompt 末尾 `Output ONLY valid JSON` 更可靠。
- **canonical_id 必须从 registry 选**：除非真的没有，回退到 `g_unregistered`
- **token 偏移**：`start` / `end` 是字符级，渲染时直接 substring；LLM 不输出 offset，由 `assignOffsets()` 算

## 实现要点

走 **Google Gemini 2.5 Flash**（fetch-based，无 SDK 依赖，适配 Workers 运行时）。API key 用 `wrangler secret put GEMINI_API_KEY` 注入，**不进** wrangler.toml / git。

> 选型背景见 `04-infrastructure.md`：原型阶段走 AWS Bedrock（`claude-sonnet-4-6`，ada/midway 内部凭证），上公网后内部凭证失效，且 AWS SDK 在 Workers 上难跑——改用 Gemini fetch API（单人用量基本在免费额度内）。

```ts
// analyze 大致结构（在 Hono Worker 内）

const MODEL = "gemini-2.5-flash";

async function loadGrammarRegistry(env): Promise<string> {
  // query D1 grammar_points → "id | display | level | short" 行，内存缓存
}

export async function analyze(text: string, env): Promise<Article> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "x-goog-api-key": env.GEMINI_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: buildSystemPrompt(await loadGrammarRegistry(env)) }] },
        contents: [{ role: "user", parts: [{ text }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: ARTICLE_SCHEMA,   // 原生 schema 约束
          temperature: 0.2,
          maxOutputTokens: 16000,           // 长输入避免 MAX_TOKENS 截断；长文由 daily.ts 分块
        },
      }),
    }
  );
  const json = await res.json();
  const article = JSON.parse(json.candidates[0].content.parts[0].text);
  return assignOffsets(article);  // ja.indexOf(surface) for each token
}
```

实际还有：缓存（hash(text + registry)）、`g_unregistered` warn、token offset fallback。`repairInnerQuotes` 在 Gemini JSON mode 下大概率不再需要（迁移时实测确认，见 §未决）。

## 缓存策略

- Cache key = `sha1(registry)[:8] + sha1(text)[:12]`，存 **KV**（`env.CACHE.get/put`），替代原本地 `data/cache/`
- 修改 `grammar_points` → registry 文本变化 → registry hash 变化 → 自动失效
- 命中 KV 时零 LLM 成本

## 错误处理 / 可靠性

- **analyze 重试**：Gemini 偶发 503（high demand）/ 429 / 5xx / 连接挂死，`callGemini` 最多重试 5 次（指数退避 0.8→1.6→3.2→6.4s），每次用 AbortController 设 **120s** 超时——挂死的请求快速失败再重试，不会一直卡住。这是"不断掉"的关键。
- **TTS 重试**：`tts.ts` 的 `synthesize` 也有同款重试（最多 4 次，退避 0.8→1.6→3.2s，每次 60s 超时）。TTS 与 analyze 共用 Gemini 配额，长文每日预热（20+ 句连发）容易撞瞬时限流——重试保证预热尽量灌满。
- **模型**：用 `gemini-2.5-flash`（冷调用约 15-45s）。实测它严格遵守"只输出实词"规则，token 干净。`flash-lite` 快 4-5 倍但会把助词/标点也当 token 输出（视觉噪音），故不用——可靠 + 干净优先于速度。
- **前端反馈**：分析时按钮显示"分析中… Ns"实时计时 + "首次分析约需 10–20 秒"提示，缓解长等待焦虑。
- **JSON 解析失败**：Gemini JSON mode 下罕见；三级兜底——①直接 parse ②`repairInnerQuotes`（CJK 间 `"` → `」`）③`stripControlChars`（剥离字符串里的裸控制字符），仍失败时若 `finishReason=MAX_TOKENS` 明确报"输入太长需分块"，否则抛原错。
- **token surface 找不到**：`assignOffsets` warn 但保留 token（start=end=-1），渲染降级
- **g_unregistered**：warn 列出所有未在 registry 的 surface，方便后续手动审视

## 成本估算

- Prompt：registry ~30K tokens（828 行 compact）+ system rules ~500 tokens
- 输出：每篇文章 ~1-3K tokens
- Gemini 2.5 Flash：$0.30/1M input、$2.50/1M output，且有免费额度——单人约 30 篇/月基本免费
- KV 缓存命中时零成本

## 已知坑

- **JSON 中的 ASCII 双引号**：LLM 在中文解释里偶尔写出 `"今天"` 这种字面量双引号，会破坏 JSON。Gemini JSON mode 已大幅缓解；保留启发式修复（CJK 间 `"` → `」`）作兜底。
- **Workers CPU 限制**：免费版每次调用 10ms CPU。LLM 等待是 I/O 不算，但 `assignOffsets` 遍历 + `repairInnerQuotes` 正则在超长文章上有概率擦边，需留意（见 `04-infrastructure.md` 未决点）。

## 后续优化

- **检索式 registry**：现在每次都喂 828 项（30K tokens）。可以先做粗略匹配只塞相关 50 项进 prompt
- **增量分析**：长文章按段落切（现在用户得自己分），避免单次输出 token 爆炸
- **prompt / context cache**：Gemini 支持 context caching，但有按小时存储费，低频调用不一定划算（见 `04-infrastructure.md` GPT 核实结论）；先靠 KV 结果缓存
- **回填中文释义**：`grammar_points.meaning_zh` 全空，可以让 LLM 一次性翻译 828 条 short_explanation 入库

## TTS（语音）

朗读用 **Gemini TTS**（`gemini-2.5-flash-preview-tts`），同一个 `GEMINI_API_KEY`、fetch 调用，跑在 `/api/tts`：
- 输出 16-bit PCM（L16/24kHz），Worker 包 44 字节 WAV 头返回 `audio/wav`
- 按 `sha1(voice+text)` 存 KV 缓存（同一句永不重复合成）
- 默认音色 `Kore`；前端 `speak.ts` 优先用 `/api/tts`，网络/错误时回退浏览器 Web Speech
- **重试**：`synthesize` 对 503/429/5xx/超时重试 4 次（退避 0.8→1.6→3.2s，每次 60s 超时），与 analyze 同款
- **预热**：每日任务（`daily.ts`）逐句调 `synthesize` 灌 KV → 点朗读/全文朗读是缓存命中。长文（20+ 句）连发偶尔仍会被限流，未灌满的句子点开时即时合成（略延迟），不影响功能
- **全文朗读**：前端 `speakSequence`（`App.tsx`）顺序连播整篇，靠预热的 KV 缓存做到流畅，详见 `03-rendering.md`
- 取代了原型阶段的 AWS Polly 与上云初期的纯浏览器 Web Speech（系统语音机械、依赖设备）
