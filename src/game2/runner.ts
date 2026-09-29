import { CHAPTERS, type ChapterDef } from '../game/chapters';
import * as S from '../game/sketch';
import { drawFairy } from '../game/draw';
import { sfx } from '../game/audio';

type Ctx = CanvasRenderingContext2D;

export interface RunnerEvents {
  onGameOver: (score: number, meters: number, biome: number) => void;
}

interface Ent {
  kind: 'thorn' | 'blot' | 'wasp' | 'star' | 'heart' | 'shield';
  x: number;
  y: number;
  h: number; // thorn: length
  top: boolean;
  r: number;
  t: number;
  seed: number;
  a: number;
  vy: number;
  passed: boolean;
  dead: boolean;
}

interface Part {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  max: number;
  size: number;
  color: string;
  kind: number; // 0 dot, 1 sparkle, 2 ring, 3 text, 4 petal, 5 streak
  g: number;
  rot: number;
  text?: string;
}

const GROUND = 40;
const BIOME_LEN = 1600; // world px per biome
const THORN_W = 30;
const WASH: [string, string][] = [
  ['rgba(255,220,230,0.35)', 'rgba(200,235,180,0.35)'],
  ['rgba(200,230,255,0.4)', 'rgba(150,210,230,0.4)'],
  ['rgba(60,50,110,0.5)', 'rgba(30,30,60,0.55)'],
  ['rgba(220,240,255,0.55)', 'rgba(240,250,255,0.35)'],
  ['rgba(40,30,80,0.55)', 'rgba(90,60,120,0.45)'],
];
const HILL: string[] = ['#9cc97a', '#7fb8a0', '#3a3560', '#bcd9ec', '#2c2450'];
const HILL2: string[] = ['#6fae55', '#5a9fc0', '#2a2848', '#d6ecf8', '#3b2f5c'];

type State = 'idle' | 'play' | 'paused' | 'dying' | 'over';

export class Runner {
  canvas: HTMLCanvasElement;
  ctx: Ctx;
  ev: RunnerEvents;
  W = 960;
  H = 540;
  s = 1;
  dpr = 1;
  paper = document.createElement('canvas');
  state: State = 'idle';
  stateT = 0;
  time = 0;
  playT = 0;
  dist = 0;
  speed = 260;
  score = 0;
  displayScore = 0;
  hearts = 3;
  shield = 0;
  combo = 0;
  comboT = 0;
  biome = 0;
  biomeFlash = 0;
  nextSpawn = 300;
  ents: Ent[] = [];
  parts: Part[] = [];
  shake = 0;
  hitstop = 0;
  flash = 0;
  seedC = 1;
  p = { x: 200, y: 270, vx: 0, vy: 0, r: 11, dashT: 0, dashCd: 0, inv: 0, tilt: 0 };
  keys = new Set<string>();
  dashQueued = false;
  touchMode = false;
  joy = { id: -1, ox: 0, oy: 0, x: 0, y: 0, active: false };
  dashBtnId = -1;
  raf = 0;
  last = 0;
  running = true;

