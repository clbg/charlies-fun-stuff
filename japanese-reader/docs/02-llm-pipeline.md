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
          maxOutputTokens: 8000,
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

## 错误处理

- **JSON 解析失败**：Gemini JSON mode 下罕见；保留 `repairInnerQuotes`（CJK 间 `"` → `」`）作兜底，再失败打印 raw 抛错
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
