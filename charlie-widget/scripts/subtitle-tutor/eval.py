"""Score a session log against ground truth.

Ground truth: JSON list of {"text", "shown" (epoch s), "hidden" (epoch s)} — from the synthetic page's
window.__gt, or converted from a YouTube .vtt plus the playback start time (see --vtt/--start).

Logs: ~/Library/Application Support/CharlieWidget/SubtitleTutor/logs/session-*.jsonl
      (`charlie-widget subtitle status` prints the current one).

Usage:
  python3 scripts/subtitle-tutor/eval.py <session.jsonl> --gt gt.json
  python3 scripts/subtitle-tutor/eval.py <session.jsonl> --vtt sub.ja.vtt --start <epoch of video t=0>
"""

import argparse
import json
import re
import statistics
import unicodedata


def norm(s):
    s = unicodedata.normalize("NFKC", s)
    return re.sub(r"\s+", "", s)


def sim(a, b):
    a, b = norm(a), norm(b)
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, cb in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb))
        prev = cur
    return 1 - prev[-1] / max(len(a), len(b))


def parse_vtt(path, start):
    cues, cur = [], None
    ts = re.compile(r"(\d+):(\d+):(\d+\.\d+) --> (\d+):(\d+):(\d+\.\d+)")
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        m = ts.match(line)
        if m:
            h1, m1, s1, h2, m2, s2 = m.groups()
            cur = {"shown": start + int(h1) * 3600 + int(m1) * 60 + float(s1),
                   "hidden": start + int(h2) * 3600 + int(m2) * 60 + float(s2), "text": ""}
            cues.append(cur)
        elif cur is not None and line.strip():
            cur["text"] += re.sub(r"<[^>]+>", "", line)
        elif not line.strip():
            cur = None
    return cues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--gt")
    ap.add_argument("--vtt")
    ap.add_argument("--start", type=float, help="epoch seconds when the video was at t=0")
    ap.add_argument("--json-out")
    a = ap.parse_args()

    ev = [json.loads(l) for l in open(a.log)]
    gt = json.load(open(a.gt)) if a.gt else parse_vtt(a.vtt, a.start)
    t_lo = min(e["wall"] for e in ev)
    t_hi = max(e["wall"] for e in ev)
    gt = [g for g in gt if g["shown"] >= t_lo and g["shown"] <= t_hi - 2]

    emits = {e["id"]: e for e in ev if e["ev"] == "emit"}
    vision_read = {e["id"]: e["text"] for e in ev if e["ev"] == "vision_read"}
    first = {e["id"]: e for e in ev if e["ev"] == "first_display"}
    done = {e["id"]: e for e in ev if e["ev"] == "done"}
    errors = [e for e in ev if e["ev"] == "llm_error"]

    rows = []
    for g in gt:
        # emits that happened while this cue was on screen (+0.5s grace)
        cands = [e for e in emits.values() if g["shown"] - 0.3 <= e["wall"] <= g.get("hidden", g["shown"] + 5) + 0.5]
        best = None
        for e in cands:
            txt = e["text"] or vision_read.get(e["id"], "")
            s = sim(txt, g["text"])
            if best is None or s > best[0]:
                best = (s, e, txt)
        row = {"gt": g["text"].replace("\n", " "), "hit": False}
        if best and best[0] >= 0.5:
            s, e, txt = best
            f = first.get(e["id"])
            row.update(hit=True, sim=round(s, 3), read=txt.replace("\n", " "), source=e["source"],
                       detect_ms=round((e["wall"] - g["shown"]) * 1000),
                       first_ms=f and f["latency_ms"],
                       # end-to-end: subtitle appeared on screen -> first explanation char in the panel
                       e2e_ms=f and round((f["wall"] - g["shown"]) * 1000),
                       llm_ttft_ms=done.get(e["id"], {}).get("llm_ttft_ms"),
                       explanation=done.get(e["id"], {}).get("explanation", ""))
        rows.append(row)

    hits = [r for r in rows if r["hit"]]
    exact = [r for r in hits if r["sim"] >= 0.999]
    e2e = [r["e2e_ms"] for r in hits if r.get("e2e_ms") is not None]
    gt_texts = [norm(g["text"]) for g in gt]
    g_lo = min((g["shown"] for g in gt), default=t_lo) - 0.5
    g_hi = max((g.get("hidden", g["shown"] + 5) for g in gt), default=t_hi) + 0.5
    spurious = [e for e in emits.values()
                if g_lo <= e["wall"] <= g_hi and max((sim(e["text"] or vision_read.get(e["id"], ""), t) for t in gt_texts), default=0) < 0.5
                and e["replacing"] == 0]

    print(f"cues: {len(gt)}  detected: {len(hits)}  exact text: {len(exact)}  "
          f"mean sim: {statistics.mean([r['sim'] for r in hits]) if hits else 0:.3f}")
    print(f"emits: {len(emits)}  spurious emits: {len(spurious)}  llm errors: {len(errors)}  "
          f"vision used: {sum(1 for e in emits.values() if e['source']=='vision')}")
    if e2e:
        e2e_sorted = sorted(e2e)
        p = lambda q: e2e_sorted[min(len(e2e_sorted) - 1, int(q * len(e2e_sorted)))]
        print(f"e2e appear->first char (ms): median {statistics.median(e2e):.0f}  p90 {p(0.9)}  max {max(e2e)}  "
              f"<=1000ms: {sum(1 for x in e2e if x <= 1000)}/{len(e2e)}")
    for r in rows:
        if not r["hit"]:
            print(f"  MISS  {r['gt']}")
        elif r["sim"] < 0.999:
            print(f"  DIFF  {r['gt']}  <-  {r['read']}  ({r['sim']})")
    for e in spurious:
        print(f"  SPURIOUS  {e['text']!r}")
    if a.json_out:
        json.dump(rows, open(a.json_out, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
