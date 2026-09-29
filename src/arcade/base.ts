// Общая основа для частей III–V: цикл, ввод (клавиатура + плавающий джойстик + кнопка),
// частицы, тряска, стоп-кадр, сердца/щит, очки с серией, HUD, тач-управление.
import type { ChapterDef } from '../game/chapters';
import * as S from '../game/sketch';
import { drawFairy, drawScene } from '../game/draw';
import { sfx } from '../game/audio';

export type Ctx = CanvasRenderingContext2D;

export interface ArcadeEvents {
  onGameOver: (score: number, stat: number) => void;
}

export interface Part {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  max: number;
  size: number;
  color: string;
  kind: number; // 0 точка, 1 искра, 2 кольцо, 3 текст, 4 лепесток, 5 штрих
  g: number;
  rot: number;
  text?: string;
}

export type AState = 'idle' | 'play' | 'paused' | 'dying' | 'over';

export abstract class Arcade {
  canvas: HTMLCanvasElement;
  ctx: Ctx;
  ev: ArcadeEvents;
  ch: ChapterDef;
  W = 960;
  H = 540;
  s = 1;
  dpr = 1;
  bg = document.createElement('canvas');
  state: AState = 'idle';
  stateT = 0;
  time = 0;
  playT = 0;
  score = 0;
  displayScore = 0;
  hearts = 3;
  maxHearts = 5;
  shield = 0;
  combo = 0;
  comboT = 0;
  comboWindow = 2;
  parts: Part[] = [];
  shake = 0;
  hitstop = 0;
  flash = 0;
  inv = 0;
  dashT = 0;
  dashCd = 0;
  dashCdMax = 1;
  dashDur = 0.25;
  dashLabel = 'Рывок';
  hint = 'Веди пальцем, чтобы лететь';
  /** светлый HUD на тёмном фоне */
  dark = false;
  /** смещение камеры (мировые координаты верхнего левого угла экрана) */
  camX = 0;
  camY = 0;
  hx = 0;
  hy = 0;
  facing = 1;
  keys = new Set<string>();
  dashQueued = false;
  touchMode = false;
  joy = { id: -1, ox: 0, oy: 0, x: 0, y: 0, active: false };
  dashBtnId = -1;
  raf = 0;
  last = 0;
  running = true;
  seedC = 1;

