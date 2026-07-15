import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api } from "./api.js";
import { speak, speakSequence, stopPlayback, warmVoices } from "./speak.js";
import type { Article, ArticleSummary, Familiarity, Sentence, Token, GrammarRef } from "./types.js";

const LS_THRESHOLD = "jr_threshold";

const famKey = (type: string, key: string) => `${type}:${key}`;

// Six-level color tier by familiarity (red→orange→yellow→green→transparent):
//   fam >= threshold → tok-fam-5 (transparent, fully mastered)
//   fam < threshold  → tok-fam-{fam} (0=deep red, 1=salmon, 2=orange, 3=yellow, 4=light green)
function famTier(fam: number, threshold: number): string {
  if (fam >= threshold) return "tok-fam-5";
  return `tok-fam-${Math.max(0, Math.min(4, fam))}`;
}

export function App() {
  const [article, setArticle] = useState<Article | null>(null);
  const [currentArticleId, setCurrentArticleId] = useState<number | null>(null);
  const [familiarity, setFamiliarity] = useState<Familiarity>({});
  const [threshold, setThreshold] = useState<number>(() =>
    parseInt(localStorage.getItem(LS_THRESHOLD) || "5", 10)
  );
  const [rawInput, setRawInput] = useState("");
  const [analyzing, setAnalyzing] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [articles, setArticles] = useState<ArticleSummary[]>([]);
  const [toast, setToast] = useState<string | null>(null);
  // Full-text playback: -1 = not playing, else index of the sentence being read.
  const [playingIndex, setPlayingIndex] = useState(-1);

  const getFam = useCallback(
    (type: string, key: string) => familiarity[famKey(type, key)] ?? 0,
    [familiarity]
  );

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 2200);
  };

  // ---------- Init: load familiarity + history ----------
  useEffect(() => {
    warmVoices();
    api.getFamiliarity().then(setFamiliarity).catch(() => {});
    api.listArticles().then(setArticles).catch(() => {});
  }, []);

  useEffect(() => {
    localStorage.setItem(LS_THRESHOLD, String(threshold));
  }, [threshold]);

  // Stop full-text playback whenever the displayed article changes.
  useEffect(() => {
    stopPlayback();
    setPlayingIndex(-1);
  }, [currentArticleId, article]);

  // ---------- Full-text read-aloud ----------
  const toggleReadAll = useCallback(() => {
    if (playingIndex >= 0) {
      stopPlayback();
      setPlayingIndex(-1);
      return;
    }
    if (!article?.sentences.length) return;
    speakSequence(
      article.sentences.map((s) => s.ja),
      { onIndex: setPlayingIndex, onDone: () => setPlayingIndex(-1) }
    );
  }, [article, playingIndex]);

  // ---------- Familiarity setter (optimistic + POST) ----------
  const setFam = useCallback(async (type: string, key: string, value: number) => {
    const v = Math.max(0, Math.min(5, value));
    setFamiliarity((prev) => ({ ...prev, [famKey(type, key)]: v }));
    try {
      await api.setFamiliarity(type, key, v);
    } catch {
      showToast("保存失败，已暂存本地");
    }
  }, []);

  // ---------- Analyze ----------
  const onAnalyze = async () => {
    const text = rawInput.trim();
    if (!text) {
      showToast("请先粘贴日语原文");
      return;
    }
    setAnalyzing(true);
    setElapsed(0);
    // Analyze can take 10–20s (Gemini processes the 30K-token grammar registry).
    // Show a live elapsed counter so the wait reads as progress, not a freeze.
    const t0 = Date.now();
    const timer = window.setInterval(() => setElapsed(Math.floor((Date.now() - t0) / 1000)), 1000);
    try {
      const result = await api.analyze(text);
      setArticle(result.data);
      setCurrentArticleId(result.article_id);
      api.listArticles().then(setArticles).catch(() => {});
    } catch (e) {
      showToast("分析失败: " + (e instanceof Error ? e.message : String(e)));
    } finally {
      window.clearInterval(timer);
      setAnalyzing(false);
    }
  };

  const onResetFamiliarity = async () => {
    if (!confirm("确定重置所有熟悉度数据？此操作不可撤销。")) return;
    setFamiliarity({});
    try {
      await api.resetFamiliarity();
    } catch {
      showToast("重置失败");
    }
  };

  const onExport = () => {
    const data = { familiarity, threshold, exported_at: new Date().toISOString() };
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `jr-familiarity-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // ---------- Sidebar ----------
  const loadArticle = async (id: number) => {
    try {
      const row = await api.getArticle(id);
      setArticle(row.data);
      setCurrentArticleId(row.id);
      setRawInput(row.raw_text || row.data.sentences.map((s) => s.ja).join("\n"));
    } catch (e) {
      showToast("加载失败: " + (e instanceof Error ? e.message : String(e)));
    }
  };

  const removeArticle = async (id: number) => {
    if (!confirm("删除这篇历史文章？（熟悉度数据保留）")) return;
    try {
      await api.deleteArticle(id);
      if (currentArticleId === id) setCurrentArticleId(null);
      api.listArticles().then(setArticles).catch(() => {});
    } catch (e) {
      showToast("删除失败: " + (e instanceof Error ? e.message : String(e)));
    }
  };

  return (
    <>
      <Sidebar
        open={sidebarOpen}
        articles={articles}
        currentId={currentArticleId}
        onClose={() => setSidebarOpen(false)}
        onSelect={(id) => {
          loadArticle(id);
        }}
        onDelete={removeArticle}
      />
      {!sidebarOpen && (
        <button className="sidebar-toggle" title="历史文章" onClick={() => setSidebarOpen(true)}>
          ☰
        </button>
      )}

      <div className="container">
        <header>
          <h1>Japanese Reader</h1>
          <div className="subtitle">自适应日语阅读器</div>
        </header>

        <div className="controls">
          <label>
            熟悉度阈值
            <input
              type="range"
              min={2}
              max={5}
              step={1}
              value={threshold}
              onChange={(e) => setThreshold(parseInt(e.target.value, 10))}
            />
            <span className="threshold-value">{threshold}</span>
            <span style={{ color: "var(--muted)", fontSize: 12 }}>
              (≥此值=熟，隐藏标注；低两档=半生提示)
            </span>
          </label>
          <button onClick={onResetFamiliarity}>重置熟悉度</button>
          <button onClick={onExport}>导出数据</button>
        </div>

        <div className="input-area">
          <textarea
            value={rawInput}
            onChange={(e) => setRawInput(e.target.value)}
            placeholder="粘贴日语原文，点 Analyze"
          />
          <div className="input-actions">
            <button onClick={onAnalyze} disabled={analyzing}>
              {analyzing ? `分析中… ${elapsed}s` : "Analyze"}
            </button>
            <span className="hint">
              {analyzing ? "首次分析约需 10–20 秒" : "Gemini · Cloudflare"}
            </span>
          </div>
        </div>

        {article && (
          <div>
            <div className="article-title">{article.title || ""}</div>
            <div className="article-source">{article.source || ""}</div>
            {article.sentences.length > 0 && (
              <button
                className={`read-all-btn${playingIndex >= 0 ? " playing" : ""}`}
                onClick={toggleReadAll}
                title="顺序朗读全文"
              >
                {playingIndex >= 0
                  ? `⏹ 停止（${playingIndex + 1}/${article.sentences.length}）`
                  : "▶ 朗读全文"}
              </button>
            )}
            {article.sentences.map((s, i) => (
              <SentenceView
                key={s.id}
                sentence={s}
                threshold={threshold}
                getFam={getFam}
                setFam={setFam}
                isReading={playingIndex === i}
              />
            ))}
          </div>
        )}

        {article && <Stats article={article} threshold={threshold} getFam={getFam} />}

        <footer>Cloudflare Workers · D1 · Gemini · 每日自动更新</footer>
      </div>

      {toast && <div className="toast">{toast}</div>}
    </>
  );
}

// ---------- Sidebar ----------
function Sidebar(props: {
  open: boolean;
  articles: ArticleSummary[];
  currentId: number | null;
  onClose: () => void;
  onSelect: (id: number) => void;
  onDelete: (id: number) => void;
}) {
  return (
    <aside className={`sidebar${props.open ? " open" : ""}`}>
      <div className="sb-head">
        <span>历史文章</span>
        <button className="sb-close" onClick={props.onClose}>
          ×
        </button>
      </div>
      <div className="sb-list">
        {props.articles.length === 0 ? (
          <div className="sb-empty">还没有分析过的文章</div>
        ) : (
          props.articles.map((a) => (
            <div
              key={a.id}
              className={`sb-item${a.id === props.currentId ? " active" : ""}`}
              onClick={() => props.onSelect(a.id)}
            >
              <span className="sb-title" title={a.title || ""}>
                {a.title || "(无标题)"}
              </span>
              <span className="sb-date">{(a.created_at || "").slice(5, 16)}</span>
              <button
                className="sb-del"
                title="删除"
                onClick={(e) => {
                  e.stopPropagation();
                  props.onDelete(a.id);
                }}
              >
                🗑
              </button>
            </div>
          ))
        )}
      </div>
    </aside>
  );
}

// ---------- Sentence ----------
function SentenceView(props: {
  sentence: Sentence;
  threshold: number;
  getFam: (type: string, key: string) => number;
  setFam: (type: string, key: string, value: number) => void;
  isReading?: boolean;
}) {
  const { sentence, threshold, getFam, setFam, isReading } = props;
  const [highlightKey, setHighlightKey] = useState<string | null>(null);
  const [playing, setPlaying] = useState(false);
  const detailsRef = useRef<HTMLDetailsElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);

  // When this sentence becomes the one being read aloud, scroll it into view.
  useEffect(() => {
    if (isReading) rootRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [isReading]);

  const minFam = useMemo(() => {
    let m = 5;
    for (const t of sentence.tokens) m = Math.min(m, getFam("word", t.dict_form));
    for (const g of sentence.grammar) m = Math.min(m, getFam("grammar", g.canonical_id));
    return m;
  }, [sentence, getFam]);

  const defaultOpen = minFam < threshold - 2;

  const focusNote = (type: string, key: string) => {
    if (detailsRef.current) detailsRef.current.open = true;
    setHighlightKey(famKey(type, key));
  };

  return (
    <div className={`sentence${isReading ? " reading" : ""}`} ref={rootRef}>
      <div className="ja-line-wrap">
        <div className="ja-line">
          <TokenSpans
            ja={sentence.ja}
            tokens={sentence.tokens}
            threshold={threshold}
            getFam={getFam}
            onClickToken={(t) => focusNote("word", t.dict_form)}
          />
        </div>
        <button
          className={`sentence-speak${playing ? " playing" : ""}`}
          title="朗读整句"
          onClick={() => speak(sentence.ja, setPlaying)}
        >
          🔊
        </button>
      </div>

      {sentence.grammar.length > 0 && (
        <div className="grammar-chips">
          {sentence.grammar.map((g) => (
            <span
              key={g.canonical_id}
              className={`grammar-chip ${famTier(getFam("grammar", g.canonical_id), threshold)}`}
              title={grammarTip(g, getFam("grammar", g.canonical_id))}
              onClick={() => focusNote("grammar", g.canonical_id)}
            >
              {g.display_form || g.canonical_id}
            </span>
          ))}
        </div>
      )}

      <div className="zh-line">{sentence.zh}</div>

      <Notes
        sentence={sentence}
        detailsRef={detailsRef}
        defaultOpen={defaultOpen}
        highlightKey={highlightKey}
        getFam={getFam}
        setFam={setFam}
      />
    </div>
  );
}

// ---------- Token spans (slice ja by offsets, wrap content tokens) ----------
function TokenSpans(props: {
  ja: string;
  tokens: Token[];
  threshold: number;
  getFam: (type: string, key: string) => number;
  onClickToken: (t: Token) => void;
}) {
  const { ja, tokens, threshold, getFam, onClickToken } = props;
  const sorted = [...tokens].filter((t) => t.end > t.start).sort((a, b) => a.start - b.start);
  const parts: React.ReactNode[] = [];
  let cursor = 0;
  let i = 0;
  for (const t of sorted) {
    if (t.start > cursor) parts.push(<span key={`t${i++}`}>{ja.slice(cursor, t.start)}</span>);
    const fam = getFam("word", t.dict_form);
    parts.push(
      <span
        key={`w${i++}`}
        className={`token ${famTier(fam, threshold)}`}
        title={tokenTip(t, fam)}
        onClick={() => onClickToken(t)}
      >
        {ja.slice(t.start, t.end)}
      </span>
    );
    cursor = t.end;
  }
  if (cursor < ja.length) parts.push(<span key={`t${i++}`}>{ja.slice(cursor)}</span>);
  return <>{parts}</>;
}

// ---------- Notes panel ----------
interface NoteItem {
  type: "word" | "grammar";
  key: string;
  label: string;
  reading: string;
  meaning: string;
  explanation: string;
  speak: string;
}

function Notes(props: {
  sentence: Sentence;
  detailsRef: React.RefObject<HTMLDetailsElement>;
  defaultOpen: boolean;
  highlightKey: string | null;
  getFam: (type: string, key: string) => number;
  setFam: (type: string, key: string, value: number) => void;
}) {
  const { sentence, detailsRef, defaultOpen, highlightKey, getFam, setFam } = props;

  const items = useMemo<NoteItem[]>(() => {
    const out: NoteItem[] = [];
    const seenW = new Set<string>();
    for (const t of sentence.tokens) {
      if (seenW.has(t.dict_form)) continue;
      seenW.add(t.dict_form);
      out.push({
        type: "word",
        key: t.dict_form,
        label: t.dict_form,
        reading: t.reading || "",
        meaning: t.meaning_zh || "",
        explanation: "",
        speak: t.dict_form,
      });
    }
    const seenG = new Set<string>();
    for (const g of sentence.grammar) {
      if (seenG.has(g.canonical_id)) continue;
      seenG.add(g.canonical_id);
      out.push({
        type: "grammar",
        key: g.canonical_id,
        label: g.display_form || g.canonical_id,
        reading: "",
        meaning: g.meaning_zh || "",
        explanation: g.explanation || "",
        speak: "",
      });
    }
    return out;
  }, [sentence]);

  if (items.length === 0) return null;

  return (
    <details className="notes" ref={detailsRef} open={defaultOpen}>
      <summary>注释</summary>
      {items.map((it) => (
        <NoteRow
          key={`${it.type}:${it.key}`}
          item={it}
          fam={getFam(it.type, it.key)}
          highlighted={highlightKey === `${it.type}:${it.key}`}
          setFam={setFam}
        />
      ))}
    </details>
  );
}

function NoteRow(props: {
  item: NoteItem;
  fam: number;
  highlighted: boolean;
  setFam: (type: string, key: string, value: number) => void;
}) {
  const { item, fam, highlighted, setFam } = props;
  const [playing, setPlaying] = useState(false);

  return (
    <div className={`note-item${highlighted ? " highlight" : ""}`}>
      <div className={`note-key${item.type === "grammar" ? " grammar" : ""}`}>
        {item.label}
        {item.reading && <div className="reading">{item.reading}</div>}
      </div>
      <div className="note-meaning">
        {item.meaning}
        {item.explanation && <div className="explanation">{item.explanation}</div>}
      </div>
      <div className="note-actions">
        {item.speak && (
          <button
            className={`speak-btn${playing ? " playing" : ""}`}
            title="朗读"
            onClick={() => speak(item.speak, setPlaying)}
          >
            🔊
          </button>
        )}
        <button
          className="plus-btn"
          title="熟悉度 +1"
          onClick={() => setFam(item.type, item.key, fam + 1)}
        >
          ＋1
        </button>
        <Rating type={item.type} itemKey={item.key} fam={fam} setFam={setFam} />
      </div>
    </div>
  );
}

// ---------- Rating dots (click N → set N; click current top → clear) ----------
function Rating(props: {
  type: string;
  itemKey: string;
  fam: number;
  setFam: (type: string, key: string, value: number) => void;
}) {
  const { type, itemKey, fam, setFam } = props;
  return (
    <>
      <span className="rating" title="点击设熟悉度，再点最高点清零">
        {[1, 2, 3, 4, 5].map((i) => (
          <span
            key={i}
            className={`dot${i <= fam ? " filled" : ""}`}
            onClick={() => setFam(type, itemKey, i === fam ? 0 : i)}
          />
        ))}
      </span>
      <span className="rating-label">{fam}/5</span>
    </>
  );
}

// ---------- Stats ----------
function Stats(props: {
  article: Article;
  threshold: number;
  getFam: (type: string, key: string) => number;
}) {
  const { article, threshold, getFam } = props;
  const { words, grammar, unknown } = useMemo(() => {
    const w = new Set<string>();
    const g = new Set<string>();
    for (const s of article.sentences) {
      for (const t of s.tokens) w.add(t.dict_form);
      for (const gr of s.grammar) g.add(gr.canonical_id);
    }
    let u = 0;
    for (const k of w) if (getFam("word", k) < threshold) u++;
    for (const k of g) if (getFam("grammar", k) < threshold) u++;
    return { words: w.size, grammar: g.size, unknown: u };
  }, [article, threshold, getFam]);

  return (
    <div className="stats">
      <h3>本文统计</h3>
      <div className="row">
        <span className="label">总单词项</span>
        <span>{words}</span>
      </div>
      <div className="row">
        <span className="label">总语法项</span>
        <span>{grammar}</span>
      </div>
      <div className="row">
        <span className="label">{"不熟（< 阈值）"}</span>
        <span>{unknown}</span>
      </div>
    </div>
  );
}

// ---------- Tooltips ----------
function tokenTip(t: Token, fam: number): string {
  const head = t.dict_form + (t.reading && t.reading !== t.dict_form ? ` (${t.reading})` : "");
  const parts = [head];
  if (t.meaning_zh) parts.push(t.meaning_zh);
  parts.push(`熟悉度 ${fam}/5 · 点击查看注释`);
  return parts.join("\n");
}

function grammarTip(g: GrammarRef, fam: number): string {
  const parts = [g.display_form || g.canonical_id];
  if (g.meaning_zh) parts.push(g.meaning_zh);
  if (g.explanation) parts.push(g.explanation);
  parts.push(`熟悉度 ${fam}/5 · 点击查看注释`);
  return parts.join("\n");
}
