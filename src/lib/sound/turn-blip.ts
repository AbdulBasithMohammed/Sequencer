// Tiny synthesized blip used as the turn-end cue. WebAudio + a single
// short oscillator with an envelope — no mp3 to ship, plays in ~5ms.
//
// Modules are cached at the AudioContext layer so we don't allocate a
// new context per call (Safari leaks them if you do).

let ctx: AudioContext | null = null;

function getCtx(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (ctx) return ctx;
  type WebkitWindow = Window & {
    webkitAudioContext?: typeof AudioContext;
  };
  const w = window as WebkitWindow;
  const Ctor: typeof AudioContext | undefined =
    window.AudioContext ?? w.webkitAudioContext;
  if (!Ctor) return null;
  ctx = new Ctor();
  return ctx;
}

export function playTurnBlip() {
  const ac = getCtx();
  if (!ac) return;
  // Some browsers (Safari, mobile) suspend the context until a user
  // gesture. Resume is a no-op if already running.
  if (ac.state === "suspended") void ac.resume();

  const now = ac.currentTime;

  // Quick two-step "tap-tap" with a triangle wave. Stays sub-200ms total
  // so it never overlaps the next move.
  const make = (start: number, freq: number, peak: number, dur: number) => {
    const osc = ac.createOscillator();
    const gain = ac.createGain();
    osc.type = "triangle";
    osc.frequency.setValueAtTime(freq, start);
    gain.gain.setValueAtTime(0, start);
    gain.gain.linearRampToValueAtTime(peak, start + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    osc.connect(gain).connect(ac.destination);
    osc.start(start);
    osc.stop(start + dur + 0.02);
  };

  make(now, 660, 0.06, 0.07);
  make(now + 0.08, 880, 0.05, 0.09);
}