  constructor(canvas: HTMLCanvasElement, ev: ArcadeEvents, ch: ChapterDef) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d')!;
    this.ev = ev;
    this.ch = ch;
  }

  /** вызывается наследником в конце конструктора */
  boot() {
    this.resize();
    window.addEventListener('resize', this.resize);
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    window.addEventListener('blur', this.onBlur);
    this.canvas.addEventListener('pointerdown', this.onPointerDown);
    window.addEventListener('pointermove', this.onPointerMove);
    window.addEventListener('pointerup', this.onPointerUp);
    window.addEventListener('pointercancel', this.onPointerUp);
    this.idleReset();
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

  // ---------------- хуки наследников
  abstract reset(): void;
  abstract step(dt: number): void;
  abstract drawWorld(ctx: Ctx): void;
  idleReset() {}
  idleStep(_dt: number) {}
  onRevive() {}
  onHurt() {}
  onDash(_dx: number, _dy: number) {}
  onResize() {}
  stat(): number {
    return 0;
  }
  drawBackground(g: Ctx) {
    drawScene(g, this.ch, this.W, this.H, 46);
  }
  /** рисование в экранных координатах под миром (небо и т.п.) */
  drawScreenUnder(_ctx: Ctx) {}
  /** рисование в экранных координатах поверх мира, под HUD (темнота и т.п.) */
  drawScreenOver(_ctx: Ctx) {}
  drawHudExtra(_ctx: Ctx) {}

  // ---------------- размеры и фон
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
    this.onResize();
  };

  buildBg() {
    const c = this.bg;
    c.width = this.canvas.width;
    c.height = this.canvas.height;
    const g = c.getContext('2d')!;
    g.fillStyle = '#f3ecdc';
    g.fillRect(0, 0, c.width, c.height);
    g.fillStyle = g.createPattern(S.paperNoise(), 'repeat')!;
    g.fillRect(0, 0, c.width, c.height);
    g.setTransform(this.dpr * this.s, 0, 0, this.dpr * this.s, 0, 0);
    this.drawBackground(g);
    g.setTransform(1, 0, 0, 1, 0, 0);
    const vg = g.createRadialGradient(c.width / 2, c.height / 2, Math.min(c.width, c.height) * 0.35, c.width / 2, c.height / 2, Math.max(c.width, c.height) * 0.75);
    vg.addColorStop(0, 'rgba(90,70,40,0)');
    vg.addColorStop(1, 'rgba(90,70,40,0.28)');
    g.fillStyle = vg;
    g.fillRect(0, 0, c.width, c.height);
  }

  // ---------------- жизненный цикл
  start() {
    sfx.init();
    this.score = 0;
    this.displayScore = 0;
    this.hearts = 3;
    this.shield = 0;
    this.combo = 0;
    this.comboT = 0;
    this.parts = [];
    this.shake = 0;
    this.hitstop = 0;
    this.flash = 0;
    this.inv = 1;
    this.dashT = 0;
    this.dashCd = 0;
    this.playT = 0;
    this.camX = 0;
    this.camY = 0;
    this.keys.clear();
    this.dashQueued = false;
    this.reset();
    this.state = 'play';
    this.burst(this.hx, this.hy, 24, this.ch.colors.wing, 220, 1);
    this.ring(this.hx, this.hy, 60, this.ch.colors.main);
  }

  /** второй шанс после рекламы с вознаграждением */
  revive() {
    this.hearts = 3;
    this.inv = 2.5;
    this.flash = 0;
    this.hitstop = 0;
    this.shake = 0;
    this.dashT = 0;
    this.dashQueued = false;
    this.keys.clear();
    this.onRevive();
    this.state = 'play';
    this.last = performance.now();
    this.burst(this.hx, this.hy, 40, this.ch.colors.wing, 300, 1);
    this.ring(this.hx, this.hy, 120, this.ch.colors.main);
    this.popText(this.hx, this.hy - 40, 'Второй шанс!', this.ch.colors.main, 32);
    sfx.bloom();
  }

  pause() {
    if (this.state === 'play') this.state = 'paused';
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
    this.parts = [];
    this.camX = 0;
    this.camY = 0;
    this.idleReset();
  }

  // ---------------- ввод
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
    const p = this.w(e);
    const b = this.dashBtn();
    if (Math.hypot(p.x - b.x, p.y - b.y) < b.r + 25) {
      this.dashQueued = true;
      this.dashBtnId = e.pointerId;
      return;
    }
    if (!this.joy.active) this.joy = { id: e.pointerId, ox: p.x, oy: p.y, x: p.x, y: p.y, active: true };
    else this.dashQueued = true;
  };
  onPointerMove = (e: PointerEvent) => {
    if (this.joy.active && e.pointerId === this.joy.id) {
      const p = this.w(e);
      this.joy.x = p.x;
      this.joy.y = p.y;
      const dx = p.x - this.joy.ox, dy = p.y - this.joy.oy;
      const d = Math.hypot(dx, dy);
      if (d > 70) {
        this.joy.ox = p.x - (dx / d) * 70;
        this.joy.oy = p.y - (dy / d) * 70;
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

  /** направление ввода, длина 0..1 */
  input() {
    let x = 0, y = 0;
    if (this.state === 'play') {
      const k = this.keys;
      if (k.has('ArrowLeft') || k.has('KeyA')) x -= 1;
      if (k.has('ArrowRight') || k.has('KeyD')) x += 1;
      if (k.has('ArrowUp') || k.has('KeyW')) y -= 1;
      if (k.has('ArrowDown') || k.has('KeyS')) y += 1;
      if (this.joy.active) {
        const dx = this.joy.x - this.joy.ox, dy = this.joy.y - this.joy.oy;
        const d = Math.hypot(dx, dy);
        if (d > 6) {
          const m = Math.min(1, d / 50);
          x = (dx / d) * m;
          y = (dy / d) * m;
        }
      }
    }
    let len = Math.hypot(x, y);
    if (len > 1) {
      x /= len;
      y /= len;
      len = 1;
    }
    return { x, y, len };
  }

  /** обработать нажатие рывка; true — рывок начался */
  tryDash(): boolean {
    const q = this.dashQueued;
    this.dashQueued = false;
    if (!q || this.dashCd > 0 || this.state !== 'play') return false;
    const inp = this.input();
    const dx = inp.len > 0.1 ? inp.x / inp.len : this.facing;
    const dy = inp.len > 0.1 ? inp.y / inp.len : 0;
    this.dashT = this.dashDur;
    this.dashCd = this.dashCdMax;
    this.shake = Math.max(this.shake, 3);
    this.ring(this.hx, this.hy, 36, this.ch.colors.wing);
    sfx.dash();
    this.onDash(dx, dy);
    return true;
  }

  // ---------------- урон и очки
  hurt(force = false): boolean {
    if ((!force && (this.inv > 0 || this.dashT > 0)) || this.state !== 'play') return false;
    if (this.shield > 0) {
      this.shield = 0;
      this.inv = 1;
      this.shake = 10;
      this.hitstop = 0.06;
      this.burst(this.hx, this.hy, 24, '#e86a92', 240, 4, 120);
      this.ring(this.hx, this.hy, 70, '#e86a92');
      this.popText(this.hx, this.hy - 30, 'Щит!', '#e86a92', 26);
      sfx.crash();
      return true;
    }
    this.hearts--;
    this.inv = 1.5;
    this.shake = 16;
    this.hitstop = 0.1;
    this.flash = 0.35;
    this.combo = 0;
    this.burst(this.hx, this.hy, 26, '#d8433b', 260, 0, 200);
    this.burst(this.hx, this.hy, 10, '#2a2420', 200, 5);
    sfx.hit();
    this.onHurt();
    if (this.hearts <= 0) {
      this.state = 'dying';
      this.stateT = 1.1;
      this.shake = 24;
      this.burst(this.hx, this.hy, 50, this.ch.colors.wing, 320, 1);
      sfx.over();
    }
    return true;
  }

  mult() {
    return Math.min(5, 1 + Math.floor(this.combo / 6));
  }
  addScore(pts: number, x: number, y: number, color: string, combo = true) {
    if (combo) {
      this.combo++;
      this.comboT = this.comboWindow;
    }
    const m = combo ? this.mult() : 1;
    const v = Math.round(pts * m);
    this.score += v;
    this.popText(x, y - 14, '+' + v + (m > 1 ? ' ×' + m : ''), color, 17 + m * 2);
    return v;
  }

  rand(a: number, b: number) {
    return a + Math.random() * (b - a);
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
    this.addParticle({ x, y, vx: 0, vy: -60, life: 0.9, max: 0.9, size, color, kind: 3, g: 0, rot: 0, text });
  }
  trailSpark(color = this.ch.colors.wing) {
    this.addParticle({ x: this.hx - this.facing * 8 + this.rand(-4, 4), y: this.hy + this.rand(-6, 6), vx: this.rand(-20, 20), vy: this.rand(-10, 30), life: 0.6, max: 0.6, size: 1.5 + Math.random() * 2.5, color, kind: Math.random() < 0.3 ? 1 : 0, g: 20, rot: 0 });
  }

  text(ctx: Ctx, x: number, y: number, s: string, color: string, size = 22, align: CanvasTextAlign = 'center') {
    ctx.font = `700 ${size}px Caveat, cursive`;
    ctx.textAlign = align;
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 4;
    ctx.strokeStyle = this.dark && color !== '#2a2420' ? 'rgba(20,16,40,0.75)' : 'rgba(243,236,220,0.85)';
    ctx.strokeText(s, x, y);
    ctx.fillStyle = color;
    ctx.fillText(s, x, y);
  }

  // ---------------- цикл
  loop = (now: number) => {
    if (!this.running) return;
    const dt = Math.min(0.033, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    this.time += dt;
    S.setBoil(this.time);
    if (this.state !== 'paused') {
      if (this.state === 'idle') {
        this.idleStep(dt);
        this.shake *= 0.9;
      } else this.update(dt);
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
    if (this.state === 'over') return;
    let sdt = dt;
    if (this.state === 'dying') {
      sdt *= 0.25;
      this.stateT -= dt;
      if (this.stateT <= 0) {
        this.state = 'over';
        this.ev.onGameOver(Math.floor(this.score), this.stat());
        return;
      }
    }
    this.playT += sdt;
    this.inv -= sdt;
    this.dashT -= sdt;
    this.dashCd -= sdt;
    if (this.comboT > 0) {
      this.comboT -= sdt;
      if (this.comboT <= 0) this.combo = 0;
    }
    this.step(sdt);
    this.shake = Math.max(0, this.shake - dt * 60);
    this.flash = Math.max(0, this.flash - dt);
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
    if (Math.abs(this.score - this.displayScore) < 1) this.displayScore = this.score;
  }

  // ---------------- рендер
  render() {
    const ctx = this.ctx;
    const k = this.dpr * this.s;
    const sh = this.shake;
    const sx = sh > 0 ? (Math.random() - 0.5) * sh : 0;
    const sy = sh > 0 ? (Math.random() - 0.5) * sh : 0;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(this.bg, 0, 0);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.setTransform(k, 0, 0, k, sx * k, sy * k);
    this.drawScreenUnder(ctx);
    ctx.setTransform(k, 0, 0, k, (sx - this.camX) * k, (sy - this.camY) * k);
    this.drawWorld(ctx);
    this.drawParticles(ctx);
    ctx.setTransform(k, 0, 0, k, sx * k, sy * k);
    this.drawScreenOver(ctx);
    if (this.flash > 0) {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = `rgba(200,50,40,${this.flash * 0.5})`;
      ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    }
    ctx.setTransform(k, 0, 0, k, 0, 0);
    if (this.state !== 'idle') this.drawHud(ctx);
    if (this.touchMode && this.state === 'play') this.drawTouch(ctx);
  }

  /** фея-героиня (мигает при неуязвимости) */
  drawHero(ctx: Ctx, scale = 1.25, glow = 0) {
    if (this.state === 'over') return;
    if (this.inv > 0 && this.state === 'play' && Math.floor(this.time * 20) % 2 === 0) return;
    drawFairy(ctx, this.hx, this.hy, this.time, this.ch, this.facing, scale * (this.dashT > 0 ? 1.12 : 1), glow);
    if (this.shield > 0) {
      for (let i = 0; i < 6; i++) {
        const a = this.time * 3 + (i / 6) * Math.PI * 2;
        S.sEllipse(ctx, this.hx + Math.cos(a) * 28, this.hy + Math.sin(a) * 28, 6, 4, 700 + i, '#e86a92', 0.9);
      }
    }
  }

  drawParticles(ctx: Ctx) {
    for (const q of this.parts) {
      const a = Math.max(0, q.life / q.max);
      ctx.globalAlpha = a;
      switch (q.kind) {
        case 0:
          ctx.fillStyle = q.color;
          ctx.beginPath();
          ctx.arc(q.x, q.y, q.size * (0.4 + a * 0.6), 0, Math.PI * 2);
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
          ctx.ellipse(0, 0, q.size * 1.8, q.size, 0, 0, Math.PI * 2);
          ctx.fill();
          ctx.restore();
          break;
        case 5: {
          ctx.strokeStyle = q.color;
          ctx.lineWidth = 1.2;
          const len = Math.hypot(q.vx, q.vy) || 1;
          ctx.beginPath();
          ctx.moveTo(q.x, q.y);
          ctx.lineTo(q.x - (q.vx / len) * q.size, q.y - (q.vy / len) * q.size);
          ctx.stroke();
          break;
        }
      }
    }
    ctx.globalAlpha = 1;
  }

  drawHud(ctx: Ctx) {
    const pad = 16;
    const ink = this.dark ? '#f3ecdc' : '#2a2420';
    const stroke = this.dark ? 'rgba(240,230,255,0.9)' : S.GRAPHITE;
    const slots = Math.max(3, this.hearts);
    for (let i = 0; i < slots; i++) {
      const x = pad + 16 + i * 32, y = pad + 16;
      const full = i < this.hearts;
      const bob = full && this.hearts === 1 ? Math.sin(this.time * 10) * 2 : 0;
      ctx.beginPath();
      S.heartPath(ctx, x, y + bob, 24, 70 + i);
      if (full) {
        ctx.fillStyle = S.hatch(ctx, '#d8433b');
        ctx.fill();
      }
      ctx.strokeStyle = stroke;
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
    this.text(ctx, pad, pad + 52, 'Очки: ' + Math.round(this.displayScore), ink, 30, 'left');
    if (this.combo >= 3) {
      const m = this.mult();
      this.text(ctx, pad, pad + 80, `Серия ${this.combo}  ×${m}`, this.ch.colors.main, 22, 'left');
      ctx.strokeStyle = this.ch.colors.main;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(pad, pad + 94);
      ctx.lineTo(pad + 110 * Math.max(0, this.comboT / this.comboWindow), pad + 94);
      ctx.stroke();
    }
    // кольцо перезарядки рывка
    if (this.dashCd > 0 && this.state === 'play') {
      ctx.strokeStyle = this.ch.colors.main;
      ctx.globalAlpha = 0.6;
      ctx.lineWidth = 2;
      ctx.beginPath();
      const px = this.hx - this.camX, py = this.hy - this.camY;
      ctx.arc(px, py, 26, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (1 - this.dashCd / this.dashCdMax));
      ctx.stroke();
      ctx.globalAlpha = 1;
    }
    this.drawHudExtra(ctx);
  }

  drawTouch(ctx: Ctx) {
    const b = this.dashBtn();
    const stroke = this.dark ? 'rgba(240,230,255,0.8)' : S.GRAPHITE;
    const ink = this.dark ? '#f3ecdc' : '#2a2420';
    ctx.globalAlpha = 0.75;
    S.sCircle(ctx, b.x, b.y, b.r * (this.dashBtnId >= 0 ? 0.92 : 1), 555, this.dashCd <= 0 ? this.ch.colors.wing : null, 2, stroke);
    this.text(ctx, b.x, b.y, this.dashLabel, ink, 22);
    if (this.joy.active) {
      S.sCircle(ctx, this.joy.ox, this.joy.oy, 50, 556, null, 1.6, stroke);
      const dx = this.joy.x - this.joy.ox, dy = this.joy.y - this.joy.oy;
      const d = Math.hypot(dx, dy);
      const m = Math.min(d, 50) / (d || 1);
      S.sCircle(ctx, this.joy.ox + dx * m, this.joy.oy + dy * m, 20, 557, this.ch.colors.main, 1.6, stroke);
    } else if (this.playT < 5) {
      this.text(ctx, this.W * 0.3, this.H - 90, this.hint, ink, 22);
    }
    ctx.globalAlpha = 1;
  }
}
