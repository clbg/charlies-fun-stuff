// REST client for the Hono Worker. Same-origin in production (and via Vite proxy in dev).
import type { Article, ArticleSummary, Familiarity } from "./types.js";

async function jsonOrThrow<T>(r: Response): Promise<T> {
  if (!r.ok) {
    const err = await r.json().catch(() => ({}) as { error?: string });
    throw new Error((err as { error?: string }).error || `HTTP ${r.status}`);
  }
  return (await r.json()) as T;
}

export const api = {
  async getFamiliarity(): Promise<Familiarity> {
    return jsonOrThrow<Familiarity>(await fetch("/api/familiarity"));
  },

  async setFamiliarity(type: string, key: string, score: number): Promise<void> {
    await jsonOrThrow(
      await fetch("/api/familiarity", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type, key, score }),
      })
    );
  },

  async resetFamiliarity(): Promise<void> {
    await jsonOrThrow(await fetch("/api/familiarity/reset", { method: "POST" }));
  },

  async analyze(text: string): Promise<{ article_id: number | null; data: Article }> {
    return jsonOrThrow<{ article_id: number | null; data: Article }>(
      await fetch("/api/analyze", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      })
    );
  },

  async listArticles(): Promise<ArticleSummary[]> {
    return jsonOrThrow<ArticleSummary[]>(await fetch("/api/articles"));
  },

  async getArticle(id: number): Promise<{ id: number; raw_text: string; data: Article }> {
    return jsonOrThrow<{ id: number; raw_text: string; data: Article }>(await fetch(`/api/articles/${id}`));
  },

  async deleteArticle(id: number): Promise<void> {
    await jsonOrThrow(await fetch(`/api/articles/${id}`, { method: "DELETE" }));
  },
};
