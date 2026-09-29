// Часть IV. «Выше облаков»: фея подпрыгивает на облаках и листьях всё выше.
// Гравитация, отскок, взмах крыльями в воздухе, топтание ос сверху, небо меняется с высотой.
import { Arcade, type ArcadeEvents, type Ctx } from './base';
import { CHAPTERS } from '../game/chapters';
import * as S from '../game/sketch';
import { sfx } from '../game/audio';

type PKind = 'cloud' | 'leaf' | 'dry' | 'spring';
interface Plat {
  x: number;
  y: number;
  w: number;
  kind: PKind;
  vx: number;
  broken: number;
  squash: number;
  seed: number;
}
interface Item {
  x: number;
  y: number;
  kind: 'dew' | 'star' | 'heart';
  seed: number;
  dead: boolean;
}
interface Foe {
  x: number;
  y: number;
  vx: number;
  kind: 'wasp' | 'ink';
  t: number;
  seed: number;
  dead: boolean;
}

const G = 1500;
const JUMP = 780;
const SPRING = 1280;
const FEET = 18;

const ZONES = [
  { at: 0, name: 'Луг', top: [205, 232, 255, 0.35], bot: [225, 245, 215, 0.3] },
  { at: 600, name: 'Облака', top: [180, 215, 250, 0.45], bot: [230, 240, 255, 0.35] },
  { at: 1500, name: 'Закат', top: [250, 170, 150, 0.45], bot: [255, 220, 170, 0.4] },
  { at: 2600, name: 'Звёздная высь', top: [40, 30, 90, 0.75], bot: [110, 70, 140, 0.6] },
  { at: 4000, name: 'Лунная дорога', top: [15, 12, 45, 0.85], bot: [60, 40, 110, 0.75] },
];

export class JumperGame extends Arcade {
  vx = 0;
  vy = 0;
  startY = 0;
  maxH = 0;
  plats: Plat[] = [];
  items: Item[] = [];
  foes: Foe[] = [];
  topY = 0;
  rescue = 0;
  zone = 0;
  squash = 0;
  fw = 560;

  constructor(canvas: HTMLCanvasElement, ev: ArcadeEvents) {
    super(canvas, ev, CHAPTERS[6]);
    this.dashCdMax = 1.8;
    this.dashDur = 0.25;
    this.dashLabel = 'Взмах';
    this.hint = 'Веди пальцем влево-вправо';
    this.boot();
  }

  stat() {
    return this.maxH;
  }
  get fx0() {
    return (this.W - this.fw) / 2;
  }
  onResize() {
    this.fw = Math.min(this.W, 560);
  }
  drawBackground(_g: Ctx) {
    /* только бумага: небо рисуется динамически */
  }

  heightM() {
    return Math.max(0, Math.floor((this.startY - this.hy) / 10));
  }

  // ---------------- мир
  build() {
    this.fw = Math.min(this.W, 560);
    this.startY = this.H - 60;
    this.hx = this.W / 2;
    this.hy = this.startY - FEET - 2;
    this.vx = 0;
    this.vy = -JUMP;
    this.camY = 0;
    this.maxH = 0;
    this.zone = 0;
    this.plats = [];
    this.items = [];
    this.foes = [];
    this.rescue = 0;
    // широкая стартовая травка
    this.plats.push({ x: this.W / 2, y: this.startY, w: this.fw * 0.9, kind: 'cloud', vx: 0, broken: 0, squash: 0, seed: 1 });
    this.topY = this.startY;
    this.generate();
  }
  reset() {
    this.build();
  }
  idleReset() {
    this.build();
  }
  onRevive() {
    this.foes = this.foes.filter((f) => Math.abs(f.y - this.hy) > 260);
    this.hy = this.camY + this.H - 60;
    this.vy = -SPRING;
    this.rescue = 1.2;
  }

