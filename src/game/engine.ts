import { CHAPTERS, PAINTS, type ChapterDef } from './chapters';
import { EMPTY_UPGRADES, type Upgrades } from './shop';
import * as S from './sketch';
import { drawFairy, drawScene } from './draw';
import { sfx } from './audio';

type Ctx = CanvasRenderingContext2D;

export interface GameEvents {
  onChapterClear: (idx: number, bonus: number, score: number) => void;
  onGameOver: (score: number, chapter: number) => void;
}

interface Ent {
  kind: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  t: number;
  seed: number;
  hp: number;
  a: number;
  b: number;
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

const GROUND = 46;
const MAXS = 330;
const DASH_SPEED = 960;
const HAZARDS = new Set(['wasp', 'flame', 'spark', 'moth', 'icicle', 'orb', 'spider', 'spore', 'inkbub', 'bug', 'beetle', 'bolt']);

type State = 'idle' | 'play' | 'paused' | 'clear' | 'dying' | 'over';

/** Режимы «Книги Фей» */
export type GameMode = 'story' | 'chapter' | 'endless' | 'hard';
/** В бесконечном режиме каждые N выполненных целей дают сердце */
export const ENDLESS_HEART_EVERY = 10;

export class Game {
  canvas: HTMLCanvasElement;
  ctx: Ctx;
  ev: GameEvents;
  W = 960;
  H = 540;
  s = 1;
  dpr = 1;
  bg: HTMLCanvasElement = document.createElement('canvas');
  state: State = 'idle';
  stateT = 0;
  time = 0;
  chT = 0;
  chIdx = 0;
  score = 0;
  displayScore = 0;
  hearts = 3;
  mode: GameMode = 'story';
  /** купленные в лавке улучшения */
  upgrades: Upgrades = { ...EMPTY_UPGRADES };
  shield = 0;
  // радужная глава: текущая краска феи
  paint = 0;
  // грибная глава: хоровод
  seqNext = 0;
  ringT = 0;
  ringMax = 1;
  ringCx = 0;
  ringCy = 0;
  ringR = 100;
  wave = 0;
  nextHeartAt = ENDLESS_HEART_EVERY;
  combo = 0;
  comboT = 0;
  progress = 0;
  ents: Ent[] = [];
  parts: Part[] = [];
  shake = 0;
  hitstop = 0;
  flash = 0;
  timers: Record<string, number> = {};
  wind = 0;
  windT = 0;
  followers = 0;
  trail: { x: number; y: number }[] = [];
  p = { x: 200, y: 270, vx: 0, vy: 0, r: 11, facing: 1, dashT: 0, dashCd: 0, inv: 0, carry: 0, dx: 1, dy: 0 };
  keys = new Set<string>();
  dashQueued = false;
  touchMode = false;
  joy = { id: -1, ox: 0, oy: 0, x: 0, y: 0, active: false };
  dashBtnId = -1;
  raf = 0;
  last = 0;
  seedCounter = 1;
  running = true;

  constructor(canvas: HTMLCanvasElement, ev: GameEvents) {
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
    return CHAPTERS[this.chIdx];
  }
  get gy() {
    return this.H - GROUND;
  }

  // ---------------- setup ----------------
  resize = () => {
    const cw = window.innerWidth;
    const chh = window.innerHeight;
    this.dpr = Math.min(2, window.devicePixelRatio || 1);
    this.canvas.width = Math.round(cw * this.dpr);
    this.canvas.height = Math.round(chh * this.dpr);
    this.canvas.style.width = cw + 'px';
    this.canvas.style.height = chh + 'px';
    this.s = Math.min(cw, chh) / 540;
    this.W = cw / this.s;
    this.H = chh / this.s;
    this.buildBg();
    const p = this.p;
    p.x = Math.min(Math.max(p.x, 20), this.W - 20);
    p.y = Math.min(Math.max(p.y, 20), this.gy - 20);
    for (const e of this.ents) {
      if (e.kind === 'sprout') e.x = this.W / 2;
      if (e.kind === 'paint') {
        e.x = this.W * ((e.a + 0.5) / 3);
        e.y = this.gy - 18;
      }
      if (e.kind === 'nest') {
        e.x = e.b ? this.W - 70 : 70;
        e.y = this.gy - 40;
      }
      if (e.kind === 'bud' || e.kind === 'lantern') {
        e.x = Math.min(e.x, this.W - 40);
        e.y = Math.min(e.y, this.gy - 40);
      }
    }
  };

  buildBg() {
    const c = this.bg;
    c.width = this.canvas.width;
    c.height = this.canvas.height;
    const g = c.getContext('2d')!;
    g.fillStyle = '#f3ecdc';
    g.fillRect(0, 0, c.width, c.height);
    const pat = g.createPattern(S.paperNoise(), 'repeat')!;
    g.fillStyle = pat;
    g.fillRect(0, 0, c.width, c.height);
    g.setTransform(this.dpr * this.s, 0, 0, this.dpr * this.s, 0, 0);
    drawScene(g, this.ch, this.W, this.H, GROUND);
    // vignette
    g.setTransform(1, 0, 0, 1, 0, 0);
    const vg = g.createRadialGradient(c.width / 2, c.height / 2, Math.min(c.width, c.height) * 0.35, c.width / 2, c.height / 2, Math.max(c.width, c.height) * 0.75);
    vg.addColorStop(0, 'rgba(90,70,40,0)');
    vg.addColorStop(1, 'rgba(90,70,40,0.28)');
    g.fillStyle = vg;
    g.fillRect(0, 0, c.width, c.height);
  }

  // ---------------- public api ----------------
  preview(idx: number) {
    this.chIdx = idx;
    this.state = 'idle';
    this.ents = [];
    this.buildBg();
  }

  newRun(mode: GameMode = this.mode) {
    this.mode = mode;
    this.score = 0;
    this.displayScore = 0;
    this.hearts = this.maxStartHearts();
    this.combo = 0;
  }

  maxStartHearts() {
    return this.mode === 'hard' ? 1 : 3 + this.upgrades.heart;
  }
  dashCdMax() {
    return 0.45 * (1 - 0.12 * this.upgrades.dash);
  }
  isDark() {
    const id = this.ch.id;
    return id === 'night' || id === 'star' || id === 'storm';
  }
  /** можно ли сейчас подобрать предмет (для магнита) */
  canPick(e: Ent) {
    const c = this.p.carry;
    switch (e.kind) {
      case 'pollen':
        return c < 6;
      case 'drop':
        return c < 5;
      case 'shard':
      case 'sun':
        return c < 3;
      case 'firefly':
        return e.b <= 0;
      case 'flake':
      case 'crystal':
        return true;
      default:
        return false;
    }
  }
  get endless() {
    return this.mode === 'endless';
  }
  scoreMult() {
    return this.mode === 'hard' ? 2 : 1;
  }

  /** Перезапуск текущего режима (для одиночной главы / бесконечного — та же глава) */
  restart() {
    const idx = this.mode === 'chapter' || this.mode === 'endless' ? this.chIdx : 0;
    this.newRun();
    this.startChapter(idx);
  }

  startChapter(idx: number) {
    sfx.init();
    this.chIdx = idx;
    this.buildBg();
    this.ents = [];
    this.parts = [];
    this.progress = 0;
    this.wave = 0;
    this.nextHeartAt = ENDLESS_HEART_EVERY;
    this.followers = 0;
    this.wind = 0;
    this.windT = 6;
    this.chT = 0;
    this.combo = 0;
    this.comboT = 0;
    this.shake = 0;
    this.hitstop = 0;
    this.timers = {};
    const p = this.p;
    p.x = this.W * 0.3;
    p.y = this.H * 0.5;
    p.vx = p.vy = 0;
    p.dashT = 0;
    p.dashCd = 0;
    p.inv = 1.2;
    p.carry = 0;
    this.shield = this.mode !== 'hard' && this.upgrades.shield > 0 ? 1 : 0;
    this.paint = 0;
    this.seqNext = 0;
    p.facing = 1;
    this.trail = [];
    this.keys.clear();
    this.dashQueued = false;
    this.initChapter();
    this.state = 'play';
    this.burst(p.x, p.y, 24, this.ch.colors.wing, 220, 1);
    this.ring(p.x, p.y, 60, this.ch.colors.main);
  }

  /** Второй шанс (после рекламы с вознаграждением): продолжить текущую главу */
  revive() {
    const p = this.p;
    this.hearts = this.maxStartHearts();
    p.inv = 2.5;
    p.vx = p.vy = 0;
    p.dashT = 0;
    this.shake = 0;
    this.flash = 0;
    this.hitstop = 0;
    this.keys.clear();
    this.dashQueued = false;
    for (const e of this.ents) {
      if (HAZARDS.has(e.kind) && Math.hypot(e.x - p.x, e.y - p.y) < 260) {
        e.dead = true;
        this.burst(e.x, e.y, 8, this.ch.colors.wing, 160, 1);
      }
    }
    this.state = 'play';
    this.last = performance.now();
    this.burst(p.x, p.y, 40, this.ch.colors.wing, 300, 1);
    this.ring(p.x, p.y, 120, this.ch.colors.main);
    this.popText(p.x, p.y - 40, 'Второй шанс!', this.ch.colors.main, 32);
    sfx.bloom();
  }

