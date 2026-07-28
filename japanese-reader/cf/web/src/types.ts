export interface Token {
  surface: string;
  dict_form: string;
  reading?: string;
  pos?: string;
  meaning_zh?: string;
  study?: boolean;
  start: number;
  end: number;
}

export interface GrammarRef {
  canonical_id: string;
  display_form?: string;
  meaning_zh?: string;
  explanation?: string;
  study?: boolean;
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

export interface ArticleSummary {
  id: number;
  title: string;
  source: string;
  created_at: string;
}

export type Familiarity = Record<string, number>;