  generate() {
    while (this.topY > this.camY - 260) {
      const h = (this.startY - this.topY) / 10;
      const gap = Math.min(158, 72 + h * 0.025 + Math.random() * 40);
      this.topY -= gap;
      const w = Math.max(56, 96 - h * 0.012) + Math.random() * 24;
      const x = this.fx0 + w / 2 + Math.random() * (this.fw - w);
      const r = Math.random();
      let kind: PKind = 'cloud';
      if (h > 60 && r < 0.07) kind = 'spring';
      else if (h > 150 && r < Math.min(0.32, 0.1 + h * 0.00008)) kind = 'dry';
      else if (h > 80 && r < Math.min(0.55, 0.3 + h * 0.0001)) kind = 'leaf';
      const vx = kind === 'leaf' ? (Math.random() < 0.5 ? -1 : 1) * (40 + Math.min(90, h * 0.03)) : 0;
      this.plats.push({ x, y: this.topY, w, kind, vx, broken: 0, squash: 0, seed: this.seedC++ * 1.618 });
      if (Math.random() < 0.3) this.items.push({ x: x + this.rand(-w / 3, w / 3), y: this.topY - 34, kind: 'dew', seed: this.seedC++ * 1.618, dead: false });
      else if (Math.random() < 0.04) this.items.push({ x, y: this.topY - 46, kind: 'star', seed: this.seedC++ * 1.618, dead: false });
      else if (Math.random() < 0.012 && this.state === 'play') this.items.push({ x, y: this.topY - 40, kind: 'heart', seed: this.seedC++ * 1.618, dead: false });
      if (h > 70 && Math.random() < Math.min(0.2, 0.05 + h * 0.00005)) {
        const ink = h > 150 && Math.random() < 0.4;
        this.foes.push({ x: ink ? this.fx0 + this.rand(40, this.fw - 40) : this.fx0 + (Math.random() < 0.5 ? 20 : this.fw - 20), y: this.topY - this.rand(50, 80), vx: ink ? 0 : (Math.random() < 0.5 ? 1 : -1) * (70 + Math.min(90, h * 0.03)), kind: ink ? 'ink' : 'wasp', t: 0, seed: this.seedC++ * 1.618, dead: false });
      }
    }
  }

  onDash() {
    this.vy = Math.min(this.vy, -660);
    this.burst(this.hx, this.hy + 10, 14, this.ch.colors.wing, 200, 4, 200);
  }

  physics(dt: number, control: boolean) {
    const inp = this.input();
    const tx = (control ? inp.x : 0) * 360;
    this.vx += (tx - this.vx) * Math.min(1, dt * 10);
    if (Math.abs(inp.x) > 0.15 && control) this.facing = inp.x > 0 ? 1 : -1;
    const prevFeet = this.hy + FEET;
    this.vy += G * dt;
    this.hx += this.vx * dt;
    this.hy += this.vy * dt;
    // заворачиваем по краям поля
    if (this.hx < this.fx0) this.hx += this.fw;
    if (this.hx > this.fx0 + this.fw) this.hx -= this.fw;
    this.squash = Math.max(0, this.squash - dt * 4);
    for (const p of this.plats) {
      if (p.kind === 'leaf') {
        p.x += p.vx * dt;
        if (p.x - p.w / 2 < this.fx0 || p.x + p.w / 2 > this.fx0 + this.fw) p.vx = -p.vx;
      }
      p.squash = Math.max(0, p.squash - dt * 4);
      if (p.broken > 0) {
        p.broken += dt;
        p.y += 260 * dt * p.broken * 3;
      }
    }
    // приземление только при падении
    if (this.vy > 0 && this.state !== 'dying') {
      const feet = this.hy + FEET;
      for (const p of this.plats) {
        if (p.broken > 0) continue;
        if (prevFeet <= p.y + 2 && feet >= p.y && Math.abs(this.hx - p.x) < p.w / 2 + 6) {
          this.hy = p.y - FEET;
          this.vy = p.kind === 'spring' ? -SPRING : -JUMP;
          p.squash = 1;
          this.squash = 1;
          this.burst(this.hx, p.y, 6, p.kind === 'spring' ? '#d0503a' : '#ffffff', 120, 0, 100);
          if (p.kind === 'spring') {
            this.ring(this.hx, p.y, 40, '#d0503a');
            this.shake = Math.max(this.shake, 4);
            sfx.tone(300, 0.25, 'sine', 0.1, 900);
          } else sfx.tone(440 + Math.min(400, this.heightM() * 0.1), 0.07, 'triangle', 0.06);
          if (p.kind === 'dry') {
            p.broken = 0.01;
            this.burst(p.x, p.y, 12, '#c89a50', 160, 4, 300);
            sfx.crash();
          }
          break;
        }
      }
    }
    if (Math.random() < dt * 20) this.trailSpark();
  }

