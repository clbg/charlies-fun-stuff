// Browser Web Speech API TTS (replaces server-side Polly).
// Single global utterance at a time; callers pass an onState callback to drive
// the playing indicator on their button.

let current: SpeechSynthesisUtterance | null = null;

export function speak(text: string, onState?: (playing: boolean) => void): void {
  if (!text || !window.speechSynthesis) return;
  window.speechSynthesis.cancel();

  const u = new SpeechSynthesisUtterance(text);
  u.lang = "ja-JP";
  const jaVoice = window.speechSynthesis.getVoices().find((v) => v.lang && v.lang.startsWith("ja"));
  if (jaVoice) u.voice = jaVoice;
  u.onend = u.onerror = () => {
    onState?.(false);
    if (current === u) current = null;
  };
  current = u;
  onState?.(true);
  window.speechSynthesis.speak(u);
}

// Some browsers populate voices() asynchronously; warm it up.
export function warmVoices(): void {
  if (window.speechSynthesis && window.speechSynthesis.getVoices().length === 0) {
    window.speechSynthesis.onvoiceschanged = () => {};
  }
}
