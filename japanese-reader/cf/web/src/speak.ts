// Text-to-speech. Prefers server-side Gemini neural TTS (/api/tts → audio/wav,
// KV-cached); falls back to the browser Web Speech API if the request fails.
// Callers pass an onState callback to drive the playing indicator on their button.

let currentAudio: HTMLAudioElement | null = null;

function stopAll() {
  if (currentAudio) {
    currentAudio.pause();
    currentAudio = null;
  }
  if (window.speechSynthesis) window.speechSynthesis.cancel();
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

// Warm up the Web Speech voice list (fallback path) on some browsers.
export function warmVoices(): void {
  if (window.speechSynthesis && window.speechSynthesis.getVoices().length === 0) {
    window.speechSynthesis.onvoiceschanged = () => {};
  }
}