  constructor(canvas: HTMLCanvasElement, ev: RunnerEvents) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d')!;
    this.ev = ev;
    this.resize();
    window.addEventListener('resize', this.resize);
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    window.addEventListener('blur', this.onBlur);
    canvas.addEventListener('pointerdown', this.onPointerDown);
    window.addEventListener('pointermove', this.onPointerMove);
    window.addEventListener('pointerup', this.onPointerUp);
    window.addEventListener('pointercancel', this.onPointerUp);
    this.last = performance.now();
    this.raf = requestAnimationFrame(this.loop);
  }

  destroy() {
    this.running = false;
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this.resize);
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    window.removeEventListener('blur', this.onBlur);
    this.canvas.removeEventListener('pointerdown', this.onPointerDown);
    window.removeEventListener('pointermove', this.onPointerMove);
    window.removeEventListener('pointerup', this.onPointerUp);
    window.removeEventListener('pointercancel', this.onPointerUp);
  }

  get ch(): ChapterDef {
    return CHAPTERS[this.biome % CHAPTERS.length];
  }
  get gy() {
    return this.H - GROUND;
  }
  get dark() {
    const id = this.ch.id;
    return id === 'night' || id === 'star';
  }

  resize = () => {
    const cw = window.innerWidth, chh = window.innerHeight;
    this.dpr = Math.min(2, window.devicePixelRatio || 1);
    this.canvas.width = Math.round(cw * this.dpr);
    this.canvas.height = Math.round(chh * this.dpr);
    this.canvas.style.width = cw + 'px';
    this.canvas.style.height = chh + 'px';
    this.s = chh / 540; // fixed vertical world of 540 units
    if (cw / this.s < 480) this.s = cw / 480;
    this.W = cw / this.s;
    this.H = chh / this.s;
    this.buildPaper();
    this.p.y = Math.min(this.p.y, this.gy - 20);
  };

  buildPaper() {
    const c = this.paper;
    c.width = this.canvas.width;
    c.height = this.canvas.height;
    const g = c.getContext('2d')!;
    g.fillStyle = '#f3ecdc';
    g.fillRect(0, 0, c.width, c.height);
    g.fillStyle = g.createPattern(S.paperNoise(), 'repeat')!;
    g.fillRect(0, 0, c.width, c.height);
    const [c1, c2] = WASH[this.biome % WASH.length];
    const gr = g.createLinearGradient(0, 0, 0, c.height);
    gr.addColorStop(0, c1);
    gr.addColorStop(1, c2);
    g.fillStyle = gr;
    g.fillRect(0, 0, c.width, c.height);
    const vg = g.createRadialGradient(c.width / 2, c.height / 2, Math.min(c.width, c.height) * 0.35, c.width / 2, c.height / 2, Math.max(c.width, c.height) * 0.75);
    vg.addColorStop(0, 'rgba(90,70,40,0)');
    vg.addColorStop(1, 'rgba(90,70,40,0.28)');
    g.fillStyle = vg;
    g.fillRect(0, 0, c.width, c.height);
  }

  // ---------------- api ----------------
  start() {
    sfx.init();
    this.ents = [];
    this.parts = [];
    this.dist = 0;
    this.speed = 260;
    this.score = 0;
    this.displayScore = 0;
    this.hearts = 3;
    this.shield = 0;
    this.combo = 0;
    this.comboT = 0;
    this.playT = 0;
    this.nextSpawn = 250;
    this.shake = 0;
    this.hitstop = 0;
    this.flash = 0;
    const p = this.p;
    p.x = this.W * 0.25;
    p.y = this.H * 0.45;
    p.vx = p.vy = 0;
    p.dashT = 0;
    p.dashCd = 0;
    p.inv = 1;
    this.keys.clear();
    this.dashQueued = false;
    if (this.biome !== 0) {
      this.biome = 0;
      this.buildPaper();
    }
    this.biomeFlash = 2.5;
    // opening star arc so the first seconds are rewarding
    for (let i = 0; i < 8; i++) this.addEnt('star', p.x + 160 + i * 38, this.H * 0.45 + Math.sin(i * 0.7) * 50, 9);
    this.state = 'play';
    this.burst(p.x, p.y, 24, this.ch.colors.wing, 220, 1);
    this.ring(p.x, p.y, 60, this.ch.colors.main);
  }
  pause() {
    if (this.state === 'play') this.state = 'paused';
  }
  /** Второй шанс (после рекламы с вознаграждением): продолжить полёт с той же дистанции */
  revive() {
    const p = this.p;
    this.hearts = 3;
    p.inv = 2.5;
    p.vx = p.vy = 0;
    p.dashT = 0;
    p.y = this.H * 0.45;
    this.shake = 0;
    this.flash = 0;
    this.hitstop = 0;
    this.keys.clear();
    this.dashQueued = false;
    // убираем препятствия перед феей и немного сбрасываем скорость
    this.ents = this.ents.filter((e) => e.x > this.W + 40 || e.kind === 'star');
    this.nextSpawn = 350;
    this.playT = Math.max(0, this.playT - 12);
    this.speed = Math.min(this.speed, 300);
    this.state = 'play';
    this.last = performance.now();
    this.burst(p.x, p.y, 40, this.ch.colors.wing, 300, 1);
    this.ring(p.x, p.y, 120, this.ch.colors.main);
    this.popText(p.x + 40, p.y - 40, 'Второй шанс!', this.ch.colors.main, 32);
    sfx.bloom();
  }
  resume() {
    if (this.state === 'paused') {
      this.state = 'play';
      this.last = performance.now();
      this.keys.clear();
    }
  }
  toIdle() {
    this.state = 'idle';
    this.ents = [];
  }

  // ---------------- input ----------------
  onKeyDown = (e: KeyboardEvent) => {
    const k = e.code;
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(k)) e.preventDefault();
    if (e.repeat) return;
    this.keys.add(k);
    if (k === 'Space' || k === 'ShiftLeft' || k === 'ShiftRight' || k === 'KeyJ' || k === 'KeyX') this.dashQueued = true;
    this.touchMode = false;
  };
  onKeyUp = (e: KeyboardEvent) => {
    this.keys.delete(e.code);
  };
  onBlur = () => this.keys.clear();
  w(e: PointerEvent) {
    return { x: e.clientX / this.s, y: e.clientY / this.s };
  }
  dashBtn() {
    return { x: this.W - 78, y: this.H - 92, r: 50 };
  }
  onPointerDown = (e: PointerEvent) => {
    sfx.init();
    if (e.pointerType === 'mouse') {
      if (this.state === 'play') this.dashQueued = true;
      return;
    }
    e.preventDefault();
    this.touchMode = true;
    const w = this.w(e);
    const b = this.dashBtn();
    if (Math.hypot(w.x - b.x, w.y - b.y) < b.r + 25) {
      this.dashQueued = true;
      this.dashBtnId = e.pointerId;
      return;
    }
    if (!this.joy.active) this.joy = { id: e.pointerId, ox: w.x, oy: w.y, x: w.x, y: w.y, active: true };
    else this.dashQueued = true;
  };
  onPointerMove = (e: PointerEvent) => {
    if (this.joy.active && e.pointerId === this.joy.id) {
      const w = this.w(e);
      this.joy.x = w.x;
      this.joy.y = w.y;
      const dx = w.x - this.joy.ox, dy = w.y - this.joy.oy;
      const d = Math.hypot(dx, dy);
      if (d > 70) {
        this.joy.ox = w.x - (dx / d) * 70;
        this.joy.oy = w.y - (dy / d) * 70;
      }
    }
  };
  onPointerUp = (e: PointerEvent) => {
    if (e.pointerId === this.joy.id) {
      this.joy.active = false;
      this.joy.id = -1;
    }
    if (e.pointerId === this.dashBtnId) this.dashBtnId = -1;
  };

  // ---------------- helpers ----------------
  rand(a: number, b: number) {
    return a + Math.random() * (b - a);
  }
  addEnt(kind: Ent['kind'], x: number, y: number, r: number, extra: Partial<Ent> = {}) {
    const e: Ent = { kind, x, y, h: 0, top: false, r, t: 0, seed: this.seedC++ * 1.618, a: Math.random() * 6, vy: 0, passed: false, dead: false, ...extra };
    this.ents.push(e);
    return e;
  }
  addParticle(q: Part) {
    if (this.parts.length > 450) this.parts.shift();
    this.parts.push(q);
  }
  burst(x: number, y: number, n: number, color: string, speed = 180, kind = 0, g = 0) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const sp = speed * (0.3 + Math.random() * 0.7);
      const life = 0.4 + Math.random() * 0.5;
      this.addParticle({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life, max: life, size: 2 + Math.random() * 3, color, kind, g, rot: Math.random() * 6 });
    }
  }
  ring(x: number, y: number, size: number, color: string) {
    this.addParticle({ x, y, vx: 0, vy: 0, life: 0.45, max: 0.45, size, color, kind: 2, g: 0, rot: 0 });
  }
  popText(x: number, y: number, text: string, color = '#2a2420', size = 22) {
    this.addParticle({ x, y, vx: -this.speed * 0.3, vy: -60, life: 0.9, max: 0.9, size, color, kind: 3, g: 0, rot: 0, text });
  }
  mult() {
    return Math.min(5, 1 + Math.floor(this.combo / 8));
  }
  gain(pts: number, x: number, y: number, color: string, combo = true) {
    if (combo) {
      this.combo++;
      this.comboT = 1.8;
    }
    const m = this.mult();
    const v = pts * m;
    this.score += v;
    this.popText(x, y - 14, '+' + v + (m > 1 ? ' ×' + m : ''), color, 17 + m * 2);
  }

  hurt() {
    const p = this.p;
    if (p.inv > 0 || p.dashT > 0 || this.state !== 'play') return false;
    if (this.shield > 0) {
      this.shield = 0;
      p.inv = 1;
      this.shake = 10;
      this.hitstop = 0.06;
      this.burst(p.x, p.y, 24, '#e86a92', 240, 4, 120);
      this.ring(p.x, p.y, 70, '#e86a92');
      this.popText(p.x, p.y - 30, 'Щит!', '#e86a92', 26);
      sfx.crash();
      return true;
    }
    this.hearts--;
    p.inv = 1.4;
    this.shake = 16;
    this.hitstop = 0.1;
    this.flash = 0.35;
    this.combo = 0;
    this.burst(p.x, p.y, 26, '#d8433b', 260, 0, 200);
    this.burst(p.x, p.y, 10, '#2a2420', 200, 5);
    sfx.hit();
    if (this.hearts <= 0) {
      this.state = 'dying';
      this.stateT = 1.1;
      this.shake = 24;
      this.burst(p.x, p.y, 50, this.ch.colors.wing, 320, 1);
      sfx.over();
    }
    return true;
  }

  // ---------------- spawning ----------------
  spawnPattern() {
    const x0 = this.W + 60;
    const top = 40, bot = this.gy;
    const diff = Math.min(1, this.dist / 12000);
    const roll = Math.random();
    let len = 380;
    if (roll < 0.38) {
      // thorn gate
      const gap = 210 - diff * 60;
      const c = this.rand(top + gap / 2 + 30, bot - gap / 2 - 30);
      this.addEnt('thorn', x0, top - 40, 0, { top: true, h: c - gap / 2 - (top - 40) });
      this.addEnt('thorn', x0, c + gap / 2, 0, { top: false, h: bot - (c + gap / 2) + 10 });
      for (let i = 0; i < 3; i++) this.addEnt('star', x0 + (i - 1) * 30, c, 9);
      if (diff > 0.35 && Math.random() < 0.5) {
        // double gate
        const c2 = Math.min(bot - gap / 2 - 30, Math.max(top + gap / 2 + 30, c + this.rand(-120, 120)));
        const x1 = x0 + 230;
        this.addEnt('thorn', x1, top - 40, 0, { top: true, h: c2 - gap / 2 - (top - 40) });
        this.addEnt('thorn', x1, c2 + gap / 2, 0, { top: false, h: bot - (c2 + gap / 2) + 10 });
        this.addEnt('star', x1, c2, 9);
        len += 230;
      }
    } else if (roll < 0.6) {
      // ink blot field
      const n = 2 + Math.floor(diff * 3 + Math.random() * 2);
      for (let i = 0; i < n; i++) this.addEnt('blot', x0 + i * 110 + this.rand(0, 40), this.rand(top + 40, bot - 40), this.rand(16, 26), { vy: this.rand(30, 60) * (Math.random() < 0.5 ? 1 : -1) });
      len += n * 90;
    } else if (roll < 0.78) {
      // star wave
      const n = 10;
      const base = this.rand(top + 90, bot - 90);
      const amp = this.rand(40, 90);
      for (let i = 0; i < n; i++) this.addEnt('star', x0 + i * 34, base + Math.sin(i * 0.6) * amp, 9);
      if (diff > 0.2) this.addEnt('blot', x0 + 170, base + (Math.random() < 0.5 ? -amp - 50 : amp + 50), 20, { vy: 0 });
      len += 200;
    } else {
      // wasps
      const n = 1 + Math.floor(diff * 2 + Math.random());
      for (let i = 0; i < n; i++) this.addEnt('wasp', x0 + i * 140, this.rand(top + 60, bot - 60), 14);
      len += n * 100;
    }
    // occasional power-ups
    const pr = Math.random();
    if (pr < 0.06 && this.hearts < 5) this.addEnt('heart', x0 + len * 0.6, this.rand(top + 60, bot - 60), 12);
    else if (pr < 0.12 && this.shield === 0) this.addEnt('shield', x0 + len * 0.6, this.rand(top + 60, bot - 60), 13);
    this.nextSpawn = len * (1.05 - diff * 0.3);
  }

  // ---------------- loop ----------------
  loop = (now: number) => {
    if (!this.running) return;
    const dt = Math.min(0.033, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    this.time += dt;
    S.setBoil(this.time);
    if (this.state !== 'paused') {
      this.update(dt);
      this.updateParticles(dt);
    }
    this.render();
    this.raf = requestAnimationFrame(this.loop);
  };

  update(dt: number) {
    if (this.hitstop > 0) {
      this.hitstop -= dt;
      return;
    }
    let sdt = dt;
    const p = this.p;
    if (this.state === 'idle') {
      p.x += (this.W * 0.3 - p.x) * dt * 2;
      p.y = this.H * 0.45 + Math.sin(this.time * 1.3) * 60;
      p.vy = Math.cos(this.time * 1.3) * 78;
      this.dist += 160 * dt;
      this.speed = 160;
      if (Math.random() < dt * 30) this.trailSpark();
      this.shake *= 0.9;
      return;
    }
    if (this.state === 'over') return;
    if (this.state === 'dying') {
      sdt *= 0.25;
      this.stateT -= dt;
      if (this.stateT <= 0) {
        this.state = 'over';
        this.ev.onGameOver(this.score, Math.floor(this.dist / 10), this.biome);
        return;
      }
    }
    this.playT += sdt;

    // speed ramps with time; dash gives a burst
    const base = Math.min(620, 260 + this.playT * 5.5);
    const target = p.dashT > 0 ? base * 1.7 : base;
    this.speed += (target - this.speed) * Math.min(1, sdt * 8);
    const dx = this.speed * sdt;
    this.dist += dx;
    if (this.state === 'play') this.score += dx * 0.02;

    // biome change
    const b = Math.floor(this.dist / BIOME_LEN);
    if (b !== this.biome) {
      this.biome = b;
      this.buildPaper();
      this.biomeFlash = 2.5;
      this.ring(p.x, p.y, 90, this.ch.colors.main);
      this.burst(p.x, p.y, 30, this.ch.colors.wing, 260, 1);
      this.gain(250, p.x, p.y - 20, this.ch.colors.main, false);
      sfx.bloom();
    }
    this.biomeFlash = Math.max(0, this.biomeFlash - sdt);

    // spawns
    if (this.state === 'play') {
      this.nextSpawn -= dx;
      if (this.nextSpawn <= 0) this.spawnPattern();
    }

    this.updatePlayer(sdt);
    this.updateEnts(sdt, dx);

    if (this.comboT > 0) {
      this.comboT -= sdt;
      if (this.comboT <= 0) this.combo = 0;
    }
    if (this.speed > 420 && Math.random() < sdt * (this.speed / 30)) {
      this.addParticle({ x: this.W + 20, y: this.rand(40, this.gy), vx: -this.speed * 2.2, vy: 0, life: 0.6, max: 0.6, size: 30 + Math.random() * 50, color: this.dark ? 'rgba(230,220,255,0.35)' : 'rgba(42,36,32,0.25)', kind: 5, g: 0, rot: 0 });
    }
    this.shake = Math.max(0, this.shake - dt * 60);
    this.flash = Math.max(0, this.flash - dt);
  }

  trailSpark() {
    const p = this.p;
    this.addParticle({ x: p.x - 10 + this.rand(-4, 4), y: p.y + this.rand(-6, 6), vx: -this.speed * 0.6 + this.rand(-20, 20), vy: this.rand(-10, 30), life: 0.6, max: 0.6, size: 1.5 + Math.random() * 2.5, color: this.ch.colors.wing, kind: Math.random() < 0.3 ? 1 : 0, g: 20, rot: 0 });
  }

  updatePlayer(dt: number) {
    const p = this.p;
    let ix = 0, iy = 0;
    if (this.state === 'play') {
      const k = this.keys;
      if (k.has('ArrowLeft') || k.has('KeyA')) ix -= 1;
      if (k.has('ArrowRight') || k.has('KeyD')) ix += 1;
      if (k.has('ArrowUp') || k.has('KeyW')) iy -= 1;
      if (k.has('ArrowDown') || k.has('KeyS')) iy += 1;
      if (this.joy.active) {
        const dx = this.joy.x - this.joy.ox, dy = this.joy.y - this.joy.oy;
        const d = Math.hypot(dx, dy);
        if (d > 6) {
          const m = Math.min(1, d / 50);
          ix = (dx / d) * m;
          iy = (dy / d) * m;
        }
      }
    }
    const len = Math.hypot(ix, iy);
    if (len > 1) {
      ix /= len;
      iy /= len;
    }
    if (this.dashQueued && p.dashCd <= 0 && this.state === 'play') {
      p.dashT = 0.28;
      p.dashCd = 0.8;
      p.vy = iy * 200;
      this.shake = Math.max(this.shake, 4);
      this.ring(p.x, p.y, 40, this.ch.colors.wing);
      sfx.dash();
    }
    this.dashQueued = false;
    const k = 1 - Math.exp(-dt * 14);
    p.vx += (ix * 280 - p.vx) * k;
    p.vy += (iy * 340 - p.vy) * k;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    const minX = 30, maxX = this.W * 0.6;
    if (p.x < minX) { p.x = minX; p.vx = 0; }
    if (p.x > maxX) { p.x = maxX; p.vx = 0; }
    if (p.y < 26) { p.y = 26; p.vy = 0; }
    if (p.y > this.gy - 16) { p.y = this.gy - 16; p.vy = 0; }
    p.tilt += (Math.max(-0.5, Math.min(0.5, p.vy / 700)) - p.tilt) * Math.min(1, dt * 10);
    if (p.dashT > 0) {
      p.dashT -= dt;
      this.addParticle({ x: p.x, y: p.y, vx: -this.speed, vy: 0, life: 0.22, max: 0.22, size: 13, color: this.ch.colors.main, kind: 0, g: 0, rot: 0 });
    }
    p.dashCd -= dt;
    p.inv -= dt;
    if (Math.random() < dt * 35) this.trailSpark();
  }

  circleRect(cx: number, cy: number, r: number, x: number, y: number, w: number, h: number) {
    const nx = Math.max(x, Math.min(cx, x + w));
    const ny = Math.max(y, Math.min(cy, y + h));
    const dx = cx - nx, dy = cy - ny;
    return dx * dx + dy * dy < r * r;
  }

  updateEnts(dt: number, dx: number) {
    const p = this.p;
    for (const e of this.ents) {
      if (e.dead) continue;
      e.t += dt;
      e.x -= dx;
      switch (e.kind) {
        case 'thorn': {
          const rx = e.x - THORN_W / 2;
          if (this.circleRect(p.x, p.y, p.r - 1, rx, e.y, THORN_W, e.h)) {
            if (this.hurt()) {
              p.vy = e.top ? 260 : -260;
              this.burst(p.x, p.y, 8, '#4a7a30', 160, 4, 200);
            }
          }
          if (!e.passed && rx + THORN_W < p.x - p.r) {
            e.passed = true;
            const edge = e.top ? e.y + e.h : e.y;
            const gapDist = Math.abs(p.y - edge) - p.r;
            if (this.state === 'play' && gapDist < 20 && p.inv <= 0) {
              this.gain(40, p.x, p.y - 20, '#c9446f');
              this.popText(p.x + 10, p.y - 44, 'Чуть-чуть!', '#c9446f', 24);
              this.burst(p.x, edge, 10, this.ch.colors.accent, 160, 1);
              sfx.tone(1200, 0.08, 'triangle', 0.08);
            }
          }
          break;
        }
        case 'blot':
          e.y += e.vy * dt;
          if (e.y < 60 || e.y > this.gy - 30) e.vy = -e.vy;
          if (this.hitCircle(e)) this.enemyHit(e, 30, '#2a2420');
          break;
        case 'wasp': {
          e.x -= 90 * dt;
          e.y += (p.y - e.y) * Math.min(1, dt * 1.1) + Math.sin(e.t * 7) * 40 * dt;
          if (this.hitCircle(e)) this.enemyHit(e, 40, '#f2c230');
          break;
        }
        case 'star':
          if (this.hitCircle(e, 10)) {
            e.dead = true;
            this.gain(10, e.x, e.y, this.dark ? '#f5e27a' : '#b08810');
            this.burst(e.x, e.y, 8, '#f7d060', 180, 1);
            sfx.pickup(this.combo);
            this.shake = Math.max(this.shake, 1.5);
          }
          break;
        case 'heart':
          if (this.hitCircle(e, 8)) {
            e.dead = true;
            this.hearts = Math.min(5, this.hearts + 1);
            this.popText(e.x, e.y - 20, '+1 ♥', '#d8433b', 28);
            this.burst(e.x, e.y, 18, '#d8433b', 200, 1);
            this.ring(e.x, e.y, 50, '#d8433b');
            sfx.bloom();
          }
          break;
        case 'shield':
          if (this.hitCircle(e, 8)) {
            e.dead = true;
            this.shield = 1;
            this.popText(e.x, e.y - 20, 'Щит из лепестков!', '#e86a92', 24);
            this.burst(e.x, e.y, 20, '#e86a92', 220, 4, 60);
            this.ring(e.x, e.y, 60, '#e86a92');
            sfx.bloom();
          }
          break;
      }
      if (e.x < -120) e.dead = true;
    }
    let j = 0;
    for (let i = 0; i < this.ents.length; i++) if (!this.ents[i].dead) this.ents[j++] = this.ents[i];
    this.ents.length = j;
  }

  hitCircle(e: Ent, extra = 0) {
    const p = this.p;
    const r = e.r + p.r + extra;
    const dx = e.x - p.x, dy = e.y - p.y;
    return dx * dx + dy * dy < r * r;
  }

  enemyHit(e: Ent, pts: number, color: string) {
    const p = this.p;
    if (p.dashT > 0) {
      e.dead = true;
      this.gain(pts, e.x, e.y, color);
      this.burst(e.x, e.y, 20, color, 280, e.kind === 'blot' ? 0 : 1);
      this.burst(e.x, e.y, 10, '#2a2420', 220, 5);
      this.ring(e.x, e.y, 50, this.ch.colors.main);
      this.shake = 9;
      this.hitstop = 0.05;
      sfx.kill();
    } else if (this.hurt()) {
      e.dead = true;
      this.burst(e.x, e.y, 16, '#2a2420', 200, 0);
    }
  }

  updateParticles(dt: number) {
    const ps = this.parts;
    let j = 0;
    for (let i = 0; i < ps.length; i++) {
      const q = ps[i];
      q.life -= dt;
      if (q.life <= 0) continue;
      q.vy += q.g * dt;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      if (q.kind !== 3 && q.kind !== 5) {
        q.vx *= 0.96;
        q.vy *= 0.96;
      }
      q.rot += dt * 4;
      ps[j++] = q;
    }
    ps.length = j;
    this.displayScore += (this.score - this.displayScore) * Math.min(1, dt * 10);
  }

  // ---------------- render ----------------
  render() {
    const ctx = this.ctx;
    const k = this.dpr * this.s;
    const sh = this.shake;
    const sx = sh > 0 ? (Math.random() - 0.5) * sh : 0;
    const sy = sh > 0 ? (Math.random() - 0.5) * sh : 0;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(this.paper, 0, 0);
    ctx.setTransform(k, 0, 0, k, sx * k, sy * k);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    this.drawBackdrop(ctx);
    for (const e of this.ents) this.drawEnt(ctx, e);

    const p = this.p;
    if (this.state !== 'over' && !(p.inv > 0 && this.state === 'play' && Math.floor(this.time * 20) % 2 === 0)) {
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.tilt);
      if (this.shield > 0) {
        for (let i = 0; i < 6; i++) {
          const a = this.time * 3 + (i / 6) * Math.PI * 2;
          S.sEllipse(ctx, Math.cos(a) * 26, Math.sin(a) * 26, 6, 4, 700 + i, '#e86a92', 0.9);
        }
      }
      drawFairy(ctx, 0, 0, this.time, this.ch, 1, p.dashT > 0 ? 1.4 : 1.25, p.dashT > 0 ? 0.6 : 0);
      ctx.restore();
    }
    this.drawParticles(ctx);

    if (this.flash > 0) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = `rgba(200,50,40,${this.flash * 0.5})`;
      ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    }
    ctx.setTransform(k, 0, 0, k, 0, 0);
    if (this.state !== 'idle') this.drawHud(ctx);
    if (this.touchMode && this.state === 'play') this.drawTouch(ctx);
  }

  drawBackdrop(ctx: Ctx) {
    const bi = this.biome % CHAPTERS.length;
    const soft = this.dark ? 'rgba(230,220,255,0.45)' : 'rgba(38,34,32,0.45)';
    // sky objects
    if (this.dark) {
      for (let i = 0; i < 26; i++) {
        const x = ((S.hash(i + 11) * this.W * 1.3 - this.dist * 0.05) % (this.W * 1.3) + this.W * 1.3) % (this.W * 1.3) - 20;
        const y = 30 + S.hash(i + 51) * (this.gy - 200);
        const r = 1.5 + S.hash(i + 91) * 2;
        S.sPoly(ctx, S.starPts(x, y, r * 2, r * 0.7, 4, 0), 300 + i, true, '#f5f0c0', 0.6, 0.3, 'rgba(255,250,220,0.6)');
      }
      S.sCircle(ctx, this.W * 0.8, 80, 34, 400, '#f5eeb8', 1.4, 'rgba(255,250,220,0.8)');
    } else {
      for (let i = 0; i < 4; i++) {
        const span = this.W + 200;
        const cx = ((S.hash(i + 5) * span - this.dist * 0.12) % span + span) % span - 100;
        const cy = 50 + S.hash(i + 15) * 110;
        for (let q = 0; q < 3; q++) S.sCircle(ctx, cx + q * 22, cy + (q % 2) * -8, 16 + (q % 2) * 6, 520 + i * 7 + q, null, 1.1, soft);
      }
    }
    // two parallax hill layers
    this.hills(ctx, 0.2, 90, 150, 70, HILL[bi], 11, soft);
    this.hills(ctx, 0.45, 55, 70, 45, HILL2[bi], 29, soft);
    // ground
    const gy = this.gy;
    S.sPoly(ctx, [-10, gy, this.W + 10, gy, this.W + 10, this.H + 10, -10, this.H + 10], 600, true, HILL2[bi], 1.8, 1);
    const step = 26;
    const off = this.dist % step;
    const n = Math.ceil(this.W / step) + 1;
    const wi = Math.floor(this.dist / step);
    for (let i = 0; i < n; i++) {
      const x = i * step - off;
      const h = 5 + S.hash(wi + i) * 10;
      S.sLine(ctx, x, gy, x - 3, gy - h, wi + i, 1.1, soft, 1);
    }
  }

  hills(ctx: Ctx, factor: number, rise: number, var_: number, stepW: number, fill: string, seed: number, stroke: string) {
    const off = this.dist * factor;
    const first = Math.floor(off / stepW);
    const shift = off - first * stepW;
    const n = Math.ceil(this.W / stepW) + 2;
    const pts: number[] = [];
    const base = this.gy;
    for (let i = 0; i <= n; i++) {
      const idx = first + i;
      const h = rise + Math.sin(idx * 0.45 + seed) * var_ * 0.4 + S.hash(idx + seed) * var_ * 0.5;
      pts.push(i * stepW - shift, base - h);
    }
    pts.push(n * stepW, base, -stepW, base);
    S.sPoly(ctx, pts, seed, true, fill, 1.1, 1.2, stroke);
  }

  drawEnt(ctx: Ctx, e: Ent) {
    const t = this.time;
    switch (e.kind) {
      case 'thorn': {
        const x = e.x, w = THORN_W;
        const y0 = e.y, y1 = e.y + e.h;
        const wav = (yy: number) => Math.sin(yy * 0.05 + e.seed) * 4;
        const pts: number[] = [];
        for (let yy = y0; yy <= y1; yy += 30) pts.push(x - w / 2 + wav(yy), yy);
        pts.push(x - w / 2 + wav(y1), y1);
        for (let yy = y1; yy >= y0; yy -= 30) pts.push(x + w / 2 + wav(yy), yy);
        pts.push(x + w / 2 + wav(y0), y0);
        S.sPoly(ctx, pts, e.seed, true, '#4a7a30', 1.8, 1);
        // thorns
        for (let yy = y0 + 14; yy < y1 - 6; yy += 24) {
          const side = Math.floor((yy - y0) / 24) % 2 === 0 ? -1 : 1;
          const bx = x + side * (w / 2) + wav(yy);
          S.sPoly(ctx, [bx, yy - 5, bx + side * 11, yy + 1, bx, yy + 6], e.seed + yy, true, '#2f5220', 1.1, 0.5);
        }
        // tip bud
        const tipY = e.top ? y1 : y0;
        S.sCircle(ctx, x + wav(tipY), tipY, 9, e.seed + 3, '#8a3b5c', 1.4);
        break;
      }
      case 'blot': {
        ctx.fillStyle = 'rgba(20,16,24,0.85)';
        ctx.beginPath();
        S.ellipsePath(ctx, e.x, e.y, e.r, e.r, e.seed, 0, 0.35);
        ctx.fill();
        for (let i = 0; i < 4; i++) {
          const a = e.seed + i * 1.7;
          S.sCircle(ctx, e.x + Math.cos(a) * (e.r + 7), e.y + Math.sin(a) * (e.r + 7), 3, e.seed + i, '#1a1418', 0.8);
        }
        S.scribble(ctx, e.x, e.y, e.r * 1.1, e.seed, 10, 'rgba(20,16,24,0.8)', 1.2);
        ctx.fillStyle = '#f3ecdc';
        ctx.beginPath();
        ctx.arc(e.x - 6, e.y - 3, 3, 0, 7);
        ctx.arc(e.x + 6, e.y - 3, 3, 0, 7);
        ctx.fill();
        break;
      }
      case 'wasp': {
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.scale(-1, 1);
        const wf = 0.4 + Math.abs(Math.sin(t * 40)) * 0.6;
        ctx.save();
        ctx.scale(1, wf);
        S.sEllipse(ctx, -2, -12, 8, 6, e.seed + 1, 'rgba(200,220,240,1)', 1);
        ctx.restore();
        S.sEllipse(ctx, 0, 0, 14, 8, e.seed, '#f2c230', 1.6);
        S.sLine(ctx, -4, -7, -4, 7, e.seed + 2, 2.5, 'rgba(30,26,24,0.85)', 1);
        S.sLine(ctx, 3, -7, 3, 7, e.seed + 3, 2.5, 'rgba(30,26,24,0.85)', 1);
        S.sPoly(ctx, [-13, -2, -21, 0, -13, 3], e.seed + 4, true, '#2a2420', 1.2, 0.5);
        S.sCircle(ctx, 14, -2, 5, e.seed + 5, '#3a3430', 1.2);
        ctx.restore();
        break;
      }
      case 'star': {
        ctx.fillStyle = 'rgba(255,230,120,0.25)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, 14, 0, 7);
        ctx.fill();
        S.sPoly(ctx, S.starPts(e.x, e.y, 10, 4.2, 5, t * 1.5 + e.seed), e.seed, true, '#f7d060', 1.2, 0.4);
        break;
      }
      case 'heart': {
        const s = 26 + Math.sin(t * 6) * 2;
        ctx.beginPath();
        S.heartPath(ctx, e.x, e.y, s, e.seed);
        ctx.fillStyle = S.hatch(ctx, '#d8433b');
        ctx.fill();
        ctx.strokeStyle = S.GRAPHITE;
        ctx.lineWidth = 1.6;
        ctx.stroke();
        break;
      }
      case 'shield': {
        for (let i = 0; i < 5; i++) {
          const a = (i / 5) * Math.PI * 2 + t;
          S.sEllipse(ctx, e.x + Math.cos(a) * 9, e.y + Math.sin(a) * 9, 7, 5, e.seed + i, '#e86a92', 1);
        }
        S.sCircle(ctx, e.x, e.y, 5, e.seed + 9, '#f2c230', 1);
        break;
      }
    }
  }

  text(ctx: Ctx, x: number, y: number, s: string, color: string, size = 22, align: CanvasTextAlign = 'center') {
    ctx.font = `700 ${size}px Caveat, cursive`;
    ctx.textAlign = align;
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 4;
    ctx.strokeStyle = this.dark && color !== '#2a2420' ? 'rgba(20,16,40,0.7)' : 'rgba(243,236,220,0.85)';
    ctx.strokeText(s, x, y);
    ctx.fillStyle = color;
    ctx.fillText(s, x, y);
  }

  drawParticles(ctx: Ctx) {
    for (const q of this.parts) {
      const a = Math.max(0, q.life / q.max);
      ctx.globalAlpha = a;
      switch (q.kind) {
        case 0:
          ctx.fillStyle = q.color;
          ctx.beginPath();
          ctx.arc(q.x, q.y, q.size * (0.4 + a * 0.6), 0, 7);
          ctx.fill();
          break;
        case 1: {
          const s = q.size * 1.6;
          ctx.strokeStyle = q.color;
          ctx.lineWidth = 1.6;
          ctx.beginPath();
          ctx.moveTo(q.x - s, q.y);
          ctx.lineTo(q.x + s, q.y);
          ctx.moveTo(q.x, q.y - s);
          ctx.lineTo(q.x, q.y + s);
          ctx.stroke();
          break;
        }
        case 2:
          ctx.globalAlpha = a * 0.9;
          S.sCircle(ctx, q.x, q.y, q.size * (1.15 - a * 0.85), q.x + q.y, null, 2, q.color);
          break;
        case 3:
          ctx.globalAlpha = Math.min(1, a * 2);
          this.text(ctx, q.x, q.y, q.text || '', q.color, q.size * (a > 0.85 ? 1 + (a - 0.85) * 3 : 1));
          break;
        case 4:
          ctx.save();
          ctx.translate(q.x, q.y);
          ctx.rotate(q.rot);
          ctx.fillStyle = q.color;
          ctx.beginPath();
          ctx.ellipse(0, 0, q.size * 1.8, q.size, 0, 0, 7);
          ctx.fill();
          ctx.restore();
          break;
        case 5:
          ctx.strokeStyle = q.color;
          ctx.lineWidth = 1.2;
          ctx.beginPath();
          ctx.moveTo(q.x, q.y);
          ctx.lineTo(q.x + q.size, q.y);
          ctx.stroke();
          break;
      }
    }
    ctx.globalAlpha = 1;
  }

  drawHud(ctx: Ctx) {
    const pad = 16;
    const ink = this.dark ? '#f3ecdc' : '#2a2420';
    for (let i = 0; i < Math.max(3, this.hearts); i++) {
      const x = pad + 16 + i * 32, y = pad + 16;
      const full = i < this.hearts;
      const bob = full && this.hearts === 1 ? Math.sin(this.time * 10) * 2 : 0;
      ctx.beginPath();
      S.heartPath(ctx, x, y + bob, 24, 70 + i);
      if (full) {
        ctx.fillStyle = S.hatch(ctx, '#d8433b');
        ctx.fill();
      }
      ctx.strokeStyle = this.dark ? 'rgba(240,230,255,0.9)' : S.GRAPHITE;
      ctx.lineWidth = 1.6;
      ctx.stroke();
    }
    this.text(ctx, pad, pad + 52, 'Очки: ' + Math.floor(this.displayScore), ink, 30, 'left');
    this.text(ctx, pad, pad + 78, Math.floor(this.dist / 10) + ' м', ink, 22, 'left');
    if (this.combo >= 3) {
      const m = this.mult();
      this.text(ctx, pad, pad + 102, `Серия ${this.combo}  ×${m}`, this.ch.colors.main, 22, 'left');
      ctx.strokeStyle = this.ch.colors.main;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(pad, pad + 116);
      ctx.lineTo(pad + 110 * (this.comboT / 1.8), pad + 116);
      ctx.stroke();
    }
    // biome progress
    const cx = this.W / 2;
    this.text(ctx, cx, pad + 14, `Земли: ${this.ch.kind}`, ink, 24);
    const bw = Math.min(200, this.W * 0.35), bx = cx - bw / 2, by = pad + 32;
    S.sPoly(ctx, [bx, by, bx + bw, by, bx + bw, by + 8, bx, by + 8], 99, true, null, 1.2, 0.5, this.dark ? 'rgba(240,230,255,0.9)' : S.GRAPHITE);
    ctx.fillStyle = S.hatch(ctx, this.ch.colors.main, 1.5);
    ctx.fillRect(bx + 2, by + 2, (bw - 4) * ((this.dist % BIOME_LEN) / BIOME_LEN), 4);
    // biome banner
    if (this.biomeFlash > 0) {
      const a = Math.min(1, this.biomeFlash, (2.5 - this.biomeFlash) * 4);
      ctx.globalAlpha = a;
      const lap = Math.floor(this.biome / CHAPTERS.length);
      this.text(ctx, cx, this.H * 0.3, this.ch.kind + (lap > 0 ? ` · круг ${lap + 1}` : ''), this.ch.colors.main, 44);
      this.text(ctx, cx, this.H * 0.3 + 36, `Летит фея ${this.ch.name}`, ink, 26);
      ctx.globalAlpha = 1;
    }
    const p = this.p;
    if (p.dashCd > 0 && this.state === 'play') {
      ctx.strokeStyle = this.ch.colors.main;
      ctx.globalAlpha = 0.6;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(p.x, p.y, 26, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (1 - p.dashCd / 0.8));
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
  }

  drawTouch(ctx: Ctx) {
    const b = this.dashBtn();
    const stroke = this.dark ? 'rgba(240,230,255,0.8)' : S.GRAPHITE;
    const ink = this.dark ? '#f3ecdc' : '#2a2420';
    ctx.globalAlpha = 0.75;
    S.sCircle(ctx, b.x, b.y, b.r * (this.dashBtnId >= 0 ? 0.92 : 1), 555, this.p.dashCd <= 0 ? this.ch.colors.wing : null, 2, stroke);
    this.text(ctx, b.x, b.y, 'Рывок', ink, 24);
    if (this.joy.active) {
      S.sCircle(ctx, this.joy.ox, this.joy.oy, 50, 556, null, 1.6, stroke);
      const dx = this.joy.x - this.joy.ox, dy = this.joy.y - this.joy.oy;
      const d = Math.hypot(dx, dy);
      const m = Math.min(d, 50) / (d || 1);
      S.sCircle(ctx, this.joy.ox + dx * m, this.joy.oy + dy * m, 20, 557, this.ch.colors.main, 1.6, stroke);
    } else if (this.playT < 5) {
      this.text(ctx, this.W * 0.3, this.H - 90, 'Веди пальцем, чтобы лететь', ink, 22);
    }
    ctx.globalAlpha = 1;
  }
}
