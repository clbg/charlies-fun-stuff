// Text-to-speech. Prefers server-side Gemini neural TTS (/api/tts → audio/wav,
// KV-cached); falls back to the browser Web Speech API if the request fails.
// Callers pass an onState callback to drive the playing indicator on their button.

let currentAudio: HTMLAudioElement | null = null;
let resolveCurrentPlayback: (() => void) | null = null;
// Incremented on every stop; a running sequence checks its captured token to
// know it was cancelled and must not advance to the next sentence.
let playToken = 0;

function stopAll() {
  playToken++;
  if (currentAudio) {
    currentAudio.pause();
    currentAudio = null;
  }
  resolveCurrentPlayback?.();
  resolveCurrentPlayback = null;
  if (window.speechSynthesis) window.speechSynthesis.cancel();
}

// Stop any playback (single sentence or full-text sequence).
export function stopPlayback(): void {
  stopAll();
}

export function pausePlayback(): void {
  if (currentAudio) currentAudio.pause();
  if (window.speechSynthesis) window.speechSynthesis.pause();
}

export function resumePlayback(): void {
  if (currentAudio) void currentAudio.play();
  if (window.speechSynthesis) window.speechSynthesis.resume();
}

export function seekPlayback(deltaSeconds: number): boolean {
  if (!currentAudio) return false;
  const nextTime = currentAudio.currentTime + deltaSeconds;
  const maxTime = Number.isFinite(currentAudio.duration) ? currentAudio.duration : nextTime;
  currentAudio.currentTime = Math.max(0, Math.min(maxTime, nextTime));
  return true;
}

function webSpeechFallback(text: string, onState?: (playing: boolean) => void) {
  if (!window.speechSynthesis) {
    onState?.(false);
    return;
  }
  const u = new SpeechSynthesisUtterance(text);
  u.lang = "ja-JP";
  const jaVoice = window.speechSynthesis.getVoices().find((v) => v.lang && v.lang.startsWith("ja"));
  if (jaVoice) u.voice = jaVoice;
  u.onend = u.onerror = () => onState?.(false);
  onState?.(true);
  window.speechSynthesis.speak(u);
}

export function speak(text: string, onState?: (playing: boolean) => void): void {
  if (!text) return;
  stopAll();

  // Prefer server-side Gemini TTS. The <audio> element streams the cached/synthesized WAV.
  const audio = new Audio(`/api/tts?text=${encodeURIComponent(text)}`);
  currentAudio = audio;
  onState?.(true);

  audio.onended = () => {
    onState?.(false);
    if (currentAudio === audio) currentAudio = null;
  };
  audio.onerror = () => {
    // Server TTS failed (network/5xx) — fall back to Web Speech.
    if (currentAudio === audio) currentAudio = null;
    onState?.(false);
    webSpeechFallback(text, onState);
  };
  // play() can reject (autoplay policy / load error) — fall back too.
  audio.play().catch(() => {
    if (currentAudio === audio) currentAudio = null;
    webSpeechFallback(text, onState);
  });
}

// Play a single text and resolve when it finishes (or fails). Used by the
// sequence player so it can await each sentence before advancing.
function speakOnce(text: string): Promise<void> {
  return new Promise((resolve) => {
    const audio = new Audio(`/api/tts?text=${encodeURIComponent(text)}`);
    currentAudio = audio;
    let settled = false;
    const done = () => {
      if (settled) return;
      settled = true;
      if (resolveCurrentPlayback === done) resolveCurrentPlayback = null;
      if (currentAudio === audio) currentAudio = null;
      resolve();
    };
    resolveCurrentPlayback = done;
    audio.onended = done;
    audio.onerror = () => {
      // Fall back to Web Speech for this sentence, then resolve when it ends.
      if (currentAudio === audio) currentAudio = null;
      if (!window.speechSynthesis) return done();
      const u = new SpeechSynthesisUtterance(text);
      u.lang = "ja-JP";
      const ja = window.speechSynthesis.getVoices().find((v) => v.lang?.startsWith("ja"));
      if (ja) u.voice = ja;
      u.onend = u.onerror = done;
      window.speechSynthesis.speak(u);
    };
    audio.play().catch(() => audio.onerror?.(new Event("error")));
  });
}

/**
 * Read a list of sentences in order (full-text playback). Calls onIndex(i)
 * as each sentence starts and onDone() when finished or stopped. Returns
 * immediately; call stopPlayback() to cancel.
 */
export function speakSequence(
  texts: string[],
  cb: { onIndex?: (i: number) => void; onDone?: () => void; startIndex?: number } = {}
): void {
  stopAll(); // cancel anything in flight (also bumps playToken)
  const token = playToken;
  const startIndex = Math.max(0, Math.min(texts.length - 1, cb.startIndex ?? 0));
  (async () => {
    for (let i = startIndex; i < texts.length; i++) {
      if (token !== playToken) return; // stopped/superseded
      cb.onIndex?.(i);
      await speakOnce(texts[i]);
      if (token !== playToken) return; // stopped during this sentence
    }
    cb.onDone?.();
  })();
}

// Warm up the Web Speech voice list (fallback path) on some browsers.
export function warmVoices(): void {
  if (window.speechSynthesis && window.speechSynthesis.getVoices().length === 0) {
    window.speechSynthesis.onvoiceschanged = () => {};
  }
}
