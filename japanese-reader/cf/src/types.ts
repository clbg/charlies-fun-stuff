// Shared types + Worker env bindings.

export interface Token {
  surface: string;
  dict_form: string;
  reading?: string;
  pos?: string;
  meaning_zh?: string;
  start: number;
  end: number;
}

export interface GrammarRef {
  canonical_id: string;
  display_form?: string;
  meaning_zh?: string;
  explanation?: string;
}

export interface Sentence {
  id: string;
  ja: string;
  zh: string;
  tokens: Token[];
  grammar: GrammarRef[];
}

export interface Article {
  title?: string;
  source?: string;
  sentences: Sentence[];
}

export interface Env {
  DB: D1Database;
  CACHE: KVNamespace;
  ASSETS: Fetcher;
  GEMINI_API_KEY: string;
}
