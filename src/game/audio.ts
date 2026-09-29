class Sfx {
  ac: AudioContext | null = null;
  master: GainNode | null = null;
  noiseBuf: AudioBuffer | null = null;
  muted = localStorage.getItem('fairy_muted') === '1';

  init() {
    try {
      if (!this.ac) {
        const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
        this.ac = new AC();
        this.master = this.ac.createGain();
        this.master.gain.value = 0.5;
        this.master.connect(this.ac.destination);
        const len = this.ac.sampleRate * 0.5;
        this.noiseBuf = this.ac.createBuffer(1, len, this.ac.sampleRate);
        const d = this.noiseBuf.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      }
      if (this.ac.state === 'suspended' && !this.suspended) this.ac.resume();
    } catch {
      /* no audio */
    }
  }
  suspended = false;
  /** Глушит звук во время рекламы / паузы платформы / скрытой вкладки */
  suspend(on: boolean) {
    this.suspended = on;
    if (this.master && this.ac) this.master.gain.setTargetAtTime(on ? 0 : 0.5, this.ac.currentTime, 0.02);
  }
  setMuted(m: boolean) {
    this.muted = m;
    localStorage.setItem('fairy_muted', m ? '1' : '0');
  }
  tone(f: number, d: number, type: OscillatorType = 'sine', v = 0.2, f2?: number, delay = 0) {
    if (!this.ac || !this.master || this.muted || this.suspended) return;
    const t = this.ac.currentTime + delay;
    const o = this.ac.createOscillator();
    const g = this.ac.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f, t);
    if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + d);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(v, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + d);
    o.connect(g).connect(this.master);
    o.start(t);
    o.stop(t + d + 0.02);
  }
  noise(d: number, v: number, freq = 1200, delay = 0) {
    if (!this.ac || !this.master || !this.noiseBuf || this.muted || this.suspended) return;
    const t = this.ac.currentTime + delay;
    const s = this.ac.createBufferSource();
    s.buffer = this.noiseBuf;
    const f = this.ac.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = freq;
    const g = this.ac.createGain();
    g.gain.setValueAtTime(v, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + d);
    s.connect(f).connect(g).connect(this.master);
    s.start(t);
    s.stop(t + d);
  }
  pickup(combo: number) {
    const f = 523 * Math.pow(2, Math.min(combo, 14) / 12);
    this.tone(f, 0.12, 'triangle', 0.16);
    this.tone(f * 1.5, 0.12, 'sine', 0.07, undefined, 0.04);
  }
  dash() {
    this.noise(0.16, 0.12, 2400);
    this.tone(280, 0.14, 'sine', 0.08, 820);
  }
  hit() {
    this.tone(220, 0.35, 'sawtooth', 0.14, 55);
    this.noise(0.25, 0.3, 500);
  }
  kill() {
    this.tone(760, 0.14, 'square', 0.06, 180);
    this.noise(0.1, 0.12, 3000);
  }
  bloom() {
    [523, 659, 784, 1046].forEach((f, i) => this.tone(f, 0.28, 'triangle', 0.13, undefined, i * 0.06));
  }
  splash() {
    this.noise(0.3, 0.22, 900);
    this.tone(900, 0.2, 'sine', 0.08, 300);
  }
  crash() {
    this.noise(0.2, 0.15, 4000);
    this.tone(1400, 0.1, 'triangle', 0.05, 700);
  }
  boom() {
    this.tone(120, 0.5, 'sawtooth', 0.2, 40);
    this.noise(0.5, 0.35, 300);
  }
  win() {
    [523, 659, 784, 1046, 1318].forEach((f, i) => this.tone(f, 0.4, 'triangle', 0.13, undefined, i * 0.09));
  }
  over() {
    [392, 330, 262, 196].forEach((f, i) => this.tone(f, 0.45, 'triangle', 0.14, undefined, i * 0.16));
  }
  click() {
    this.tone(660, 0.06, 'triangle', 0.08);
  }
}

export const sfx = new Sfx();