  pause() {
    if (this.state === 'play' || this.state === 'clear') {
      this.stateBeforePause = this.state;
      this.state = 'paused';
    }
  }
  stateBeforePause: State = 'play';
  resume() {
    if (this.state === 'paused') {
      this.state = this.stateBeforePause;
      this.last = performance.now();
      this.keys.clear();
    }
  }
  isPlaying() {
    return this.state === 'play' || this.state === 'clear' || this.state === 'dying';
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
  onBlur = () => {
    this.keys.clear();
  };
  toWorld(e: PointerEvent) {
    return { x: e.clientX / this.s, y: e.clientY / this.s };
  }
  dashBtn() {
    return { x: this.W - 78, y: this.H - 92, r: 50 };
  }
  onPointerDown = (e: PointerEvent) => {
    sfx.init();
    if (e.pointerType === 'mouse') {
      // mouse click = dash too
      if (this.state === 'play') this.dashQueued = true;
      return;
    }
    e.preventDefault();
    this.touchMode = true;
    const w = this.toWorld(e);
    const b = this.dashBtn();
    if (Math.hypot(w.x - b.x, w.y - b.y) < b.r + 25) {
      this.dashQueued = true;
      this.dashBtnId = e.pointerId;
      return;
    }
    if (!this.joy.active) {
      this.joy = { id: e.pointerId, ox: w.x, oy: w.y, x: w.x, y: w.y, active: true };
    } else {
      // second finger tap anywhere = dash
      this.dashQueued = true;
    }
  };
  onPointerMove = (e: PointerEvent) => {
    if (this.joy.active && e.pointerId === this.joy.id) {
      const w = this.toWorld(e);
      this.joy.x = w.x;
      this.joy.y = w.y;
      // drag origin along if finger goes far (floating stick)
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
  spawn(kind: string, x: number, y: number, r: number, extra: Partial<Ent> = {}): Ent {
    const e: Ent = { kind, x, y, vx: 0, vy: 0, r, t: 0, seed: this.seedCounter++ * 1.618, hp: 1, a: 0, b: 0, dead: false, ...extra };
    this.ents.push(e);
    return e;
  }
  count(kind: string) {
    let n = 0;
    for (const e of this.ents) if (e.kind === kind && !e.dead) n++;
    return n;
  }
  randPos(margin = 60) {
    const p = this.p;
    for (let i = 0; i < 10; i++) {
      const x = this.rand(margin, this.W - margin);
      const y = this.rand(110, this.gy - 50);
      if (Math.hypot(x - p.x, y - p.y) > 110) return { x, y };
    }
    return { x: this.rand(margin, this.W - margin), y: this.rand(110, this.gy - 50) };
  }
  touching(e: Ent, extra = 0) {
    const p = this.p;
    const r = e.r + p.r + extra;
    const dx = e.x - p.x, dy = e.y - p.y;
    return dx * dx + dy * dy < r * r;
  }

  addParticle(pt: Part) {
    if (this.parts.length > 450) this.parts.shift();
    this.parts.push(pt);
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
    this.addParticle({ x, y, vx: 0, vy: -60, life: 0.9, max: 0.9, size, color, kind: 3, g: 0, rot: 0, text });
  }

  addScore(pts: number, x: number, y: number, color?: string) {
    this.combo++;
    this.comboT = 2.4;
    const mult = Math.min(5, 1 + Math.floor(this.combo / 5));
    const v = pts * mult * this.scoreMult();
    this.score += v;
    this.popText(x, y - 14, '+' + v + (mult > 1 ? ' ×' + mult : ''), color, 18 + mult * 2);
    return v;
  }

  collect(e: Ent, pts: number, color: string) {
    e.dead = true;
    this.addScore(pts, e.x, e.y, color);
    this.burst(e.x, e.y, 12, color, 200, 1);
    this.ring(e.x, e.y, 26, color);
    sfx.pickup(this.combo);
    this.shake = Math.max(this.shake, 2);
  }

  /** force — урон, который не спасает неуязвимость (например, съеденный росток) */
  damage(force = false): boolean {
    const p = this.p;
    if ((!force && (p.inv > 0 || p.dashT > 0)) || this.state !== 'play') return false;
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
    p.inv = 1.5;
    this.shake = 16;
    this.hitstop = 0.1;
    this.flash = 0.35;
    this.combo = 0;
    this.burst(p.x, p.y, 26, '#d8433b', 260, 0, 200);
    this.burst(p.x, p.y, 10, '#2a2420', 200, 5);
    sfx.hit();
    // chapter penalties
    if (this.ch.id === 'flower' || this.ch.id === 'water') p.carry = Math.max(0, p.carry - 2);
    if (this.ch.id === 'night' && this.followers > 0) {
      for (let i = 0; i < this.followers; i++) {
        const f = this.spawn('firefly', p.x, p.y, 8, { a: Math.random() * 6 });
        const ang = Math.random() * Math.PI * 2;
        f.vx = Math.cos(ang) * 220;
        f.vy = Math.sin(ang) * 220;
        f.b = 0.8; // flee time
      }
      this.popText(p.x, p.y - 30, 'Светлячки разлетелись!', '#7a6cd6', 20);
      this.followers = 0;
    }
    if (this.ch.id === 'star') p.carry = 0;
    if (this.ch.id === 'garden') p.carry = Math.max(0, p.carry - 1);
    if (this.hearts <= 0) {
      this.state = 'dying';
      this.stateT = 1.1;
      this.shake = 24;
      this.burst(p.x, p.y, 50, this.ch.colors.wing, 320, 1);
      sfx.over();
    }
    return true;
  }

  // ---------------- chapter logic ----------------
  initChapter() {
    const W = this.W, gy = this.gy;
    switch (this.ch.id) {
      case 'flower': {
        for (let i = 0; i < 5; i++) {
          const x = W * ((i + 0.5) / 5) + this.rand(-20, 20);
          const y = gy - 50 - Math.random() * Math.min(160, this.H * 0.25);
          this.spawn('bud', x, y, 20);
        }
        for (let i = 0; i < 4; i++) {
          const a = (i / 4) * Math.PI * 2;
          this.spawn('pollen', this.p.x + Math.cos(a) * 90 + 60, this.p.y + Math.sin(a) * 70, 9, { a: Math.random() * 6 });
        }
        this.timers.wasp = 3;
        break;
      }
      case 'water': {
        for (let i = 0; i < 3; i++) this.spawn('drop', this.p.x + 80 + i * 60, this.p.y - 40 + i * 30, 9, { a: Math.random() * 6 });
        this.spawn('flame', this.p.x + 260, this.p.y + 20, 6, { a: 0, b: 2 });
        this.timers.flame = 1.5;
        break;
      }
      case 'night': {
        this.spawn('lantern', W / 2, Math.max(110, this.H * 0.2), 28);
        for (let i = 0; i < 3; i++) {
          const pos = this.randPos();
          this.spawn('firefly', pos.x, pos.y, 8, { a: Math.random() * 6 });
        }
        this.spawn('firefly', this.p.x + 90, this.p.y - 20, 8, { a: 0 });
        this.timers.moth = 4;
        break;
      }
      case 'frost': {
        for (let i = 0; i < 5; i++) this.spawn('flake', this.p.x + 60 + i * 50, this.rand(80, 200), 10, { vy: this.rand(40, 70), a: Math.random() * 6 });
        this.timers.icicle = 2.5;
        this.timers.flake = 0.3;
        this.timers.crystal = 7;
        break;
      }
      case 'star': {
        const boss = this.spawn('boss', W * 0.7, this.H * 0.3, 46, { hp: 6 });
        boss.a = 0;
        for (let i = 0; i < 3; i++) this.spawn('shard', this.p.x + 70 + i * 55, this.p.y + (i % 2 ? -40 : 40), 10, { a: Math.random() * 6 });
        this.timers.attack = 3;
        this.timers.shard = 1;
        break;
      }
      case 'mushroom': {
        this.newRing(true);
        this.timers.spider = 4;
        this.timers.spore = 7;
        this.timers.wrong = 0;
        break;
      }
      case 'rainbow': {
        for (let i = 0; i < 3; i++) this.spawn('paint', W * ((i + 0.5) / 3), gy - 18, 24, { a: i });
        for (let i = 0; i < 4; i++) this.spawn('bubble', this.p.x + 90 + i * 55, this.p.y + (i % 2 ? 30 : -30), 16, { a: i < 3 ? 0 : 1, vy: -18, b: Math.random() * 6 });
        this.timers.bubble = 0.6;
        this.timers.ink = 5;
        break;
      }
      case 'garden': {
        this.spawn('sprout', W / 2, gy - 20, 26, { hp: 5 });
        for (let i = 0; i < 3; i++) this.spawn('sun', this.p.x + 70 + i * 50, this.p.y - 40 + i * 20, 10, { a: Math.random() * 6 });
        this.timers.bug = 3;
        this.timers.sun = 1;
        break;
      }
      case 'storm': {
        this.spawn('nest', W - 70, gy - 40, 38, { b: 1 });
        this.spawn('seed', this.p.x + 60, this.p.y, 13);
        for (let i = 0; i < 2; i++) {
          const pos = this.randPos(90);
          this.spawn('seed', pos.x, Math.min(pos.y, gy - 90), 13);
        }
        this.timers.bolt = 3.5;
        break;
      }
    }
  }

  updateChapter(dt: number) {
    const p = this.p;
    const T = this.timers;
    const t = this.chT;
    const playing = this.state === 'play';
    for (const k in T) T[k] -= dt;

    switch (this.ch.id) {
      case 'flower': {
        if (playing && this.count('pollen') < 5 && Math.random() < dt * 3) {
          const pos = this.randPos();
          this.spawn('pollen', pos.x, pos.y, 9, { a: Math.random() * 6 });
        }
        const maxW = Math.min(4, 1 + Math.floor(t / 12));
        if (playing && T.wasp <= 0 && this.count('wasp') < maxW) {
          const side = Math.random() < 0.5 ? -30 : this.W + 30;
          this.spawn('wasp', side, this.rand(100, this.gy - 100), 14);
          T.wasp = 3.5;
        }
        break;
      }
      case 'water': {
        if (playing && this.count('drop') < 5 && Math.random() < dt * 2.5) {
          const pos = this.randPos();
          this.spawn('drop', pos.x, pos.y, 9, { a: Math.random() * 6 });
        }
        if (playing && T.flame <= 0 && this.count('flame') < 6) {
          const pos = this.randPos();
          this.spawn('flame', pos.x, Math.max(pos.y, this.H * 0.35), 6, { b: this.rand(1.5, 2.5) });
          T.flame = Math.max(1.1, 2.4 - t * 0.02);
        }
        break;
      }
      case 'night': {
        if (playing && this.count('firefly') < 3 && Math.random() < dt * 1.2) {
          const pos = this.randPos();
          this.spawn('firefly', pos.x, pos.y, 8, { a: Math.random() * 6 });
        }
        const maxM = Math.min(5, 2 + Math.floor(t / 15));
        if (playing && T.moth <= 0 && this.count('moth') < maxM) {
          const side = Math.random() < 0.5 ? -30 : this.W + 30;
          this.spawn('moth', side, this.rand(120, this.gy - 60), 16, { a: Math.random() * 6 });
          T.moth = 3;
        }
        break;
      }
      case 'frost': {
        if (playing && T.flake <= 0) {
          this.spawn('flake', this.rand(30, this.W - 30), -20, 10, { vy: this.rand(45, 85), a: Math.random() * 6 });
          T.flake = 0.5;
        }
        if (playing && T.crystal <= 0) {
          this.spawn('crystal', this.rand(60, this.W - 60), -30, 16, { vy: 55, a: 0 });
          T.crystal = 8;
        }
        if (playing && T.icicle <= 0) {
          const rows = t > 20 && Math.random() < 0.4 ? 3 : 1;
          const bx = Math.random() < 0.5 ? p.x + this.rand(-60, 60) : this.rand(40, this.W - 40);
          for (let i = 0; i < rows; i++) this.spawn('icicle', Math.min(this.W - 20, Math.max(20, bx + (i - (rows - 1) / 2) * 70)), -10, 10, { a: 0.9, b: 0 });
          T.icicle = Math.max(0.55, 1.4 - t * 0.015);
        }
        // wind gusts
        this.windT -= dt;
        if (this.windT <= 0) {
          if (this.wind === 0) {
            this.wind = (Math.random() < 0.5 ? -1 : 1) * 190;
            this.windT = 2.5;
            this.popText(this.W / 2, 120, this.wind > 0 ? 'Ветер →' : '← Ветер', '#4fa3cf', 28);
          } else {
            this.wind = 0;
            this.windT = this.rand(4, 7);
          }
        }
        if (this.wind !== 0 && Math.random() < dt * 30) {
          const x = this.wind > 0 ? -20 : this.W + 20;
          this.addParticle({ x, y: this.rand(60, this.gy), vx: this.wind * 4, vy: 0, life: 0.8, max: 0.8, size: 40 + Math.random() * 40, color: 'rgba(80,120,160,0.5)', kind: 5, g: 0, rot: 0 });
        }
        break;
      }
      case 'star': {
        if (playing && this.count('shard') < 2 && T.shard <= 0) {
          const pos = this.randPos();
          this.spawn('shard', pos.x, pos.y, 10, { a: Math.random() * 6 });
          T.shard = 1.2;
        }
        break;
      }
      case 'mushroom': {
        if (playing) {
          this.ringT -= dt;
          if (this.ringT <= 0) {
            this.popText(this.W / 2, 120, 'Хоровод рассыпался!', '#b0603a', 28);
            this.combo = 0;
            sfx.crash();
            for (const e of this.ents) if (e.kind === 'shroom' && !e.dead) this.burst(e.x, e.y, 8, '#c8b890', 120, 0, -40);
            this.newRing();
          }
        }
        const maxS = Math.min(4, 1 + Math.floor(t / 14));
        if (playing && T.spider <= 0 && this.count('spider') < maxS) {
          let x = this.rand(40, this.W - 40);
          if (Math.abs(x - p.x) < 50) x = ((x + this.W / 2) % (this.W - 80)) + 40;
          this.spawn('spider', x, -20, 13, { hp: this.rand(140, this.gy - 50), a: Math.random() * 6 });
          T.spider = 3.4;
        }
        if (playing && T.spore <= 0 && this.count('spore') < 2) {
          const left = Math.random() < 0.5;
          this.spawn('spore', left ? -50 : this.W + 50, this.rand(130, this.gy - 70), 48, { vx: left ? 45 : -45 });
          T.spore = 8;
        }
        break;
      }
      case 'rainbow': {
        if (playing && T.bubble <= 0 && this.count('bubble') < 9) {
          const r = Math.random();
          const col = r < 0.08 ? -1 : r < 0.5 ? this.paint : Math.floor(Math.random() * 3);
          this.spawn('bubble', this.rand(40, this.W - 40), this.gy + 20, this.rand(14, 19), { a: col, vy: -this.rand(38, 60) - Math.min(30, t * 0.4), b: Math.random() * 6 });
          T.bubble = Math.max(0.4, 0.85 - t * 0.005);
        }
        const maxI = Math.min(5, 1 + Math.floor(t / 12));
        if (playing && T.ink <= 0 && this.count('inkbub') < maxI) {
          this.spawn('inkbub', this.rand(40, this.W - 40), this.gy + 20, 16, { vy: -this.rand(50, 85), b: Math.random() * 6 });
          T.ink = 3;
        }
        break;
      }
      case 'garden': {
        if (playing && this.count('sun') < 3 && T.sun <= 0) {
          this.spawn('sun', this.rand(50, this.W - 50), this.rand(90, Math.max(120, this.gy * 0.55)), 10, { a: Math.random() * 6 });
          T.sun = 1.4;
        }
        const maxB = Math.min(6, 1 + Math.floor(t / 10));
        if (playing && T.bug <= 0 && this.count('bug') + this.count('beetle') < maxB) {
          const left = Math.random() < 0.5;
          if (t > 15 && Math.random() < 0.4) this.spawn('beetle', left ? -30 : this.W + 30, this.rand(80, this.gy * 0.5), 13);
          else this.spawn('bug', left ? -30 : this.W + 30, this.gy - 10, 14, { vx: left ? 1 : -1 });
          T.bug = Math.max(1.4, 3.2 - t * 0.03);
        }
        break;
      }
      case 'storm': {
        if (playing && this.count('seed') < 3 && Math.random() < dt * 0.9) {
          const pos = this.randPos(80);
          const sd = this.spawn('seed', pos.x, Math.min(pos.y, this.gy - 90), 13);
          this.burst(sd.x, sd.y, 8, '#ffffff', 90, 1);
        }
        if (playing && T.bolt <= 0) {
          const n = t > 25 && Math.random() < 0.45 ? 2 : 1;
          for (let i = 0; i < n; i++) {
            const x = i === 0 ? Math.max(30, Math.min(this.W - 30, p.x + this.rand(-50, 50))) : this.rand(30, this.W - 30);
            this.spawn('bolt', x, 0, 28, { a: 1.1 });
          }
          T.bolt = Math.max(1.3, 3 - t * 0.03);
        }
        if (Math.random() < dt * 45) this.addParticle({ x: this.rand(0, this.W + 60), y: -10, vx: -60, vy: 520, life: 1.2, max: 1.2, size: 1, color: 'rgba(200,215,240,0.55)', kind: 6, g: 0, rot: 0 });
        break;
      }
    }

    const magR = this.upgrades.magnet > 0 ? 50 + 28 * this.upgrades.magnet : 0;
    let sprout: Ent | undefined;
    let nest: Ent | undefined;
    for (const e of this.ents) {
      if (e.kind === 'sprout') sprout = e;
      else if (e.kind === 'nest') nest = e;
    }

    // per entity
    for (const e of this.ents) {
      if (e.dead) continue;
      e.t += dt;
      // магнит из лавки
      if (magR > 0 && this.canPick(e)) {
        const mx = p.x - e.x, my = p.y - e.y;
        const md = Math.hypot(mx, my);
        if (md < magR && md > 1) {
          const k = Math.min(1, dt * 7);
          e.x += mx * k;
          e.y += my * k;
        }
      }
      switch (e.kind) {
        case 'pollen':
        case 'drop':
        case 'shard':
          e.a += dt;
          e.y += Math.sin(e.a * 2.5) * 12 * dt;
          if (this.touching(e, 8)) {
            if (e.kind === 'pollen') {
              if (p.carry < 6) {
                p.carry++;
                this.collect(e, 10, this.ch.colors.accent);
              }
            } else if (e.kind === 'drop') {
              if (p.carry < 5) {
                p.carry++;
                this.collect(e, 10, '#3a8fd6');
              }
            } else {
              if (p.carry < 3) {
                p.carry++;
                this.collect(e, 20, '#e0a526');
                if (p.carry === 3) {
                  this.popText(p.x, p.y - 36, 'Заряжена! Рывок в Короля!', '#b58cff', 22);
                  this.ring(p.x, p.y, 70, '#ffe89a');
                  sfx.bloom();
                }
              }
            }
          }
          break;
        case 'bud':
          // бесконечный режим: распустившийся цветок через пару секунд снова становится бутоном
          if (this.endless && e.b === 1 && e.t > 2.5) {
            e.b = 0;
            e.a = 0;
            this.burst(e.x, e.y, 10, '#6fb04e', 120, 4, 60);
          }
          if (e.b === 0 && p.carry > 0 && this.touching(e, 4)) {
            e.a += p.carry;
            this.addScore(15 * p.carry, e.x, e.y, '#e86a92');
            p.carry = 0;
            this.burst(e.x, e.y, 10, '#f2c230', 150, 1);
            sfx.pickup(this.combo);
            if (e.a >= 3) {
              e.b = 1;
              e.t = 0;
              this.progress++;
              this.addScore(100, e.x, e.y - 20, '#e86a92');
              this.burst(e.x, e.y, 30, '#e86a92', 280, 4, 120);
              this.burst(e.x, e.y, 16, '#f2c230', 200, 1);
              this.ring(e.x, e.y, 80, '#e86a92');
              this.shake = 8;
              sfx.bloom();
            }
          }
          break;
        case 'wasp': {
          const dx = p.x - e.x, dy = p.y - e.y;
          const d = Math.hypot(dx, dy) || 1;
          const sp = Math.min(230, 140 + t * 2);
          if (e.b > 0) {
            e.b -= dt;
            e.vx *= 0.95;
            e.vy *= 0.95;
          } else {
            e.vx += (dx / d) * 260 * dt;
            e.vy += (dy / d) * 260 * dt + Math.sin(e.t * 6) * 60 * dt;
            const v = Math.hypot(e.vx, e.vy);
            if (v > sp) {
              e.vx *= sp / v;
              e.vy *= sp / v;
            }
          }
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          this.enemyContact(e, 25, '#f2c230');
          break;
        }
        case 'flame': {
          e.a = Math.min(1, e.a + dt / 1.5);
          e.r = 6 + e.a * 16;
          e.b -= dt;
          if (e.b <= 0 && e.a >= 1 && this.state === 'play') {
            e.b = this.rand(1.6, 2.6);
            for (let i = 0; i < 3; i++) {
              const ang = -Math.PI / 2 + (i - 1) * 0.6 + this.rand(-0.15, 0.15);
              this.spawn('spark', e.x, e.y - 10, 5, { vx: Math.cos(ang) * 170, vy: Math.sin(ang) * 170 });
            }
          }
          if (Math.random() < dt * 8) this.addParticle({ x: e.x + this.rand(-6, 6), y: e.y - e.r * 0.6, vx: 0, vy: -50, life: 0.5, max: 0.5, size: 2, color: '#f08a2c', kind: 0, g: -20, rot: 0 });
          if (this.touching(e, -4)) {
            if (p.carry > 0) {
              p.carry--;
              e.dead = true;
              this.progress++;
              this.addScore(50, e.x, e.y, '#3a8fd6');
              this.burst(e.x, e.y, 24, 'rgba(160,170,180,0.8)', 160, 0, -60);
              this.burst(e.x, e.y, 14, '#9fd3f5', 240, 1);
              this.ring(e.x, e.y, 60, '#3a8fd6');
              this.shake = 7;
              this.hitstop = 0.04;
              sfx.splash();
            } else this.damage();
          }
          break;
        }
        case 'spark':
          e.vy += 140 * dt;
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          if (e.y > this.gy || e.t > 4) {
            e.dead = true;
            this.burst(e.x, e.y, 4, '#f08a2c', 60);
          }
          if (this.touching(e, -3)) {
            if (this.damage()) e.dead = true;
          }
          break;
        case 'firefly': {
          e.a += dt * (0.8 + Math.sin(e.seed) * 0.5);
          if (e.b > 0) {
            e.b -= dt;
            e.vx *= 0.96;
            e.vy *= 0.96;
          } else {
            e.vx = Math.cos(e.a) * 40;
            e.vy = Math.sin(e.a * 1.3) * 30;
          }
          e.x = Math.min(this.W - 20, Math.max(20, e.x + e.vx * dt));
          e.y = Math.min(this.gy - 20, Math.max(80, e.y + e.vy * dt));
          if (e.b <= 0 && this.touching(e, 10)) {
            this.followers++;
            this.collect(e, 20, '#f5e27a');
          }
          break;
        }
        case 'lantern':
          if (this.followers > 0 && this.touching(e, 8)) {
            const n = this.followers;
            this.progress += n;
            this.addScore(40 * n, e.x, e.y - 20, '#f5e27a');
            this.followers = 0;
            this.burst(e.x, e.y, 20 + n * 6, '#f5e27a', 260, 1);
            this.ring(e.x, e.y, 90, '#f5e27a');
            this.shake = 6 + n;
            e.a = 1;
            sfx.bloom();
          }
          e.a = Math.max(0, e.a - dt);
          break;
        case 'moth': {
          const light = 130 + this.followers * 14;
          const dx = p.x - e.x, dy = p.y - e.y;
          const d = Math.hypot(dx, dy) || 1;
          e.a += dt;
          let tx: number, ty: number;
          if (e.b > 0) {
            e.b -= dt;
            tx = -dx / d * 120;
            ty = -dy / d * 120;
          } else if (d < light + 90) {
            const sp = 165 + Math.min(40, t);
            tx = (dx / d) * sp;
            ty = (dy / d) * sp;
          } else {
            tx = Math.cos(e.a * 0.7 + e.seed) * 90 + (this.W / 2 - e.x) * 0.2;
            ty = Math.sin(e.a * 1.1 + e.seed) * 70 + (this.H / 2 - e.y) * 0.2;
          }
          e.vx += (tx - e.vx) * Math.min(1, dt * 2.5);
          e.vy += (ty - e.vy) * Math.min(1, dt * 2.5);
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          this.enemyContact(e, 30, '#7a6cd6');
          break;
        }
        case 'flake':
        case 'crystal':
          e.a += dt;
          e.x += (Math.sin(e.a * 2) * 30 + this.wind * 0.6) * dt;
          e.y += e.vy * dt;
          if (e.y > this.gy + 10) e.dead = true;
          if (this.touching(e, 10)) {
            const big = e.kind === 'crystal';
            this.progress += big ? 3 : 1;
            this.collect(e, big ? 60 : 15, big ? '#4fa3cf' : '#9ad8f0');
            if (big) {
              this.ring(e.x, e.y, 70, '#4fa3cf');
              sfx.bloom();
            }
          }
          break;
        case 'icicle':
          if (e.a > 0) {
            e.a -= dt;
            if (e.a <= 0) sfx.crash();
          } else {
            e.vy += 1500 * dt;
            e.y += e.vy * dt;
            if (e.y > this.gy - 10) {
              e.dead = true;
              this.burst(e.x, this.gy - 5, 14, '#bfe6fa', 220, 5, 400);
              this.burst(e.x, this.gy - 5, 8, '#ffffff', 160, 1);
              this.shake = Math.max(this.shake, 3);
            }
            if (this.touching(e, -2)) {
              if (this.damage()) e.dead = true;
            }
          }
          break;
        case 'boss':
          this.updateBoss(e, dt);
          break;
        // ---------- VI. грибной хоровод
        case 'shroom':
          if (e.b === 0 && this.touching(e, 6) && this.state === 'play') {
            if (e.a === this.seqNext) {
              e.b = 1;
              e.t = 0;
              this.seqNext++;
              this.addScore(10 * this.seqNext, e.x, e.y, '#b0603a');
              this.burst(e.x, e.y, 10, '#f7d060', 160, 1);
              this.ring(e.x, e.y, 30, '#f7d060');
              sfx.pickup(this.combo);
              if (this.seqNext >= 5) {
                this.progress++;
                this.addScore(150 + Math.round(this.ringT * 10), this.ringCx, this.ringCy, this.ch.colors.main);
                for (const o of this.ents) if (o.kind === 'shroom') this.burst(o.x, o.y, 14, '#f7d060', 220, 4, 60);
                this.ring(this.ringCx, this.ringCy, this.ringR + 30, this.ch.colors.main);
                this.shake = 8;
                sfx.bloom();
                if (this.endless || this.progress < this.ch.goal) this.newRing();
              }
            } else if ((T.wrong ?? 0) <= 0) {
              T.wrong = 0.8;
              for (const o of this.ents) if (o.kind === 'shroom') o.b = 0;
              this.seqNext = 0;
              this.combo = 0;
              this.burst(e.x, e.y, 16, '#b8a878', 150, 0, -30);
              this.popText(e.x, e.y - 30, 'Не по порядку!', '#8a3b3b', 22);
              this.shake = Math.max(this.shake, 4);
              sfx.tone(160, 0.2, 'square', 0.06, 90);
            }
          }
          break;
        case 'spider': {
          if (e.t < 14) {
            const target = 40 + (e.hp - 40) * (0.55 + 0.45 * Math.sin(e.t * 1.4 + e.a));
            const k = Math.min(1, e.t / 1.2);
            e.y = -20 + (target + 20) * k;
          } else {
            e.y -= 220 * dt;
            if (e.y < -30) e.dead = true;
          }
          this.enemyContact(e, 30, '#6a4a3a');
          break;
        }
        case 'spore':
          e.x += e.vx * dt;
          e.y += Math.sin(e.t * 0.8 + e.seed) * 10 * dt;
          if (e.t > 2 && (e.x < -70 || e.x > this.W + 70)) e.dead = true;
          break;
        // ---------- VII. краски радуги
        case 'paint':
          if (this.paint !== e.a && this.touching(e, 4)) {
            this.paint = e.a;
            const c = PAINTS[e.a].c;
            this.burst(p.x, p.y, 18, c, 200, 0, 60);
            this.ring(p.x, p.y, 40, c);
            this.popText(p.x, p.y - 34, PAINTS[e.a].n + '!', c, 22);
            sfx.splash();
          }
          break;
        case 'bubble': {
          e.y += e.vy * dt;
          e.x += Math.sin(e.t * 2 + e.b) * 22 * dt;
          if (e.y < -30) {
            e.dead = true;
            break;
          }
          if (this.touching(e, 2) && this.state === 'play') {
            if (e.a === -1 || e.a === this.paint) {
              const rb = e.a === -1;
              this.progress += rb ? 3 : 1;
              this.collect(e, rb ? 60 : 20, rb ? '#b58cff' : PAINTS[e.a].c);
              if (rb) this.ring(e.x, e.y, 60, '#f2c230');
            } else {
              e.dead = true;
              this.progress = Math.max(0, this.progress - 1);
              this.combo = 0;
              const d = Math.hypot(p.x - e.x, p.y - e.y) || 1;
              p.vx = ((p.x - e.x) / d) * 380;
              p.vy = ((p.y - e.y) / d) * 380;
              this.burst(e.x, e.y, 12, PAINTS[e.a].c, 180, 0);
              this.popText(e.x, e.y - 24, 'Не тот цвет! −1', '#8a3b3b', 22);
              this.shake = Math.max(this.shake, 5);
              sfx.tone(200, 0.18, 'square', 0.06, 110);
            }
          }
          break;
        }
        case 'inkbub':
          e.y += e.vy * dt;
          e.x += Math.sin(e.t * 3 + e.seed) * 26 * dt;
          if (e.y < -30) e.dead = true;
          else this.enemyContact(e, 25, '#2a2420');
          break;
        // ---------- VIII. первый росток
        case 'sun':
          e.a += dt;
          e.y += Math.sin(e.a * 2.2) * 10 * dt;
          if (p.carry < 3 && this.touching(e, 8)) {
            p.carry++;
            this.collect(e, 15, '#f2a03a');
          }
          break;
        case 'sprout': {
          const g = Math.min(1, this.progress / (this.endless ? 24 : this.ch.goal));
          e.r = 24 + g * 18;
          e.y = this.gy - 18 - g * 50;
          e.a = Math.max(0, e.a - dt);
          if (p.carry > 0 && this.touching(e, 10) && this.state === 'play') {
            const n = p.carry;
            this.progress += n;
            e.hp = Math.min(5, e.hp + 1);
            this.addScore(30 * n, e.x, e.y - 30, '#5c9e3a');
            p.carry = 0;
            e.a = 1;
            this.burst(e.x, e.y, 16 + n * 6, '#f2a03a', 220, 1);
            this.burst(e.x, e.y, 10, '#6fb04e', 160, 4, 80);
            this.ring(e.x, e.y, 70, '#f2a03a');
            this.shake = 5 + n;
            sfx.bloom();
          }
          break;
        }
        case 'bug': {
          const sp = 42 + Math.min(40, t * 0.8);
          const tx = sprout ? sprout.x : this.W / 2;
          const dir = Math.sign(tx - e.x) || 1;
          e.vx = dir;
          e.x += dir * sp * dt;
          e.y = this.gy - 10 - Math.abs(Math.sin(e.t * 6)) * 2;
          if (sprout && Math.abs(e.x - sprout.x) < 16) this.biteSprout(e, sprout);
          else this.enemyContact(e, 20, '#6fb04e');
          break;
        }
        case 'beetle': {
          const tx = sprout ? sprout.x : this.W / 2;
          const ty = sprout ? sprout.y : this.gy - 30;
          const dx = tx - e.x, dy = ty - e.y;
          const d = Math.hypot(dx, dy) || 1;
          const sp = 80 + Math.min(40, t * 0.6);
          e.vx = (dx / d) * sp;
          e.vy = (dy / d) * sp + Math.sin(e.t * 5) * 30;
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          if (sprout && d < sprout.r + e.r - 6) this.biteSprout(e, sprout);
          else this.enemyContact(e, 30, '#3a3a5a');
          break;
        }
        // ---------- IX. семена ветра
        case 'seed': {
          e.vx *= 0.985;
          e.vy *= 0.985;
          e.vy += Math.sin(e.t * 1.5 + e.seed) * 10 * dt;
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          if (e.x < e.r) {
            e.x = e.r;
            e.vx = Math.abs(e.vx) * 0.7;
          }
          if (e.x > this.W - e.r) {
            e.x = this.W - e.r;
            e.vx = -Math.abs(e.vx) * 0.7;
          }
          if (e.y < 30) {
            e.y = 30;
            e.vy = Math.abs(e.vy) * 0.7;
          }
          if (e.y > this.gy - e.r) {
            e.y = this.gy - e.r;
            e.vy = -Math.abs(e.vy) * 0.7;
          }
          const dx = e.x - p.x, dy = e.y - p.y;
          const d = Math.hypot(dx, dy);
          const minD = e.r + p.r + 4;
          if (d < minD && d > 0.01 && this.state !== 'dying') {
            const nx = dx / d, ny = dy / d;
            e.x = p.x + nx * minD;
            e.y = p.y + ny * minD;
            const pv = p.vx * nx + p.vy * ny;
            const push = Math.max(140, pv * (p.dashT > 0 ? 1.5 : 1.15));
            e.vx = nx * push + p.vx * 0.15;
            e.vy = ny * push + p.vy * 0.15;
            if (e.a <= 0) {
              this.burst(e.x, e.y, 5, '#ffffff', 90, 1);
              sfx.tone(720, 0.05, 'triangle', 0.05);
              e.a = 0.25;
            }
          }
          e.a -= dt;
          if (nest && Math.hypot(e.x - nest.x, e.y - nest.y) < nest.r) {
            e.dead = true;
            this.progress++;
            this.addScore(80, nest.x, nest.y - 30, this.ch.colors.main);
            this.burst(nest.x, nest.y, 20, '#ffffff', 220, 1);
            this.ring(nest.x, nest.y, 60, this.ch.colors.accent);
            this.shake = 6;
            nest.a = 1;
            sfx.bloom();
            if (this.progress % 3 === 0 && (this.endless || this.progress < this.ch.goal)) this.moveNest(nest);
          }
          break;
        }
        case 'nest':
          e.a = Math.max(0, e.a - dt);
          break;
        case 'bolt':
          if (e.a > 0) {
            e.a -= dt;
            if (e.a <= 0) {
              e.b = 0.28;
              this.shake = Math.max(this.shake, 7);
              this.burst(e.x, this.gy - 4, 18, '#f7e36a', 260, 1, 200);
              sfx.tone(90, 0.3, 'sawtooth', 0.12, 40);
              sfx.noise(0.3, 0.3, 2500);
              for (const sd of this.ents) {
                if (sd.kind === 'seed' && !sd.dead && Math.abs(sd.x - e.x) < e.r + sd.r) {
                  sd.dead = true;
                  this.burst(sd.x, sd.y, 10, '#c8c0b0', 140, 0, -40);
                  this.popText(sd.x, sd.y - 20, 'Пых!', '#5a6fa8', 20);
                }
              }
            }
          } else {
            e.b -= dt;
            if (Math.abs(p.x - e.x) < e.r + p.r - 4) this.damage();
            if (e.b <= 0) e.dead = true;
          }
          break;
        case 'orb':
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          if (e.x < -40 || e.x > this.W + 40 || e.y < -40 || e.y > this.H + 40) e.dead = true;
          if (this.touching(e, -3)) {
            if (this.damage()) {
              e.dead = true;
            }
          }
          break;
      }
    }

    // compact
    let j = 0;
    for (let i = 0; i < this.ents.length; i++) if (!this.ents[i].dead) this.ents[j++] = this.ents[i];
    this.ents.length = j;

    if (this.endless) this.updateEndless();
    else if (this.state === 'play' && this.progress >= this.ch.goal) this.clearChapter();
  }

  /** Бесконечный режим: сердца за прогресс, новые волны Короля Теней */
  updateEndless() {
    if (this.state !== 'play') return;
    const p = this.p;
    if (this.progress >= this.nextHeartAt) {
      this.nextHeartAt += ENDLESS_HEART_EVERY;
      this.wave++;
      if (this.hearts < 5) {
        this.hearts++;
        this.popText(p.x, p.y - 40, '+1 ♥', '#d8433b', 30);
      } else {
        this.score += 200;
        this.popText(p.x, p.y - 40, 'Волна ' + (this.wave + 1) + '! +200', this.ch.colors.main, 26);
      }
      this.ring(p.x, p.y, 80, '#d8433b');
      sfx.bloom();
    }
    if (this.ch.id === 'star' && this.count('boss') === 0) {
      if (this.timers.boss === undefined) this.timers.boss = 2.5;
      if (this.timers.boss <= 0) {
        delete this.timers.boss;
        const side = Math.random() < 0.5 ? this.W * 0.2 : this.W * 0.8;
        this.spawn('boss', side, -60, 46, { hp: 6 });
        this.popText(this.W / 2, 120, 'Король Теней вернулся!', '#b58cff', 30);
        this.shake = 10;
        sfx.boom();
      }
    }
  }

  /** Грибная глава: новый хоровод из 5 грибов */
  newRing(first = false) {
    for (const e of this.ents) if (e.kind === 'shroom') e.dead = true;
    const R = Math.max(70, Math.min(120, this.W * 0.18, (this.gy - 130) * 0.4));
    let cx: number, cy: number;
    if (first) {
      cx = this.p.x + R + 40;
      cy = this.p.y;
    } else {
      const pos = this.randPos(R + 40);
      cx = pos.x;
      cy = pos.y;
    }
    cx = Math.max(R + 30, Math.min(this.W - R - 30, cx));
    cy = Math.max(R * 0.8 + 90, Math.min(this.gy - R * 0.8 - 30, cy));
    // по кругу или «звёздочкой» (номера вразброс)
    const pattern = first || Math.random() < 0.4 ? [0, 1, 2, 3, 4] : [0, 3, 1, 4, 2];
    const off = Math.random() * Math.PI * 2;
    const dir = Math.random() < 0.5 ? 1 : -1;
    for (let i = 0; i < 5; i++) {
      const a = off + dir * (i / 5) * Math.PI * 2;
      this.spawn('shroom', cx + Math.cos(a) * R, cy + Math.sin(a) * R * 0.8, 16, { a: pattern[i] });
    }
    this.ringCx = cx;
    this.ringCy = cy;
    this.ringR = R;
    this.seqNext = 0;
    this.ringMax = Math.max(7, 15 - this.progress * 1.2);
    this.ringT = this.ringMax;
    this.ring(cx, cy, R, this.ch.colors.main);
  }

  /** Садовая глава: вредитель добрался до ростка */
  biteSprout(e: Ent, sp: Ent) {
    e.dead = true;
    if (this.state !== 'play') return;
    sp.hp--;
    this.burst(sp.x, sp.y, 12, '#6fb04e', 180, 4, 120);
    this.popText(sp.x, sp.y - 40, 'Хрум! −листик', '#8a3b3b', 22);
    this.shake = Math.max(this.shake, 6);
    sfx.tone(240, 0.15, 'sawtooth', 0.07, 120);
    if (sp.hp <= 0) {
      sp.hp = 3;
      this.popText(sp.x, sp.y - 64, 'Росток без листьев!', '#c8433b', 24);
      this.damage(true);
    }
  }

  /** Грозовая глава: гнездо перелетает на другую сторону */
  moveNest(n: Ent) {
    this.burst(n.x, n.y, 14, '#d8c49a', 160, 0);
    n.b = n.b ? 0 : 1;
    n.x = n.b ? this.W - 70 : 70;
    this.ring(n.x, n.y, 60, this.ch.colors.accent);
    this.popText(n.x, n.y - 50, 'Гнездо перелетело!', this.ch.colors.main, 22);
  }

  /** returns true if enemy got killed by dash */
  enemyContact(e: Ent, pts: number, color: string) {
    const p = this.p;
    if (!this.touching(e, -2)) return false;
    if (p.dashT > 0) {
      e.dead = true;
      this.addScore(pts, e.x, e.y, color);
      this.burst(e.x, e.y, 22, color, 280, 1);
      this.burst(e.x, e.y, 10, '#2a2420', 220, 5);
      this.ring(e.x, e.y, 50, color);
      this.shake = 9;
      this.hitstop = 0.06;
      sfx.kill();
      return true;
    }
    if (this.damage()) {
      e.vx = -e.vx * 1.5;
      e.vy = -e.vy * 1.5;
      e.b = 0.8;
    }
    return false;
  }

  updateBoss(e: Ent, dt: number) {
    const p = this.p;
    const rage = 1 + (6 - e.hp) * 0.12 + this.wave * 0.1;
    e.a += dt * rage;
    const tx = this.W / 2 + Math.cos(e.a * 0.6) * this.W * 0.3;
    const ty = Math.max(130, this.H * 0.28) + Math.sin(e.a * 1.1) * Math.min(90, this.H * 0.12);
    e.x += (tx - e.x) * Math.min(1, dt * 2);
    e.y += (ty - e.y) * Math.min(1, dt * 2);
    e.b = Math.max(0, e.b - dt);
    if (this.state !== 'play') return;
    if (this.timers.attack <= 0) {
      const pat = Math.floor(Math.random() * 3);
      const sp = 150 + (6 - e.hp) * 12;
      if (pat === 0) {
        const n = 10 + (6 - e.hp) * 1;
        const off = Math.random() * 6;
        for (let i = 0; i < n; i++) {
          const a = off + (i / n) * Math.PI * 2;
          this.spawn('orb', e.x, e.y, 9, { vx: Math.cos(a) * sp, vy: Math.sin(a) * sp });
        }
      } else if (pat === 1) {
        const base = Math.atan2(p.y - e.y, p.x - e.x);
        for (let i = -2; i <= 2; i++) {
          this.spawn('orb', e.x, e.y, 9, { vx: Math.cos(base + i * 0.22) * sp * 1.3, vy: Math.sin(base + i * 0.22) * sp * 1.3 });
        }
      } else {
        for (let i = 0; i < 14; i++) {
          const a = i * 0.45;
          const s2 = sp * (0.6 + i * 0.05);
          this.spawn('orb', e.x, e.y, 8, { vx: Math.cos(a) * s2, vy: Math.sin(a) * s2 });
        }
      }
      this.ring(e.x, e.y, 70, '#2a2040');
      sfx.tone(180, 0.2, 'square', 0.05, 90);
      this.timers.attack = Math.max(this.endless ? 0.9 : 1.2, 2.6 - (6 - e.hp) * 0.22 - this.wave * 0.1);
    }
    // contact
    if (this.touching(e, -6)) {
      if (p.dashT > 0 && p.carry >= 3 && e.b <= 0) {
        e.hp--;
        e.b = 0.8;
        this.progress++;
        p.carry = 0;
        this.addScore(300, e.x, e.y - 40, '#b58cff');
        this.burst(e.x, e.y, 40, '#ffe89a', 360, 1);
        this.burst(e.x, e.y, 20, '#2a2040', 300, 5);
        this.ring(e.x, e.y, 110, '#b58cff');
        this.shake = 22;
        this.hitstop = 0.16;
        this.flash = 0.25;
        sfx.boom();
        const dx = p.x - e.x, dy = p.y - e.y, d = Math.hypot(dx, dy) || 1;
        p.vx = (dx / d) * 600;
        p.vy = (dy / d) * 600;
        p.dashT = 0;
        p.inv = 0.8;
        if (e.hp <= 0) {
          e.dead = true;
          for (let i = 0; i < 4; i++) this.burst(e.x, e.y, 30, i % 2 ? '#ffe89a' : '#b58cff', 420, 1);
        }
      } else if (p.dashT <= 0) {
        if (this.damage()) {
          const dx = p.x - e.x, dy = p.y - e.y, d = Math.hypot(dx, dy) || 1;
          p.vx = (dx / d) * 500;
          p.vy = (dy / d) * 500;
        }
      } else if (p.carry < 3 && e.b <= 0) {
        e.b = 0.5;
        this.popText(e.x, e.y - 60, 'Нужен заряд!', '#2a2420', 22);
        sfx.tone(150, 0.15, 'square', 0.06);
      }
    }
  }

  clearChapter() {
    this.state = 'clear';
    this.stateT = 2.2;
    for (const e of this.ents) {
      if (HAZARDS.has(e.kind) || e.kind === 'boss') {
        e.dead = true;
        this.burst(e.x, e.y, 8, this.ch.colors.wing, 150, 1);
      }
    }
    const timeBonus = Math.max(0, Math.floor((120 - this.chT) * 4));
    this.lastBonus = 500 + this.hearts * 100 + timeBonus;
    this.score += this.lastBonus;
    this.popText(this.W / 2, this.H / 2 - 20, 'Глава пройдена!', this.ch.colors.main, 46);
    this.popText(this.W / 2, this.H / 2 + 30, 'Бонус +' + this.lastBonus, '#2a2420', 28);
    for (let i = 0; i < 5; i++) this.burst(this.rand(0, this.W), this.rand(0, this.H * 0.6), 20, i % 2 ? this.ch.colors.main : this.ch.colors.accent, 260, i % 2 ? 4 : 1, 80);
    this.shake = 10;
    sfx.win();
  }
  lastBonus = 0;

  // ---------------- main update ----------------
  loop = (now: number) => {
    if (!this.running) return;
    const dt = Math.min(0.033, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    this.time += dt;
    S.setBoil(this.time);
    if (this.state !== 'paused') {
      if (this.state === 'idle') this.updateIdle(dt);
      else this.update(dt);
      this.updateParticles(dt);
    }
    this.render();
    this.raf = requestAnimationFrame(this.loop);
  };

  updateIdle(dt: number) {
    const p = this.p;
    const t = this.time;
    const tx = this.W / 2 + Math.cos(t * 0.7) * this.W * 0.3;
    const ty = this.H * 0.45 + Math.sin(t * 1.4) * this.H * 0.15;
    p.vx = (tx - p.x) * 3;
    p.facing = p.vx >= 0 ? 1 : -1;
    p.x += (tx - p.x) * Math.min(1, dt * 3);
    p.y += (ty - p.y) * Math.min(1, dt * 3);
    if (Math.random() < dt * 30) this.trailSpark();
    this.shake *= 0.9;
  }

  trailSpark() {
    const p = this.p;
    this.addParticle({ x: p.x - p.facing * 8 + this.rand(-4, 4), y: p.y + this.rand(-6, 6), vx: -p.vx * 0.1 + this.rand(-20, 20), vy: this.rand(-10, 30), life: 0.6, max: 0.6, size: 1.5 + Math.random() * 2.5, color: this.ch.colors.wing, kind: Math.random() < 0.3 ? 1 : 0, g: 20, rot: 0 });
  }

  update(dt: number) {
    if (this.hitstop > 0) {
      this.hitstop -= dt;
      return;
    }
    let sdt = dt;
    if (this.state === 'dying') {
      sdt *= 0.25;
      this.stateT -= dt;
      if (this.stateT <= 0) {
        this.state = 'over';
        this.ev.onGameOver(this.score, this.chIdx);
        return;
      }
    } else if (this.state === 'clear') {
      this.stateT -= dt;
      if (Math.random() < dt * 6) this.burst(this.rand(0, this.W), this.rand(0, this.H * 0.7), 14, Math.random() < 0.5 ? this.ch.colors.main : this.ch.colors.accent, 200, 1, 40);
      if (this.stateT <= 0) {
        this.state = 'idle';
        if (this.mode !== 'hard') this.hearts = Math.min(5, this.hearts + 1);
        this.ev.onChapterClear(this.chIdx, this.lastBonus, this.score);
        return;
      }
    } else if (this.state === 'over') {
      return;
    }
    this.chT += sdt;
    this.updatePlayer(sdt);
    this.updateChapter(sdt);
    if (this.comboT > 0) {
      this.comboT -= sdt;
      if (this.comboT <= 0) this.combo = 0;
    }
    this.shake = Math.max(0, this.shake - dt * 60);
    this.flash = Math.max(0, this.flash - dt);
  }

  updatePlayer(dt: number) {
    const p = this.p;
    let ix = 0, iy = 0;
    const canControl = this.state === 'play' || this.state === 'clear';
    if (canControl) {
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
    if (len > 0.1) {
      p.dx = ix / Math.max(len, 0.0001);
      p.dy = iy / Math.max(len, 0.0001);
    }
    if (this.dashQueued && p.dashCd <= 0 && this.state === 'play') {
      const dx = len > 0.1 ? p.dx : p.facing;
      const dy = len > 0.1 ? p.dy : 0;
      p.vx = dx * DASH_SPEED;
      p.vy = dy * DASH_SPEED;
      p.dashT = 0.17;
      p.dashCd = this.dashCdMax();
      this.shake = Math.max(this.shake, 3);
      this.ring(p.x, p.y, 36, this.ch.colors.wing);
      sfx.dash();
    }
    this.dashQueued = false;

    if (p.dashT > 0) {
      p.dashT -= dt;
      this.addParticle({ x: p.x, y: p.y, vx: 0, vy: 0, life: 0.25, max: 0.25, size: 14, color: this.ch.colors.main, kind: 0, g: 0, rot: 0 });
      if (Math.random() < 0.7) this.trailSpark();
    } else {
      let slow = 1;
      if (this.ch.id === 'mushroom') {
        for (const e of this.ents) {
          if (e.kind === 'spore' && Math.hypot(e.x - p.x, e.y - p.y) < e.r) {
            slow = 0.5;
            break;
          }
        }
      }
      const maxs = MAXS * (1 + 0.07 * this.upgrades.speed) * slow;
      const k = 1 - Math.exp(-dt * 14);
      p.vx += (ix * maxs - p.vx) * k;
      p.vy += (iy * maxs - p.vy) * k;
    }
    p.x += (p.vx + this.wind) * dt;
    p.y += p.vy * dt;
    const r = p.r + 4;
    if (p.x < r) { p.x = r; p.vx = Math.abs(p.vx) * 0.3; }
    if (p.x > this.W - r) { p.x = this.W - r; p.vx = -Math.abs(p.vx) * 0.3; }
    if (p.y < r + 10) { p.y = r + 10; p.vy = Math.abs(p.vy) * 0.3; }
    if (p.y > this.gy - r) { p.y = this.gy - r; p.vy = -Math.abs(p.vy) * 0.3; }
    if (Math.abs(ix) > 0.15) p.facing = ix > 0 ? 1 : -1;
    else if (p.dashT > 0 && Math.abs(p.vx) > 50) p.facing = p.vx > 0 ? 1 : -1;
    p.dashCd -= dt;
    p.inv -= dt;
    if (Math.hypot(p.vx, p.vy) > 60 && Math.random() < dt * 40) this.trailSpark();
    this.trail.unshift({ x: p.x, y: p.y });
    if (this.trail.length > 200) this.trail.pop();
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
      if (q.kind !== 3 && q.kind < 5) {
        q.vx *= 0.96;
        q.vy *= 0.96;
      }
      q.rot += dt * 4;
      ps[j++] = q;
    }
    ps.length = j;
    this.displayScore += (this.score - this.displayScore) * Math.min(1, dt * 10);
    if (Math.abs(this.score - this.displayScore) < 1) this.displayScore = this.score;
  }

  // ---------------- render ----------------
  render() {
    const ctx = this.ctx;
    const k = this.dpr * this.s;
    const sh = this.shake;
    const sx = sh > 0 ? (Math.random() - 0.5) * sh : 0;
    const sy = sh > 0 ? (Math.random() - 0.5) * sh : 0;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#e9e1cf';
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    ctx.drawImage(this.bg, sx * k, sy * k);
    ctx.setTransform(k, 0, 0, k, sx * k, sy * k);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    this.drawUnder(ctx);
    for (const e of this.ents) this.drawEnt(ctx, e);

    // followers (night)
    if (this.followers > 0) {
      for (let i = 0; i < this.followers; i++) {
        const tp = this.trail[Math.min(this.trail.length - 1, (i + 1) * 7)];
        if (tp) this.drawFirefly(ctx, tp.x + Math.sin(this.time * 5 + i) * 4, tp.y + Math.cos(this.time * 4 + i) * 4, i + 900);
      }
    }

    // player
    const p = this.p;
    const visible = this.state !== 'over' || this.stateT > 0;
    if (visible && !(p.inv > 0 && this.state === 'play' && Math.floor(this.time * 20) % 2 === 0)) {
      const glow = this.ch.id === 'star' && p.carry >= 3 ? 0.7 + Math.sin(this.time * 10) * 0.3 : 0;
      const squash = p.dashT > 0 ? 1.15 : 1;
      if (this.ch.id === 'rainbow') {
        ctx.globalAlpha = 0.35 + Math.sin(this.time * 6) * 0.1;
        ctx.fillStyle = PAINTS[this.paint].c;
        ctx.beginPath();
        ctx.arc(p.x, p.y, 24, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1;
      }
      drawFairy(ctx, p.x, p.y, this.time, this.ch, p.facing, 1.25 * squash, glow);
      if (this.shield > 0) {
        for (let i = 0; i < 6; i++) {
          const a = this.time * 3 + (i / 6) * Math.PI * 2;
          S.sEllipse(ctx, p.x + Math.cos(a) * 28, p.y + Math.sin(a) * 28, 6, 4, 700 + i, '#e86a92', 0.9);
        }
      }
    }

    this.drawParticles(ctx);

    // night darkness
    if (this.ch.id === 'night' && this.state !== 'idle') {
      const light = 130 + this.followers * 14;
      ctx.setTransform(k, 0, 0, k, 0, 0);
      const g = ctx.createRadialGradient(p.x, p.y, light * 0.35, p.x, p.y, light);
      g.addColorStop(0, 'rgba(14,12,34,0)');
      g.addColorStop(1, 'rgba(14,12,34,0.9)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, this.W, this.H);
      // glowing things on top of darkness
      ctx.globalCompositeOperation = 'lighter';
      for (const e of this.ents) {
        if (e.kind === 'firefly' || e.kind === 'lantern') {
          const rr = e.kind === 'lantern' ? 70 + e.a * 40 : 26;
          const gg = ctx.createRadialGradient(e.x, e.y, 0, e.x, e.y, rr);
          gg.addColorStop(0, 'rgba(255,230,120,0.55)');
          gg.addColorStop(1, 'rgba(255,230,120,0)');
          ctx.fillStyle = gg;
          ctx.fillRect(e.x - rr, e.y - rr, rr * 2, rr * 2);
        }
        if (e.kind === 'moth') {
          ctx.fillStyle = 'rgba(255,60,80,0.8)';
          ctx.beginPath();
          ctx.arc(e.x - 4, e.y - 3, 2, 0, 7);
          ctx.arc(e.x + 4, e.y - 3, 2, 0, 7);
          ctx.fill();
        }
      }
      ctx.globalCompositeOperation = 'source-over';
    }

    // damage flash
    if (this.flash > 0) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = `rgba(200,50,40,${this.flash * 0.5})`;
      ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    }

    ctx.setTransform(k, 0, 0, k, 0, 0);
    if (this.state !== 'idle') this.drawHud(ctx);
    if (this.touchMode && (this.state === 'play' || this.state === 'clear')) this.drawTouch(ctx);
  }

  /** Подложка под сущностями: таймер хоровода, подсказка к гнезду */
  drawUnder(ctx: Ctx) {
    if (this.ch.id === 'mushroom' && this.count('shroom') > 0) {
      const frac = Math.max(0, this.ringT / this.ringMax);
      ctx.setLineDash([4, 7]);
      ctx.strokeStyle = 'rgba(90,60,40,0.35)';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.ellipse(this.ringCx, this.ringCy, this.ringR, this.ringR * 0.8, 0, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      if (this.state === 'play') {
        ctx.strokeStyle = frac < 0.3 ? '#c8433b' : this.ch.colors.main;
        ctx.lineWidth = 4;
        ctx.globalAlpha = 0.7;
        ctx.beginPath();
        ctx.ellipse(this.ringCx, this.ringCy, this.ringR + 26, (this.ringR + 26) * 0.8, 0, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac);
        ctx.stroke();
        ctx.globalAlpha = 1;
      }
    }
    if (this.ch.id === 'storm' && this.chT < 7 && this.state === 'play') {
      const nest = this.ents.find((e) => e.kind === 'nest');
      let best: Ent | undefined;
      let bd = Infinity;
      for (const e of this.ents) {
        if (e.kind !== 'seed') continue;
        const d = Math.hypot(e.x - this.p.x, e.y - this.p.y);
        if (d < bd) {
          bd = d;
          best = e;
        }
      }
      if (nest && best) {
        ctx.setLineDash([6, 8]);
        ctx.strokeStyle = 'rgba(247,227,106,0.7)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(best.x, best.y);
        ctx.lineTo(nest.x, nest.y);
        ctx.stroke();
        ctx.setLineDash([]);
      }
    }
  }

  drawFirefly(ctx: Ctx, x: number, y: number, seed: number) {
    const fl = 0.6 + Math.sin(this.time * 8 + seed) * 0.4;
    ctx.fillStyle = `rgba(255,230,110,${0.35 * fl})`;
    ctx.beginPath();
    ctx.arc(x, y, 12, 0, 7);
    ctx.fill();
    S.sCircle(ctx, x, y, 4, seed, '#f5e27a', 1);
    S.sEllipse(ctx, x - 3, y - 5, 4, 2, seed + 1, null, 0.8);
    S.sEllipse(ctx, x + 3, y - 5, 4, 2, seed + 2, null, 0.8);
  }

  drawEnt(ctx: Ctx, e: Ent) {
    const t = this.time;
    switch (e.kind) {
      case 'pollen': {
        ctx.fillStyle = 'rgba(242,194,48,0.25)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, 14 + Math.sin(t * 5 + e.seed) * 2, 0, 7);
        ctx.fill();
        S.sCircle(ctx, e.x, e.y, 7, e.seed, '#f2c230', 1.3);
        for (let i = 0; i < 3; i++) {
          ctx.fillStyle = S.GRAPHITE_SOFT;
          ctx.fillRect(e.x - 3 + i * 2.5, e.y - 1 + (i % 2) * 2, 1.4, 1.4);
        }
        break;
      }
      case 'bud': {
        const gy = this.gy;
        S.sLine(ctx, e.x, e.y + 14, e.x + Math.sin(e.seed) * 10, gy, e.seed, 1.8, 'rgba(40,90,30,0.85)', 6);
        S.sEllipse(ctx, e.x + 10, (e.y + gy) / 2, 9, 4, e.seed + 2, '#6fb04e', 1.1);
        if (e.b === 0) {
          const pulse = 1 + Math.sin(t * 3 + e.seed) * 0.05;
          S.sPoly(ctx, [e.x - 13 * pulse, e.y + 8, e.x - 8, e.y - 14, e.x, e.y - 20 * pulse, e.x + 8, e.y - 14, e.x + 13 * pulse, e.y + 8], e.seed, true, '#e8a0b8', 1.5, 1);
          S.sPoly(ctx, [e.x - 13, e.y + 8, e.x, e.y + 14, e.x + 13, e.y + 8], e.seed + 5, false, '#6fb04e', 1.4, 1);
          for (let i = 0; i < 3; i++) {
            const a = -Math.PI / 2 + (i - 1) * 0.7;
            const filled = i < e.a;
            S.sCircle(ctx, e.x + Math.cos(a) * 32, e.y + Math.sin(a) * 32, 4, e.seed + 10 + i, filled ? '#f2c230' : null, 1);
          }
        } else {
          const open = Math.min(1, e.t * 3);
          const sc = 0.5 + open * 0.5 + (open < 1 ? 0 : Math.sin(t * 2 + e.seed) * 0.04);
          for (let i = 0; i < 7; i++) {
            const a = (i / 7) * Math.PI * 2 + t * 0.2;
            S.sEllipse(ctx, e.x + Math.cos(a) * 16 * sc, e.y + Math.sin(a) * 16 * sc, 11 * sc, 11 * sc, e.seed + i, '#e86a92', 1.2);
          }
          S.sCircle(ctx, e.x, e.y, 9 * sc, e.seed + 20, '#f2c230', 1.4);
        }
        break;
      }
      case 'wasp': {
        const f = e.vx >= 0 ? 1 : -1;
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.scale(f, 1);
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
        ctx.fillStyle = '#d8433b';
        ctx.beginPath();
        ctx.arc(16, -3, 1.5, 0, 7);
        ctx.fill();
        ctx.restore();
        break;
      }
      case 'drop': {
        const s = 1 + Math.sin(t * 4 + e.seed) * 0.06;
        S.sPoly(ctx, [e.x, e.y - 12 * s, e.x - 7, e.y + 1, e.x - 5, e.y + 7, e.x, e.y + 9, e.x + 5, e.y + 7, e.x + 7, e.y + 1], e.seed, true, '#5aa8e6', 1.3, 0.6);
        ctx.fillStyle = 'rgba(255,255,255,0.8)';
        ctx.fillRect(e.x - 3, e.y - 1, 2, 4);
        break;
      }
      case 'flame': {
        const r = e.r;
        const fl = Math.sin(t * 14 + e.seed) * 0.12;
        ctx.fillStyle = 'rgba(255,140,40,0.18)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, r * 1.6, 0, 7);
        ctx.fill();
        S.sPoly(ctx, [e.x, e.y - r * (1.6 + fl), e.x - r * 0.8, e.y - r * 0.1, e.x - r * 0.6, e.y + r * 0.7, e.x + r * 0.6, e.y + r * 0.7, e.x + r * 0.8, e.y - r * 0.1], e.seed, true, '#f08a2c', 1.5, 1.2);
        S.sPoly(ctx, [e.x, e.y - r * (0.8 - fl), e.x - r * 0.35, e.y + r * 0.2, e.x, e.y + r * 0.55, e.x + r * 0.35, e.y + r * 0.2], e.seed + 3, true, '#f7d060', 1, 0.8);
        break;
      }
      case 'spark':
        S.sCircle(ctx, e.x, e.y, 5, e.seed, '#f08a2c', 1.1);
        ctx.fillStyle = 'rgba(255,160,60,0.3)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, 9, 0, 7);
        ctx.fill();
        break;
      case 'firefly':
        this.drawFirefly(ctx, e.x, e.y, e.seed);
        break;
      case 'lantern': {
        const x = e.x, y = e.y;
        S.sLine(ctx, x, y - 30, x, y - 60, e.seed + 1, 1.3, 'rgba(230,220,255,0.7)');
        S.sPoly(ctx, [x - 16, y - 26, x + 16, y - 26, x + 20, y + 22, x - 20, y + 22], e.seed, true, '#f5e27a', 1.8, 1, 'rgba(240,230,255,0.9)');
        S.sPoly(ctx, [x - 22, y - 26, x + 22, y - 26], e.seed + 4, false, null, 2, 1, 'rgba(240,230,255,0.9)');
        S.sPoly(ctx, [x - 24, y + 22, x + 24, y + 22], e.seed + 5, false, null, 2, 1, 'rgba(240,230,255,0.9)');
        this.drawProgressText(ctx, x, y + 44, this.endless ? `${this.progress}` : `${this.progress}/${this.ch.goal}`, '#f5e27a');
        break;
      }
      case 'moth': {
        const wf = 0.5 + Math.abs(Math.sin(t * 12 + e.seed)) * 0.5;
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.save();
        ctx.scale(wf, 1);
        S.sEllipse(ctx, -14, -2, 14, 10, e.seed, '#3a3450', 1.2, 'rgba(10,8,20,0.8)');
        S.sEllipse(ctx, 14, -2, 14, 10, e.seed + 1, '#3a3450', 1.2, 'rgba(10,8,20,0.8)');
        ctx.restore();
        S.scribble(ctx, 0, 0, 7, e.seed, 12, 'rgba(10,8,20,0.9)', 1.6);
        ctx.restore();
        break;
      }
      case 'flake':
      case 'crystal': {
        const big = e.kind === 'crystal';
        const r = big ? 15 : 9;
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.rotate(e.a * 0.8);
        if (big) {
          ctx.fillStyle = 'rgba(120,200,240,0.25)';
          ctx.beginPath();
          ctx.arc(0, 0, r * 1.8, 0, 7);
          ctx.fill();
        }
        for (let i = 0; i < 6; i++) {
          const a = (i / 6) * Math.PI * 2;
          const cx = Math.cos(a), cy = Math.sin(a);
          S.sLine(ctx, 0, 0, cx * r, cy * r, e.seed + i, big ? 1.8 : 1.3, 'rgba(40,90,130,0.85)', 0.5);
          if (big) S.sLine(ctx, cx * r * 0.6, cy * r * 0.6, cx * r * 0.6 + Math.cos(a + 0.8) * 5, cy * r * 0.6 + Math.sin(a + 0.8) * 5, e.seed + i + 10, 1, 'rgba(40,90,130,0.8)', 0.3);
        }
        ctx.restore();
        break;
      }
      case 'icicle': {
        if (e.a > 0) {
          // warning
          const blink = Math.floor(t * 12) % 2 === 0;
          ctx.setLineDash([6, 8]);
          ctx.strokeStyle = 'rgba(200,60,50,0.35)';
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.moveTo(e.x, 30);
          ctx.lineTo(e.x, this.gy);
          ctx.stroke();
          ctx.setLineDash([]);
          if (blink) this.drawProgressText(ctx, e.x, 34, '!', '#c8433b', 30);
          S.sPoly(ctx, [e.x - 9, 0, e.x + 9, 0, e.x, 18 + (0.9 - e.a) * 20], e.seed, true, '#9ad8f0', 1.4, 0.6);
        } else {
          S.sPoly(ctx, [e.x - 9, e.y - 30, e.x + 9, e.y - 30, e.x, e.y + 12], e.seed, true, '#9ad8f0', 1.6, 0.6);
          S.sLine(ctx, e.x, e.y - 60, e.x, e.y - 34, e.seed + 1, 1, 'rgba(80,140,180,0.4)');
        }
        break;
      }
      case 'shard': {
        ctx.fillStyle = 'rgba(255,230,120,0.25)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, 16, 0, 7);
        ctx.fill();
        S.sPoly(ctx, S.starPts(e.x, e.y, 11, 4.5, 5, t * 1.5 + e.seed), e.seed, true, '#f7d060', 1.3, 0.5);
        break;
      }
      case 'boss': {
        const x = e.x, y = e.y;
        const hurt = e.b > 0 && Math.floor(t * 20) % 2 === 0;
        ctx.fillStyle = 'rgba(20,10,40,0.35)';
        ctx.beginPath();
        ctx.arc(x, y, 64 + Math.sin(t * 3) * 4, 0, 7);
        ctx.fill();
        S.sCircle(ctx, x, y, 46, e.seed, hurt ? '#b58cff' : '#2a2040', 2.2, 'rgba(10,6,20,0.9)');
        S.scribble(ctx, x, y, 44, e.seed + 1, 24, 'rgba(10,6,20,0.7)', 1.4);
        // tendrils
        for (let i = 0; i < 6; i++) {
          const a = Math.PI * 0.15 + (i / 5) * Math.PI * 0.7;
          const len = 30 + Math.sin(t * 4 + i) * 10;
          S.sLine(ctx, x + Math.cos(a) * 40, y + Math.sin(a) * 40, x + Math.cos(a) * (46 + len), y + Math.sin(a) * (46 + len), e.seed + 10 + i, 2, 'rgba(10,6,20,0.8)', 8);
        }
        // crown
        S.sPoly(ctx, [x - 26, y - 38, x - 22, y - 64, x - 10, y - 46, x, y - 70, x + 10, y - 46, x + 22, y - 64, x + 26, y - 38], e.seed + 20, true, '#8a6cc0', 1.6, 1);
        // eyes
        ctx.fillStyle = '#ffe89a';
        ctx.beginPath();
        ctx.ellipse(x - 14, y - 6, 7, 4, -0.3, 0, 7);
        ctx.ellipse(x + 14, y - 6, 7, 4, 0.3, 0, 7);
        ctx.fill();
        // hp bar
        const bw = 90;
        S.sPoly(ctx, [x - bw / 2, y + 60, x + bw / 2, y + 60, x + bw / 2, y + 70, x - bw / 2, y + 70], e.seed + 30, true, null, 1.2, 0.6, 'rgba(240,230,255,0.9)');
        ctx.fillStyle = '#b58cff';
        ctx.fillRect(x - bw / 2 + 2, y + 62, (bw - 4) * (e.hp / 6), 6);
        break;
      }
      // ---------- VI
      case 'shroom': {
        const lit = e.b === 1;
        const next = !lit && e.a === this.seqNext && this.state === 'play';
        const s = next ? 1 + Math.sin(t * 8) * 0.1 : 1;
        const x = e.x, y = e.y;
        if (lit) {
          ctx.fillStyle = 'rgba(247,208,96,0.35)';
          ctx.beginPath();
          ctx.arc(x, y - 4, 26, 0, Math.PI * 2);
          ctx.fill();
        }
        if (next) {
          ctx.strokeStyle = this.ch.colors.main;
          ctx.lineWidth = 2;
          ctx.globalAlpha = 0.5 + Math.sin(t * 8) * 0.3;
          ctx.beginPath();
          ctx.arc(x, y - 2, 26 * s, 0, Math.PI * 2);
          ctx.stroke();
          ctx.globalAlpha = 1;
        }
        S.sPoly(ctx, [x - 5, y + 14, x - 4, y, x + 4, y, x + 5, y + 14], e.seed, true, '#f3e6c8', 1.2, 0.6);
        S.sPoly(ctx, [x - 17 * s, y + 2, x - 12 * s, y - 10 * s, x, y - 15 * s, x + 12 * s, y - 10 * s, x + 17 * s, y + 2], e.seed + 3, true, lit ? '#f7d060' : '#d0503a', 1.5, 0.8);
        ctx.fillStyle = '#fff4dc';
        ctx.beginPath();
        ctx.arc(x - 9, y - 4, 1.8, 0, Math.PI * 2);
        ctx.arc(x + 10, y - 3, 1.6, 0, Math.PI * 2);
        ctx.fill();
        this.drawProgressText(ctx, x, y - 5, String(e.a + 1), lit ? '#6a4a10' : '#2a2420', 20);
        break;
      }
      case 'spider': {
        ctx.strokeStyle = 'rgba(60,50,50,0.5)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(e.x, 0);
        ctx.lineTo(e.x, e.y - 8);
        ctx.stroke();
        ctx.strokeStyle = 'rgba(40,30,30,0.85)';
        ctx.lineWidth = 1.4;
        ctx.beginPath();
        for (const side of [-1, 1]) {
          for (let i = 0; i < 4; i++) {
            const ly = e.y - 6 + i * 4;
            ctx.moveTo(e.x, e.y);
            ctx.lineTo(e.x + side * 10, ly - 5);
            ctx.lineTo(e.x + side * 16, ly + 4 + Math.sin(t * 10 + i) * 1.5);
          }
        }
        ctx.stroke();
        S.sCircle(ctx, e.x, e.y, 9, e.seed, '#3a3030', 1.5);
        ctx.fillStyle = '#d8433b';
        ctx.beginPath();
        ctx.arc(e.x - 3, e.y + 2, 1.6, 0, Math.PI * 2);
        ctx.arc(e.x + 3, e.y + 2, 1.6, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
      case 'spore': {
        ctx.fillStyle = 'rgba(150,140,90,0.16)';
        for (let i = 0; i < 6; i++) {
          const a = i * 1.05 + e.seed;
          ctx.beginPath();
          ctx.arc(e.x + Math.cos(a) * e.r * 0.35, e.y + Math.sin(a) * e.r * 0.3, e.r * 0.45, 0, Math.PI * 2);
          ctx.fill();
        }
        S.scribble(ctx, e.x, e.y, e.r * 0.8, e.seed, 9, 'rgba(110,100,60,0.4)', 1);
        break;
      }
      // ---------- VII
      case 'paint': {
        const c = PAINTS[e.a].c;
        if (this.paint === e.a) {
          ctx.fillStyle = c;
          ctx.globalAlpha = 0.25;
          ctx.beginPath();
          ctx.arc(e.x, e.y - 6, 30, 0, Math.PI * 2);
          ctx.fill();
          ctx.globalAlpha = 1;
        }
        S.sLine(ctx, e.x, this.gy + 4, e.x, e.y + 8, e.seed + 5, 1.6, 'rgba(40,90,30,0.85)', 2);
        S.sPoly(ctx, [e.x - 18, e.y - 8, e.x - 10, e.y + 10, e.x + 10, e.y + 10, e.x + 18, e.y - 8], e.seed, true, c, 1.5, 0.8);
        S.sEllipse(ctx, e.x, e.y - 8, 18, 5, e.seed + 2, c, 1.2);
        break;
      }
      case 'bubble': {
        if (e.a === -1) {
          S.sCircle(ctx, e.x, e.y, e.r, e.seed, null, 1.3);
          PAINTS.forEach((pc, i) => {
            ctx.strokeStyle = pc.c;
            ctx.lineWidth = 2.5;
            ctx.beginPath();
            ctx.arc(e.x, e.y, e.r - 3 - i * 3, Math.PI * 1.1 + t, Math.PI * 1.9 + t);
            ctx.stroke();
          });
        } else {
          S.sCircle(ctx, e.x, e.y, e.r, e.seed, PAINTS[e.a].c, 1.3);
        }
        ctx.strokeStyle = 'rgba(255,255,255,0.85)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r * 0.65, Math.PI * 1.15, Math.PI * 1.45);
        ctx.stroke();
        break;
      }
      case 'inkbub':
        S.sCircle(ctx, e.x, e.y, e.r, e.seed, '#2a2420', 1.6);
        S.scribble(ctx, e.x, e.y, e.r * 0.8, e.seed + 1, 10, 'rgba(20,16,24,0.8)', 1.2);
        ctx.fillStyle = '#f3ecdc';
        ctx.beginPath();
        ctx.arc(e.x - 5, e.y - 3, 2.5, 0, Math.PI * 2);
        ctx.arc(e.x + 5, e.y - 3, 2.5, 0, Math.PI * 2);
        ctx.fill();
        break;
      // ---------- VIII
      case 'sun': {
        ctx.fillStyle = 'rgba(242,160,58,0.25)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, 16, 0, Math.PI * 2);
        ctx.fill();
        for (let i = 0; i < 8; i++) {
          const a = (i / 8) * Math.PI * 2 + t;
          S.sLine(ctx, e.x + Math.cos(a) * 11, e.y + Math.sin(a) * 11, e.x + Math.cos(a) * 16, e.y + Math.sin(a) * 16, e.seed + i, 1.1, 'rgba(160,90,20,0.7)', 0.3);
        }
        S.sCircle(ctx, e.x, e.y, 8, e.seed, '#f2a03a', 1.3);
        break;
      }
      case 'sprout': {
        const g = Math.min(1, this.progress / (this.endless ? 24 : this.ch.goal));
        const base = this.gy;
        const top = base - 30 - g * 110;
        if (e.a > 0) {
          ctx.fillStyle = `rgba(242,160,58,${0.3 * e.a})`;
          ctx.beginPath();
          ctx.arc(e.x, e.y, e.r + 20, 0, Math.PI * 2);
          ctx.fill();
        }
        const sway = Math.sin(t * 1.3) * 3;
        S.sLine(ctx, e.x, base, e.x + sway, top, e.seed, 3 + g * 3, 'rgba(60,110,40,0.9)', 4);
        for (let i = 0; i < 5; i++) {
          const ly = base - 16 - i * ((base - top - 20) / 5);
          const side = i % 2 ? 1 : -1;
          const has = i < e.hp;
          S.sEllipse(ctx, e.x + sway * (i / 5) + side * 12, ly, 11, 5, e.seed + i, has ? '#6fb04e' : null, has ? 1.2 : 0.8, has ? S.GRAPHITE : 'rgba(40,36,32,0.25)');
        }
        if (g >= 1) {
          for (let i = 0; i < 6; i++) {
            const a = (i / 6) * Math.PI * 2 + t * 0.3;
            S.sEllipse(ctx, e.x + sway + Math.cos(a) * 10, top + Math.sin(a) * 10, 8, 8, e.seed + 20 + i, '#f7a8c4', 1);
          }
          S.sCircle(ctx, e.x + sway, top, 6, e.seed + 30, '#f2c230', 1.2);
        } else {
          S.sCircle(ctx, e.x + sway, top, 4 + g * 6, e.seed + 30, '#8cc063', 1.2);
        }
        break;
      }
      case 'bug': {
        const dir = e.vx >= 0 ? 1 : -1;
        for (let i = 3; i >= 0; i--) {
          S.sCircle(ctx, e.x - dir * i * 8, e.y - Math.abs(Math.sin(t * 8 + i)) * 3, 6.5 - i * 0.6, e.seed + i, i === 0 ? '#6fa040' : '#9ccf63', 1.1);
        }
        ctx.fillStyle = S.GRAPHITE;
        ctx.beginPath();
        ctx.arc(e.x + dir * 3, e.y - 2, 1.4, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
      case 'beetle': {
        const wf = 0.4 + Math.abs(Math.sin(t * 30)) * 0.6;
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.scale(1, wf);
        S.sEllipse(ctx, -6, -9, 8, 5, e.seed + 1, '#dfe6f0', 1);
        S.sEllipse(ctx, 6, -9, 8, 5, e.seed + 2, '#dfe6f0', 1);
        ctx.restore();
        S.sEllipse(ctx, e.x, e.y, 12, 9, e.seed, '#3a3a5a', 1.5);
        S.sLine(ctx, e.x, e.y - 9, e.x, e.y + 9, e.seed + 3, 1, 'rgba(230,230,255,0.6)', 0.5);
        break;
      }
      // ---------- IX
      case 'seed': {
        ctx.fillStyle = 'rgba(255,255,255,0.35)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r + 4, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = 'rgba(60,56,70,0.6)';
        ctx.lineWidth = 0.9;
        ctx.beginPath();
        for (let i = 0; i < 12; i++) {
          const a = (i / 12) * Math.PI * 2 + e.t * 0.4;
          ctx.moveTo(e.x, e.y);
          ctx.lineTo(e.x + Math.cos(a) * e.r, e.y + Math.sin(a) * e.r);
        }
        ctx.stroke();
        ctx.fillStyle = '#ffffff';
        for (let i = 0; i < 12; i++) {
          const a = (i / 12) * Math.PI * 2 + e.t * 0.4;
          ctx.beginPath();
          ctx.arc(e.x + Math.cos(a) * e.r, e.y + Math.sin(a) * e.r, 2, 0, Math.PI * 2);
          ctx.fill();
        }
        S.sCircle(ctx, e.x, e.y, 2.5, e.seed, '#8a6a4a', 0.8);
        break;
      }
      case 'nest': {
        const x = e.x, y = e.y;
        if (e.a > 0) {
          ctx.fillStyle = `rgba(247,227,106,${0.4 * e.a})`;
          ctx.beginPath();
          ctx.arc(x, y, 50, 0, Math.PI * 2);
          ctx.fill();
        }
        S.sPoly(ctx, [x - 38, y - 6, x - 30, y + 18, x + 30, y + 18, x + 38, y - 6], e.seed, true, '#b08a5a', 1.8, 1);
        for (let i = -3; i <= 3; i++) S.sLine(ctx, x + i * 9 - 4, y - 4, x + i * 8 + 4, y + 16, e.seed + i, 0.9, 'rgba(60,40,20,0.5)', 1);
        S.sEllipse(ctx, x, y - 6, 38, 8, e.seed + 9, '#d8b888', 1.5);
        if (this.chT < 7 || e.a > 0) this.drawProgressText(ctx, x, y - 34, 'Гнездо', '#f7e36a', 22);
        break;
      }
      case 'bolt': {
        if (e.a > 0) {
          const k = 1 - e.a / 1.1;
          ctx.fillStyle = `rgba(255,245,180,${0.12 + 0.25 * k})`;
          ctx.fillRect(e.x - e.r, 0, e.r * 2, this.gy);
          ctx.setLineDash([5, 7]);
          ctx.strokeStyle = 'rgba(247,227,106,0.6)';
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.moveTo(e.x - e.r, 0);
          ctx.lineTo(e.x - e.r, this.gy);
          ctx.moveTo(e.x + e.r, 0);
          ctx.lineTo(e.x + e.r, this.gy);
          ctx.stroke();
          ctx.setLineDash([]);
          if (Math.floor(t * 10) % 2 === 0) this.drawProgressText(ctx, e.x, 34, '⚡', '#f7e36a', 28);
        } else {
          const pts: number[] = [];
          for (let y = 0; y <= this.gy; y += 36) pts.push(e.x + (y === 0 ? 0 : (Math.random() - 0.5) * 28), y);
          pts.push(e.x, this.gy);
          ctx.lineJoin = 'miter';
          [
            [10, 'rgba(255,255,255,0.45)'],
            [3.5, '#f7e36a'],
          ].forEach(([w, c]) => {
            ctx.strokeStyle = c as string;
            ctx.lineWidth = w as number;
            ctx.beginPath();
            for (let i = 0; i < pts.length; i += 2) {
              if (i === 0) ctx.moveTo(pts[i], pts[i + 1]);
              else ctx.lineTo(pts[i], pts[i + 1]);
            }
            ctx.stroke();
          });
          ctx.lineJoin = 'round';
          ctx.fillStyle = 'rgba(255,250,200,0.35)';
          ctx.fillRect(e.x - e.r, 0, e.r * 2, this.gy);
        }
        break;
      }
      case 'orb': {
        ctx.fillStyle = 'rgba(80,40,120,0.25)';
        ctx.beginPath();
        ctx.arc(e.x, e.y, e.r + 5, 0, 7);
        ctx.fill();
        S.sCircle(ctx, e.x, e.y, e.r, e.seed, '#4a2d70', 1.4, 'rgba(10,6,20,0.9)');
        break;
      }
    }
  }

  drawProgressText(ctx: Ctx, x: number, y: number, text: string, color: string, size = 22, align: CanvasTextAlign = 'center') {
    ctx.font = `700 ${size}px Caveat, cursive`;
    ctx.textAlign = align;
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 4;
    ctx.strokeStyle = 'rgba(243,236,220,0.85)';
    ctx.strokeText(text, x, y);
    ctx.fillStyle = color;
    ctx.fillText(text, x, y);
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
        case 2: {
          const r = q.size * (1.15 - a * 0.85);
          ctx.globalAlpha = a * 0.9;
          S.sCircle(ctx, q.x, q.y, r, q.x + q.y, null, 2, q.color);
          break;
        }
        case 3:
          ctx.globalAlpha = Math.min(1, a * 2);
          this.drawProgressText(ctx, q.x, q.y, q.text || '', q.color, q.size * (a > 0.85 ? 1 + (a - 0.85) * 3 : 1));
          break;
        case 4:
          ctx.save();
          ctx.translate(q.x, q.y);
          ctx.rotate(q.rot);
          ctx.fillStyle = q.color;
          ctx.beginPath();
          ctx.ellipse(0, 0, q.size * 1.8, q.size, 0, 0, 7);
          ctx.fill();
          ctx.strokeStyle = S.GRAPHITE_SOFT;
          ctx.lineWidth = 0.8;
          ctx.stroke();
          ctx.restore();
          break;
        case 6:
          ctx.strokeStyle = q.color;
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(q.x, q.y);
          ctx.lineTo(q.x - q.vx * 0.03, q.y - q.vy * 0.03);
          ctx.stroke();
          break;
        case 5: {
          ctx.strokeStyle = q.color;
          ctx.lineWidth = 1.2;
          const len = q.size;
          const d = Math.sign(q.vx) || 1;
          ctx.beginPath();
          ctx.moveTo(q.x, q.y);
          ctx.lineTo(q.x - d * len, q.y + (q.vy === 0 ? 0 : -q.vy * 0.05));
          ctx.stroke();
          break;
        }
      }
    }
    ctx.globalAlpha = 1;
  }

  drawHud(ctx: Ctx) {
    const pad = 16;
    // hearts
    const slots = Math.max(this.maxStartHearts(), this.hearts);
    const modeLabel: Record<GameMode, string> = { story: '', chapter: 'Одна глава', endless: '∞ Бесконечная охота', hard: 'Одно перо ×2' };
    if (modeLabel[this.mode]) {
      this.drawProgressText(ctx, pad, this.H - 22, modeLabel[this.mode], this.mode === 'hard' ? '#c8433b' : this.ch.colors.main, 22, 'left');
    }
    for (let i = 0; i < slots; i++) {
      const x = pad + 16 + i * 32;
      const y = pad + 16;
      const full = i < this.hearts;
      const bob = full && this.hearts === 1 ? Math.sin(this.time * 10) * 2 : 0;
      ctx.beginPath();
      S.heartPath(ctx, x, y + bob, 24, 70 + i);
      if (full) {
        ctx.fillStyle = S.hatch(ctx, '#d8433b');
        ctx.fill();
      }
      ctx.strokeStyle = S.GRAPHITE;
      ctx.lineWidth = 1.6;
      ctx.stroke();
    }
    if (this.shield > 0) {
      const sx = pad + 16 + slots * 32;
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2 + this.time;
        S.sEllipse(ctx, sx + Math.cos(a) * 6, pad + 16 + Math.sin(a) * 6, 5, 3.5, 720 + i, '#e86a92', 0.8);
      }
    }
    // score
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.font = '700 30px Caveat, cursive';
    ctx.fillStyle = this.isDark() ? '#f3ecdc' : '#2a2420';
    const light = this.isDark();
    ctx.fillText('Очки: ' + Math.round(this.displayScore), pad, pad + 52);
    if (this.combo >= 2) {
      const mult = Math.min(5, 1 + Math.floor(this.combo / 5));
      ctx.font = '700 22px Caveat, cursive';
      ctx.fillStyle = this.ch.colors.main;
      ctx.fillText(`Серия ${this.combo}  ×${mult}`, pad, pad + 80);
      // combo timer line
      ctx.strokeStyle = this.ch.colors.main;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(pad, pad + 94);
      ctx.lineTo(pad + 110 * (this.comboT / 2.4), pad + 94);
      ctx.stroke();
    }

    // quest progress (center top)
    const cx = this.W / 2;
    const txt = this.endless
      ? `${this.ch.goalLabel}: ${this.progress}  ·  до ♥ ${this.nextHeartAt - this.progress}`
      : `${this.ch.goalLabel}: ${Math.min(this.progress, this.ch.goal)} / ${this.ch.goal}`;
    this.drawProgressText(ctx, cx, pad + 14, txt, light ? '#f5e27a' : '#2a2420', 28);
    const bw = Math.min(220, this.W * 0.4);
    const bx = cx - bw / 2, by = pad + 34;
    S.sPoly(ctx, [bx, by, bx + bw, by, bx + bw, by + 10, bx, by + 10], 99, true, null, 1.3, 0.6, light ? 'rgba(240,230,255,0.9)' : S.GRAPHITE);
    const frac = this.endless
      ? 1 - (this.nextHeartAt - this.progress) / ENDLESS_HEART_EVERY
      : this.progress / this.ch.goal;
    const fillW = (bw - 4) * Math.max(0, Math.min(1, frac));
    if (fillW > 0) {
      ctx.fillStyle = S.hatch(ctx, this.ch.colors.main, 1.5);
      ctx.fillRect(bx + 2, by + 2, fillW, 6);
    }
    // carry indicator
    const carryMax: Record<string, number> = { flower: 6, water: 5, star: 3, garden: 3 };
    const carryCol: Record<string, string> = { flower: '#f2c230', water: '#5aa8e6', star: '#f7d060', garden: '#f2a03a' };
    const carryLabel: Record<string, string> = { flower: 'Пыльца', water: 'Вода', star: 'Заряд', garden: 'Солнце' };
    const cm = carryMax[this.ch.id];
    if (cm) {
      const col = carryCol[this.ch.id];
      const label = carryLabel[this.ch.id];
      this.drawProgressText(ctx, cx - (cm * 16) / 2 - 36, by + 30, label, light ? '#f3ecdc' : '#2a2420', 20);
      for (let i = 0; i < cm; i++) {
        S.sCircle(ctx, cx - (cm * 16) / 2 + 8 + i * 18, by + 30, 6, 200 + i, i < this.p.carry ? col : null, 1.2, light ? 'rgba(240,230,255,0.9)' : S.GRAPHITE);
      }
    }
    if (this.ch.id === 'night' && this.followers > 0) {
      this.drawProgressText(ctx, cx, by + 30, `За тобой: ${this.followers} ✦`, '#f5e27a', 22);
    }
    if (this.ch.id === 'mushroom' && this.state === 'play') {
      const secs = Math.max(0, Math.ceil(this.ringT));
      const warn = this.ringT < this.ringMax * 0.3;
      this.drawProgressText(ctx, cx, by + 30, `Хоровод: ${this.seqNext}/5 · ${secs} с`, warn ? '#c8433b' : light ? '#f3ecdc' : '#2a2420', 22);
    }
    if (this.ch.id === 'rainbow') {
      this.drawProgressText(ctx, cx - 14, by + 30, 'Цвет:', light ? '#f3ecdc' : '#2a2420', 22);
      S.sCircle(ctx, cx + 26, by + 30, 8, 250, PAINTS[this.paint].c, 1.4);
    }
    // dash cooldown ring around player
    const p = this.p;
    if (p.dashCd > 0 && this.state === 'play') {
      ctx.strokeStyle = this.ch.colors.main;
      ctx.globalAlpha = 0.6;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(p.x, p.y, 26, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (1 - p.dashCd / this.dashCdMax()));
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
  }

  drawTouch(ctx: Ctx) {
    const b = this.dashBtn();
    const ready = this.p.dashCd <= 0;
    const light = this.isDark();
    const stroke = light ? 'rgba(240,230,255,0.8)' : S.GRAPHITE;
    ctx.globalAlpha = 0.75;
    S.sCircle(ctx, b.x, b.y, b.r * (this.dashBtnId >= 0 ? 0.92 : 1), 555, ready ? this.ch.colors.wing : null, 2, stroke);
    this.drawProgressText(ctx, b.x, b.y, 'Рывок', light ? '#f3ecdc' : '#2a2420', 24);
    if (this.joy.active) {
      S.sCircle(ctx, this.joy.ox, this.joy.oy, 50, 556, null, 1.6, stroke);
      const dx = this.joy.x - this.joy.ox, dy = this.joy.y - this.joy.oy;
      const d = Math.hypot(dx, dy);
      const m = Math.min(d, 50) / (d || 1);
      S.sCircle(ctx, this.joy.ox + dx * m, this.joy.oy + dy * m, 20, 557, this.ch.colors.main, 1.6, stroke);
    } else if (this.chT < 6) {
      this.drawProgressText(ctx, this.W * 0.3, this.H - 90, 'Веди пальцем, чтобы лететь', light ? '#f3ecdc' : '#2a2420', 22);
    }
    ctx.globalAlpha = 1;
  }
}