  idleStep(dt: number) {
    this.physics(dt, false);
    if (this.hy > this.startY + 50) {
      this.hy = this.startY - FEET;
      this.vy = -JUMP;
    }
  }

  step(dt: number) {
    const playing = this.state === 'play';
    this.tryDash();
    this.physics(dt, playing);
    this.rescue = Math.max(0, this.rescue - dt);

    // камера только вверх
    const target = this.hy - this.H * 0.42;
    if (target < this.camY) this.camY += (target - this.camY) * Math.min(1, dt * 8);

    // высота = очки
    const h = this.heightM();
    if (h > this.maxH && playing) {
      this.score += h - this.maxH;
      this.maxH = h;
      let z = 0;
      for (let i = 0; i < ZONES.length; i++) if (h >= ZONES[i].at) z = i;
      if (z !== this.zone) {
        this.zone = z;
        this.dark = z >= 3;
        this.popText(this.W / 2 + this.camX, this.camY + this.H * 0.3, ZONES[z].name + '!', this.ch.colors.main, 40);
        this.addScore(100 * z, this.hx, this.hy - 30, this.ch.colors.accent, false);
        this.ring(this.hx, this.hy, 90, this.ch.colors.main);
        sfx.bloom();
      }
    }
    this.generate();

    // предметы
    for (const it of this.items) {
      if (it.dead || !playing) continue;
      if (Math.hypot(it.x - this.hx, it.y - this.hy) < 26) {
        it.dead = true;
        if (it.kind === 'dew') {
          this.addScore(10, it.x, it.y, '#3a8fd6');
          this.burst(it.x, it.y, 10, '#9fd3f5', 160, 1);
          sfx.pickup(this.combo);
        } else if (it.kind === 'star') {
          this.addScore(60, it.x, it.y, '#e0a526');
          this.burst(it.x, it.y, 18, '#f7d060', 220, 1);
          this.ring(it.x, it.y, 40, '#f7d060');
          sfx.bloom();
        } else {
          this.hearts = Math.min(this.maxHearts, this.hearts + 1);
          this.popText(it.x, it.y - 20, '+1 ♥', '#d8433b', 28);
          this.burst(it.x, it.y, 16, '#d8433b', 200, 1);
          sfx.bloom();
        }
      }
    }

    // враги
    for (const f of this.foes) {
      if (f.dead) continue;
      f.t += dt;
      if (f.kind === 'wasp') {
        f.x += f.vx * dt;
        if (f.x < this.fx0 + 16 || f.x > this.fx0 + this.fw - 16) f.vx = -f.vx;
      }
      if (!playing) continue;
      const d = Math.hypot(f.x - this.hx, f.y - this.hy);
      if (d < 26) {
        if (this.vy > 0 && this.hy < f.y - 4) {
          // топчем сверху
          f.dead = true;
          this.vy = -JUMP * 0.95;
          this.addScore(40, f.x, f.y, f.kind === 'wasp' ? '#e0a526' : '#2a2420');
          this.burst(f.x, f.y, 18, f.kind === 'wasp' ? '#f2c230' : '#2a2420', 240, 1);
          this.ring(f.x, f.y, 44, this.ch.colors.main);
          this.shake = 8;
          this.hitstop = 0.05;
          sfx.kill();
        } else if (this.hurt()) {
          this.vy = Math.max(this.vy, 120);
          this.vx = (this.hx < f.x ? -1 : 1) * 300;
        }
      }
    }

    // чистим то, что ушло вниз
    const bottom = this.camY + this.H + 120;
    this.plats = this.plats.filter((p) => p.y < bottom && p.broken < 1.5);
    this.items = this.items.filter((i) => !i.dead && i.y < bottom);
    this.foes = this.foes.filter((f) => !f.dead && f.y < bottom);

    // падение вниз
    if (playing && this.hy - this.camY > this.H + 30) {
      this.inv = 0;
      this.dashT = 0;
      this.shield = 0;
      this.hurt(true);
      if (this.state === 'play') {
        this.hy = this.camY + this.H - 20;
        this.vy = -SPRING * 1.05;
        this.rescue = 1.4;
        this.popText(this.hx, this.hy - 60, 'Пузырёк спас!', '#3a8fd6', 26);
      }
    }
  }

  // ---------------- рисование
  drawScreenUnder(ctx: Ctx) {
    const h = this.heightM();
    let z = 0;
    for (let i = 0; i < ZONES.length; i++) if (h >= ZONES[i].at) z = i;
    const a = ZONES[z], b = ZONES[Math.min(ZONES.length - 1, z + 1)];
    const k = b === a ? 0 : Math.min(1, Math.max(0, (h - a.at) / (b.at - a.at)));
    const mix = (u: number[], v: number[]) => `rgba(${u.map((x, i) => (i < 3 ? Math.round(x + (v[i] - x) * k) : (x + (v[i] - x) * k).toFixed(2))).join(',')})`;
    const g = ctx.createLinearGradient(0, 0, 0, this.H);
    g.addColorStop(0, mix(a.top, b.top));
    g.addColorStop(1, mix(a.bot, b.bot));
    ctx.fillStyle = g;
    ctx.fillRect(-20, -20, this.W + 40, this.H + 40);
    // звёзды в выси
    if (h > 2000) {
      ctx.globalAlpha = Math.min(1, (h - 2000) / 800);
      for (let i = 0; i < 50; i++) {
        const x = S.hash(i + 3) * this.W;
        const y = (((S.hash(i + 77) * this.H * 2 - this.camY * 0.05) % this.H) + this.H) % this.H;
        ctx.fillStyle = '#fff8d0';
        ctx.fillRect(x, y, 2, 2);
      }
      ctx.globalAlpha = 1;
    }
    // далёкие облака (параллакс)
    const soft = this.dark ? 'rgba(230,220,255,0.35)' : 'rgba(38,34,32,0.3)';
    for (let i = 0; i < 6; i++) {
      const span = this.H + 200;
      const cy = ((((S.hash(i + 11) * span - this.camY * 0.25) % span) + span) % span) - 100;
      const cx = S.hash(i + 21) * this.W;
      for (let q = 0; q < 3; q++) S.sCircle(ctx, cx + q * 24, cy + (q % 2) * -8, 16 + (q % 2) * 6, 520 + i * 7 + q, null, 1.1, soft);
    }
    // границы поля
    if (this.W > this.fw + 20) {
      ctx.setLineDash([6, 10]);
      ctx.strokeStyle = soft;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(this.fx0, 0);
      ctx.lineTo(this.fx0, this.H);
      ctx.moveTo(this.fx0 + this.fw, 0);
      ctx.lineTo(this.fx0 + this.fw, this.H);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  drawWorld(ctx: Ctx) {
    // стартовый луг
    if (this.camY > -this.H) {
      const gy = this.startY + 8;
      S.sPoly(ctx, [-10, gy, this.W + 10, gy, this.W + 10, gy + 200, -10, gy + 200], 600, true, '#7fbf5a', 1.8, 1.5);
    }
    for (const p of this.plats) this.drawPlat(ctx, p);
    for (const it of this.items) {
      if (it.dead) continue;
      const bob = Math.sin(this.time * 4 + it.seed) * 3;
      if (it.kind === 'dew') {
        S.sPoly(ctx, [it.x, it.y - 12 + bob, it.x - 7, it.y + 1 + bob, it.x - 5, it.y + 7 + bob, it.x, it.y + 9 + bob, it.x + 5, it.y + 7 + bob, it.x + 7, it.y + 1 + bob], it.seed, true, '#5aa8e6', 1.3, 0.6);
      } else if (it.kind === 'star') {
        ctx.fillStyle = 'rgba(255,230,120,0.3)';
        ctx.beginPath();
        ctx.arc(it.x, it.y + bob, 18, 0, Math.PI * 2);
        ctx.fill();
        S.sPoly(ctx, S.starPts(it.x, it.y + bob, 12, 5, 5, this.time), it.seed, true, '#f7d060', 1.3, 0.5);
      } else {
        ctx.beginPath();
        S.heartPath(ctx, it.x, it.y + bob, 24, it.seed);
        ctx.fillStyle = S.hatch(ctx, '#d8433b');
        ctx.fill();
        ctx.strokeStyle = S.GRAPHITE;
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
    }
    for (const f of this.foes) this.drawFoe(ctx, f);
    if (this.rescue > 0) {
      ctx.strokeStyle = 'rgba(90,168,230,0.8)';
      ctx.fillStyle = 'rgba(200,235,255,0.35)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(this.hx, this.hy, 30, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
    const sq = 1 + this.squash * 0.12;
    ctx.save();
    ctx.translate(this.hx, this.hy + FEET);
    ctx.scale(sq, 1 / sq);
    ctx.translate(-this.hx, -this.hy - FEET);
    this.drawHero(ctx, 1.2);
    ctx.restore();
    // «призрак» у противоположного края при заворачивании
    if (this.hx - this.fx0 < 20 || this.fx0 + this.fw - this.hx < 20) {
      ctx.globalAlpha = 0.4;
      const ox = this.hx;
      this.hx += this.hx - this.fx0 < 20 ? this.fw : -this.fw;
      this.drawHero(ctx, 1.2);
      this.hx = ox;
      ctx.globalAlpha = 1;
    }
  }

  drawPlat(ctx: Ctx, p: Plat) {
    const sq = p.squash;
    const y = p.y + sq * 4;
    const hw = p.w / 2;
    if (p.kind === 'cloud') {
      const n = Math.max(3, Math.round(p.w / 26));
      for (let i = 0; i < n; i++) {
        const cx = p.x - hw + 12 + (i * (p.w - 24)) / Math.max(1, n - 1);
        S.sCircle(ctx, cx, y + 4 - (i % 2) * 4, 12 + (i % 2) * 3, p.seed + i, '#ffffff', 1.3);
      }
    } else if (p.kind === 'leaf' || p.kind === 'dry') {
      const col = p.kind === 'leaf' ? '#6fb04e' : '#c89a50';
      ctx.save();
      if (p.broken > 0) {
        ctx.globalAlpha = Math.max(0, 1 - p.broken);
        ctx.translate(p.x, y);
        ctx.rotate(p.broken * 2);
        ctx.translate(-p.x, -y);
      }
      S.sPoly(ctx, [p.x - hw, y, p.x - hw * 0.5, y - 9, p.x + hw * 0.5, y - 9, p.x + hw, y, p.x + hw * 0.5, y + 8, p.x - hw * 0.5, y + 8], p.seed, true, col, 1.5, 1);
      S.sLine(ctx, p.x - hw + 4, y, p.x + hw - 4, y, p.seed + 3, 1, 'rgba(40,60,20,0.6)', 1);
      if (p.kind === 'dry') {
        S.sLine(ctx, p.x - 6, y - 7, p.x + 3, y + 6, p.seed + 5, 0.9, 'rgba(90,50,20,0.7)', 1);
        S.sLine(ctx, p.x + 10, y - 6, p.x + 5, y + 6, p.seed + 6, 0.9, 'rgba(90,50,20,0.7)', 1);
      }
      ctx.restore();
    } else {
      // гриб-батут
      S.sPoly(ctx, [p.x - 6, y + 16, p.x - 5, y + 2, p.x + 5, y + 2, p.x + 6, y + 16], p.seed, true, '#f3e6c8', 1.2, 0.6);
      const s = 1 + sq * 0.25;
      S.sPoly(ctx, [p.x - hw * 0.6 * s, y + 3, p.x - hw * 0.4 * s, y - 10 / s, p.x, y - 14 / s, p.x + hw * 0.4 * s, y - 10 / s, p.x + hw * 0.6 * s, y + 3], p.seed + 2, true, '#d0503a', 1.5, 0.8);
      ctx.fillStyle = '#fff4dc';
      ctx.beginPath();
      ctx.arc(p.x - 8, y - 5, 2, 0, Math.PI * 2);
      ctx.arc(p.x + 9, y - 4, 1.8, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  drawFoe(ctx: Ctx, f: Foe) {
    if (f.kind === 'wasp') {
      const dir = f.vx >= 0 ? 1 : -1;
      ctx.save();
      ctx.translate(f.x, f.y);
      ctx.scale(dir, 1);
      const wf = 0.4 + Math.abs(Math.sin(this.time * 40)) * 0.6;
      ctx.save();
      ctx.scale(1, wf);
      S.sEllipse(ctx, -2, -12, 8, 6, f.seed + 1, 'rgba(200,220,240,1)', 1);
      ctx.restore();
      S.sEllipse(ctx, 0, 0, 14, 8, f.seed, '#f2c230', 1.6);
      S.sLine(ctx, -4, -7, -4, 7, f.seed + 2, 2.5, 'rgba(30,26,24,0.85)', 1);
      S.sLine(ctx, 3, -7, 3, 7, f.seed + 3, 2.5, 'rgba(30,26,24,0.85)', 1);
      S.sPoly(ctx, [-13, -2, -21, 0, -13, 3], f.seed + 4, true, '#2a2420', 1.2, 0.5);
      S.sCircle(ctx, 14, -2, 5, f.seed + 5, '#3a3430', 1.2);
      ctx.restore();
    } else {
      const y = f.y + Math.sin(f.t * 2 + f.seed) * 6;
      ctx.fillStyle = 'rgba(20,16,24,0.85)';
      ctx.beginPath();
      S.ellipsePath(ctx, f.x, y, 18, 18, f.seed, 0, 0.35);
      ctx.fill();
      S.scribble(ctx, f.x, y, 20, f.seed, 10, 'rgba(20,16,24,0.8)', 1.2);
      ctx.fillStyle = '#f3ecdc';
      ctx.beginPath();
      ctx.arc(f.x - 6, y - 3, 3, 0, Math.PI * 2);
      ctx.arc(f.x + 6, y - 3, 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  drawHudExtra(ctx: Ctx) {
    const cx = this.W / 2;
    const ink = this.dark ? '#f3ecdc' : '#2a2420';
    this.text(ctx, cx, 30, `Высота: ${this.heightM()} м`, ink, 28);
    const next = ZONES.find((z) => z.at > this.maxH);
    if (next) this.text(ctx, cx, 58, `до «${next.name}»: ${next.at - this.maxH} м`, this.ch.colors.main, 20);
    if (this.playT < 6) this.text(ctx, cx, 84, 'Прыгай выше! Ос можно топтать сверху', ink, 20);
  }
}
