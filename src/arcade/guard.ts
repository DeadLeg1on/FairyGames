// Часть V. «Звёздная стража»: фея сама стреляет звёздной пыльцой, на неё идут волны
// чернильных существ, каждая 5-я волна — Чернильный Кракен. Вспышка сжигает вражеские снаряды.
import { Arcade, type ArcadeEvents, type Ctx } from './base';
import { CHAPTERS } from '../game/chapters';
import * as S from '../game/sketch';
import { sfx } from '../game/audio';

type EKind = 'blot' | 'moth' | 'eye' | 'boss';
interface Enemy {
  kind: EKind;
  x: number;
  y: number;
  vx: number;
  vy: number;
  hp: number;
  maxHp: number;
  r: number;
  t: number;
  seed: number;
  fireT: number;
  hit: number;
  ty: number;
  dead: boolean;
}
interface Shot {
  x: number;
  y: number;
  vx: number;
  vy: number;
  dead: boolean;
}
interface Orb {
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  dead: boolean;
}
interface Drop {
  x: number;
  y: number;
  kind: 'power' | 'heart' | 'shield';
  t: number;
  dead: boolean;
}

const SCORE: Record<EKind, number> = { blot: 20, moth: 25, eye: 50, boss: 800 };

export class GuardGame extends Arcade {
  vx = 0;
  vy = 0;
  power = 1;
  fireT = 0;
  wave = 0;
  queue: { kind: EKind; delay: number }[] = [];
  spawnT = 0;
  breakT = 0;
  enemies: Enemy[] = [];
  shots: Shot[] = [];
  orbs: Orb[] = [];
  drops: Drop[] = [];
  flashR = 0;

  constructor(canvas: HTMLCanvasElement, ev: ArcadeEvents) {
    super(canvas, ev, CHAPTERS[4]);
    this.dark = true;
    this.dashCdMax = 3;
    this.dashDur = 0.35;
    this.dashLabel = 'Вспышка';
    this.hint = 'Веди пальцем — фея стреляет сама';
    this.boot();
  }

  stat() {
    return this.wave;
  }

  reset() {
    this.hx = this.W / 2;
    this.hy = this.H * 0.8;
    this.vx = this.vy = 0;
    this.power = 1;
    this.fireT = 0;
    this.wave = 0;
    this.enemies = [];
    this.shots = [];
    this.orbs = [];
    this.drops = [];
    this.queue = [];
    this.breakT = 0.6;
  }
  idleReset() {
    this.reset();
  }
  onRevive() {
    this.orbs = [];
    for (const e of this.enemies) if (e.kind !== 'boss' && Math.hypot(e.x - this.hx, e.y - this.hy) < 200) e.dead = true;
  }
  onResize() {
    this.hx = Math.min(Math.max(this.hx, 20), this.W - 20);
    this.hy = Math.min(Math.max(this.hy, this.H * 0.3), this.H - 30);
  }
  onHurt() {
    if (this.power > 1) {
      this.power--;
      this.popText(this.hx, this.hy - 40, 'Сила −1', '#b58cff', 20);
    }
    this.orbs = this.orbs.filter((o) => Math.hypot(o.x - this.hx, o.y - this.hy) > 80);
  }

  /** Звёздная вспышка: сжигает снаряды вокруг */
  onDash() {
    this.flashR = 0.01;
    let n = 0;
    for (const o of this.orbs) {
      if (Math.hypot(o.x - this.hx, o.y - this.hy) < 120) {
        o.dead = true;
        n++;
        this.burst(o.x, o.y, 4, '#ffe89a', 120, 1);
      }
    }
    if (n > 0) this.addScore(5 * n, this.hx, this.hy - 30, '#ffe89a');
    this.ring(this.hx, this.hy, 120, '#ffe89a');
    this.shake = Math.max(this.shake, 6);
  }

  nextWave() {
    this.wave++;
    const w = this.wave;
    this.queue = [];
    if (w % 5 === 0) {
      this.queue.push({ kind: 'boss', delay: 0.8 });
      for (let i = 0; i < 4; i++) this.queue.push({ kind: 'blot', delay: 1.2 });
      this.popText(this.W / 2, this.H * 0.35, 'Чернильный Кракен!', '#b58cff', 40);
      sfx.boom();
    } else {
      const n = Math.min(26, 6 + w * 2);
      for (let i = 0; i < n; i++) {
        const r = Math.random();
        let kind: EKind = 'blot';
        if (w >= 3 && r < Math.min(0.25, 0.08 + w * 0.02)) kind = 'eye';
        else if (w >= 2 && r < 0.5) kind = 'moth';
        this.queue.push({ kind, delay: Math.max(0.25, 0.9 - w * 0.04) * (0.6 + Math.random() * 0.8) });
      }
      this.popText(this.W / 2, this.H * 0.35, `Волна ${w}`, '#ffe89a', 40);
      sfx.win();
    }
    this.spawnT = 0.6;
  }

  spawn(kind: EKind) {
    const w = this.wave;
    const x = this.rand(40, this.W - 40);
    const base = { x, y: -30, vx: 0, vy: 0, t: 0, seed: this.seedC++ * 1.618, fireT: this.rand(1, 2), hit: 0, dead: false, ty: 0 };
    if (kind === 'blot') {
      const hp = 2 + Math.floor(w / 4);
      this.enemies.push({ ...base, kind, hp, maxHp: hp, r: 16, vy: 45 + w * 3 });
    } else if (kind === 'moth') {
      this.enemies.push({ ...base, kind, hp: 1, maxHp: 1, r: 13, vy: 90 });
    } else if (kind === 'eye') {
      const hp = 4 + Math.floor(w / 3);
      this.enemies.push({ ...base, kind, hp, maxHp: hp, r: 18, vy: 80, ty: this.rand(70, this.H * 0.32) });
    } else {
      const hp = 60 + w * 8;
      this.enemies.push({ ...base, kind, x: this.W / 2, y: -80, hp, maxHp: hp, r: 46, vy: 60, ty: Math.max(110, this.H * 0.2), fireT: 2 });
    }
  }

  fire() {
    const sp = 640;
    const add = (ox: number, a: number) => this.shots.push({ x: this.hx + ox, y: this.hy - 16, vx: Math.sin(a) * sp, vy: -Math.cos(a) * sp, dead: false });
    if (this.power === 1) add(0, 0);
    else if (this.power === 2) {
      add(-6, 0);
      add(6, 0);
    } else if (this.power === 3) {
      add(0, 0);
      add(-4, -0.16);
      add(4, 0.16);
    } else {
      add(-5, 0);
      add(5, 0);
      add(-6, -0.24);
      add(6, 0.24);
    }
    if (this.state === 'play') sfx.tone(1100 + Math.random() * 200, 0.04, 'triangle', 0.025);
  }

  shootOrb(x: number, y: number, a: number, sp: number, r = 8) {
    this.orbs.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, r, dead: false });
  }

  idleStep(dt: number) {
    this.hx = this.W / 2 + Math.sin(this.time * 0.8) * this.W * 0.25;
    this.hy = this.H * 0.75 + Math.sin(this.time * 1.7) * 20;
    this.facing = Math.cos(this.time * 0.8) >= 0 ? 1 : -1;
    this.fireT -= dt;
    if (this.fireT <= 0) {
      this.fire();
      this.fireT = 0.2;
    }
    for (const s of this.shots) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
    }
    this.shots = this.shots.filter((s) => s.y > -20);
    if (Math.random() < dt * 20) this.trailSpark();
  }

  step(dt: number) {
    const playing = this.state === 'play';
    this.tryDash();
    if (this.flashR > 0) this.flashR += dt * 3;
    if (this.flashR > 1) this.flashR = 0;
    const inp = this.input();
    const sp = 360;
    this.vx += (inp.x * sp - this.vx) * Math.min(1, dt * 12);
    this.vy += (inp.y * sp - this.vy) * Math.min(1, dt * 12);
    this.hx = Math.max(20, Math.min(this.W - 20, this.hx + this.vx * dt));
    this.hy = Math.max(this.H * 0.3, Math.min(this.H - 30, this.hy + this.vy * dt));
    if (Math.abs(inp.x) > 0.15) this.facing = inp.x > 0 ? 1 : -1;
    if (Math.random() < dt * 25) this.trailSpark();

    // стрельба
    this.fireT -= dt;
    if (playing && this.fireT <= 0) {
      this.fire();
      this.fireT = 0.15;
    }

    // волны
    if (playing) {
      if (this.queue.length > 0) {
        this.spawnT -= dt;
        if (this.spawnT <= 0) {
          const q = this.queue.shift()!;
          this.spawn(q.kind);
          this.spawnT = this.queue[0]?.delay ?? 0;
        }
      } else if (this.enemies.length === 0) {
        if (this.breakT <= 0) {
          if (this.wave > 0) {
            this.addScore(100 * this.wave, this.W / 2, this.H * 0.45, '#ffe89a', false);
            this.burst(this.W / 2, this.H * 0.45, 30, '#ffe89a', 260, 1);
          }
          this.breakT = 1.6;
        }
        this.breakT -= dt;
        if (this.breakT <= 0.001) {
          this.breakT = 0;
          this.nextWave();
        }
      }
    }

    // выстрелы феи
    for (const s of this.shots) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      if (s.y < -20 || s.x < -20 || s.x > this.W + 20) s.dead = true;
    }

    // враги
    for (const e of this.enemies) {
      if (e.dead) continue;
      e.t += dt;
      e.hit = Math.max(0, e.hit - dt);
      switch (e.kind) {
        case 'blot':
          e.y += e.vy * dt;
          e.x += Math.sin(e.t * 1.6 + e.seed) * 50 * dt;
          break;
        case 'moth': {
          if (e.t < 1) e.y += e.vy * dt;
          else {
            const dx = this.hx - e.x, dy = this.hy - e.y;
            const d = Math.hypot(dx, dy) || 1;
            const msp = 150 + this.wave * 6;
            e.vx += ((dx / d) * msp - e.vx) * Math.min(1, dt * 1.5);
            e.vy += ((dy / d) * msp - e.vy) * Math.min(1, dt * 1.5);
            if (e.t > 5) e.vy = Math.abs(e.vy) + 40;
            e.x += e.vx * dt;
            e.y += e.vy * dt;
          }
          break;
        }
        case 'eye':
          if (e.t < 8) e.y += (e.ty - e.y) * Math.min(1, dt * 2);
          else e.y -= 120 * dt;
          e.x += Math.sin(e.t * 0.9 + e.seed) * 40 * dt;
          e.fireT -= dt;
          if (playing && e.fireT <= 0 && e.t < 8 && e.y > 20) {
            const a = Math.atan2(this.hy - e.y, this.hx - e.x);
            this.shootOrb(e.x, e.y, a, 170 + this.wave * 5);
            e.fireT = Math.max(1, 2 - this.wave * 0.05);
            sfx.tone(260, 0.1, 'square', 0.03, 140);
          }
          if (e.t > 8 && e.y < -40) e.dead = true;
          break;
        case 'boss': {
          e.y += (e.ty - e.y) * Math.min(1, dt * 1.5);
          e.x = this.W / 2 + Math.sin(e.t * 0.6) * this.W * 0.3;
          e.fireT -= dt;
          if (playing && e.fireT <= 0) {
            const rage = 1 - e.hp / e.maxHp;
            const pat = Math.floor(Math.random() * 3);
            const osp = 150 + this.wave * 4 + rage * 60;
            if (pat === 0) {
              const n = 14 + Math.floor(rage * 8);
              const off = Math.random() * 6;
              for (let i = 0; i < n; i++) this.shootOrb(e.x, e.y, off + (i / n) * Math.PI * 2, osp, 9);
            } else if (pat === 1) {
              const a = Math.atan2(this.hy - e.y, this.hx - e.x);
              for (let i = -2; i <= 2; i++) this.shootOrb(e.x, e.y, a + i * 0.2, osp * 1.3, 9);
            } else {
              for (let i = 0; i < 16; i++) this.shootOrb(e.x, e.y, i * 0.42 + e.t, osp * (0.6 + i * 0.04), 8);
            }
            if (Math.random() < 0.4) this.queue.push({ kind: 'blot', delay: 0.2 });
            this.ring(e.x, e.y, 70, '#2a2040');
            sfx.tone(180, 0.2, 'square', 0.05, 90);
            e.fireT = Math.max(1, 2.4 - rage * 1.2);
          }
          break;
        }
      }
      if (e.kind !== 'boss' && e.y > this.H + 40) {
        e.dead = true;
        this.combo = 0;
      }
      // попадания
      for (const s of this.shots) {
        if (s.dead) continue;
        if (Math.hypot(s.x - e.x, s.y - e.y) < e.r + 4) {
          s.dead = true;
          e.hp--;
          e.hit = 0.08;
          this.addParticle({ x: s.x, y: s.y, vx: this.rand(-60, 60), vy: this.rand(-40, 40), life: 0.25, max: 0.25, size: 2, color: '#ffe89a', kind: 1, g: 0, rot: 0 });
          if (e.hp <= 0) {
            this.kill(e);
            break;
          }
        }
      }
      if (e.dead || !playing) continue;
      if (Math.hypot(e.x - this.hx, e.y - this.hy) < e.r + 10) {
        if (this.hurt() && e.kind !== 'boss') {
          e.hp -= 3;
          if (e.hp <= 0) this.kill(e);
        }
      }
    }
    this.enemies = this.enemies.filter((e) => !e.dead);
    this.shots = this.shots.filter((s) => !s.dead);

    // вражеские снаряды
    for (const o of this.orbs) {
      o.x += o.vx * dt;
      o.y += o.vy * dt;
      if (o.x < -30 || o.x > this.W + 30 || o.y < -30 || o.y > this.H + 30) o.dead = true;
      else if (playing && Math.hypot(o.x - this.hx, o.y - this.hy) < o.r + 7) {
        if (this.hurt()) o.dead = true;
      }
    }
    this.orbs = this.orbs.filter((o) => !o.dead);

    // подарки
    for (const d of this.drops) {
      d.t += dt;
      d.y += 70 * dt;
      if (d.y > this.H + 20) d.dead = true;
      if (playing && Math.hypot(d.x - this.hx, d.y - this.hy) < 26) {
        d.dead = true;
        if (d.kind === 'power') {
          if (this.power < 4) {
            this.power++;
            this.popText(d.x, d.y - 20, 'Сила звёзд +1!', '#ffe89a', 24);
          } else this.addScore(100, d.x, d.y, '#ffe89a');
        } else if (d.kind === 'heart') {
          this.hearts = Math.min(this.maxHearts, this.hearts + 1);
          this.popText(d.x, d.y - 20, '+1 ♥', '#d8433b', 26);
        } else {
          this.shield = 1;
          this.popText(d.x, d.y - 20, 'Щит!', '#e86a92', 26);
        }
        this.burst(d.x, d.y, 18, '#ffe89a', 200, 1);
        this.ring(d.x, d.y, 40, '#ffe89a');
        sfx.bloom();
      }
    }
    this.drops = this.drops.filter((d) => !d.dead);
  }

  kill(e: Enemy) {
    e.dead = true;
    this.addScore(SCORE[e.kind], e.x, e.y, e.kind === 'boss' ? '#b58cff' : '#ffe89a');
    const big = e.kind === 'boss';
    this.burst(e.x, e.y, big ? 60 : 16, big ? '#b58cff' : '#ffe89a', big ? 420 : 240, 1);
    this.burst(e.x, e.y, big ? 30 : 8, '#1a1628', big ? 320 : 180, big ? 5 : 0);
    this.ring(e.x, e.y, big ? 160 : 40, this.ch.colors.accent);
    this.shake = Math.max(this.shake, big ? 24 : 5);
    this.hitstop = big ? 0.2 : 0.02;
    if (big) {
      this.orbs = [];
      this.flash = 0;
      sfx.boom();
      for (let i = 0; i < 3; i++) this.drops.push({ x: e.x + (i - 1) * 40, y: e.y, kind: i === 1 ? 'heart' : 'power', t: 0, dead: false });
    } else {
      sfx.kill();
      const r = Math.random();
      if (r < 0.09) this.drops.push({ x: e.x, y: e.y, kind: 'power', t: 0, dead: false });
      else if (r < 0.13) this.drops.push({ x: e.x, y: e.y, kind: 'heart', t: 0, dead: false });
      else if (r < 0.16) this.drops.push({ x: e.x, y: e.y, kind: 'shield', t: 0, dead: false });
    }
  }

  // ---------------- рисование
  drawScreenUnder(ctx: Ctx) {
    // падающие звёзды — ощущение полёта вверх
    ctx.strokeStyle = 'rgba(255,245,210,0.5)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let i = 0; i < 40; i++) {
      const x = S.hash(i + 5) * this.W;
      const sp = 60 + S.hash(i + 9) * 160;
      const y = ((S.hash(i + 13) * this.H + this.time * sp) % (this.H + 40)) - 20;
      ctx.moveTo(x, y);
      ctx.lineTo(x, y - sp * 0.06);
    }
    ctx.stroke();
  }

  drawWorld(ctx: Ctx) {
    const t = this.time;
    for (const d of this.drops) {
      const bob = Math.sin(d.t * 5) * 3;
      if (d.kind === 'power') {
        ctx.fillStyle = 'rgba(255,230,120,0.3)';
        ctx.beginPath();
        ctx.arc(d.x, d.y + bob, 18, 0, Math.PI * 2);
        ctx.fill();
        S.sPoly(ctx, S.starPts(d.x, d.y + bob, 12, 5, 5, t * 2), 40, true, '#f7d060', 1.3, 0.5, 'rgba(255,250,220,0.9)');
      } else if (d.kind === 'heart') {
        ctx.beginPath();
        S.heartPath(ctx, d.x, d.y + bob, 24, 41);
        ctx.fillStyle = S.hatch(ctx, '#d8433b');
        ctx.fill();
        ctx.strokeStyle = 'rgba(255,240,240,0.9)';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      } else {
        for (let i = 0; i < 5; i++) {
          const a = (i / 5) * Math.PI * 2 + t;
          S.sEllipse(ctx, d.x + Math.cos(a) * 9, d.y + bob + Math.sin(a) * 9, 7, 5, 42 + i, '#e86a92', 1, 'rgba(255,240,245,0.9)');
        }
      }
    }
    for (const e of this.enemies) this.drawEnemy(ctx, e);
    // выстрелы
    ctx.strokeStyle = '#ffe89a';
    ctx.lineWidth = 3;
    ctx.beginPath();
    for (const s of this.shots) {
      ctx.moveTo(s.x, s.y);
      ctx.lineTo(s.x - s.vx * 0.02, s.y - s.vy * 0.02);
    }
    ctx.stroke();
    ctx.fillStyle = '#ffffff';
    for (const s of this.shots) {
      ctx.beginPath();
      ctx.arc(s.x, s.y, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    // вражеские снаряды
    for (const o of this.orbs) {
      ctx.fillStyle = 'rgba(120,60,180,0.3)';
      ctx.beginPath();
      ctx.arc(o.x, o.y, o.r + 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#4a2d70';
      ctx.strokeStyle = 'rgba(230,210,255,0.9)';
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      ctx.arc(o.x, o.y, o.r, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
    if (this.flashR > 0) {
      ctx.strokeStyle = `rgba(255,232,154,${1 - this.flashR})`;
      ctx.lineWidth = 6 * (1 - this.flashR) + 1;
      ctx.beginPath();
      ctx.arc(this.hx, this.hy, 120 * this.flashR, 0, Math.PI * 2);
      ctx.stroke();
    }
    this.drawHero(ctx, 1.2, this.power >= 3 ? 0.4 + Math.sin(t * 8) * 0.2 : 0);
  }

  drawEnemy(ctx: Ctx, e: Enemy) {
    const t = this.time;
    const hitCol = e.hit > 0 ? '#ffffff' : null;
    switch (e.kind) {
      case 'blot':
        ctx.fillStyle = hitCol ?? 'rgba(20,16,24,0.9)';
        ctx.beginPath();
        S.ellipsePath(ctx, e.x, e.y, e.r, e.r, e.seed, 0, 0.35);
        ctx.fill();
        S.scribble(ctx, e.x, e.y, e.r * 1.1, e.seed, 10, 'rgba(200,190,255,0.35)', 1);
        ctx.fillStyle = '#f3ecdc';
        ctx.beginPath();
        ctx.arc(e.x - 5, e.y - 3, 3, 0, Math.PI * 2);
        ctx.arc(e.x + 5, e.y - 3, 3, 0, Math.PI * 2);
        ctx.fill();
        break;
      case 'moth': {
        const wf = 0.5 + Math.abs(Math.sin(t * 14 + e.seed)) * 0.5;
        ctx.save();
        ctx.translate(e.x, e.y);
        ctx.scale(wf, 1);
        S.sEllipse(ctx, -12, -2, 12, 9, e.seed, hitCol ?? '#3a3450', 1.2, 'rgba(230,220,255,0.7)');
        S.sEllipse(ctx, 12, -2, 12, 9, e.seed + 1, hitCol ?? '#3a3450', 1.2, 'rgba(230,220,255,0.7)');
        ctx.restore();
        ctx.fillStyle = 'rgba(255,60,80,0.9)';
        ctx.beginPath();
        ctx.arc(e.x - 3, e.y - 2, 1.8, 0, Math.PI * 2);
        ctx.arc(e.x + 3, e.y - 2, 1.8, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
      case 'eye': {
        S.sCircle(ctx, e.x, e.y, e.r, e.seed, hitCol ?? '#2a2040', 1.8, 'rgba(230,220,255,0.85)');
        S.sEllipse(ctx, e.x, e.y, e.r * 0.7, e.r * 0.45, e.seed + 1, '#f3ecdc', 1.2);
        const a = Math.atan2(this.hy - e.y, this.hx - e.x);
        ctx.fillStyle = '#b8433b';
        ctx.beginPath();
        ctx.arc(e.x + Math.cos(a) * 5, e.y + Math.sin(a) * 3, 5, 0, Math.PI * 2);
        ctx.fill();
        for (let i = 0; i < 5; i++) {
          const la = Math.PI * 0.2 + (i / 4) * Math.PI * 0.6;
          S.sLine(ctx, e.x + Math.cos(la) * e.r, e.y + Math.sin(la) * e.r, e.x + Math.cos(la) * (e.r + 10 + Math.sin(t * 5 + i) * 3), e.y + Math.sin(la) * (e.r + 12), e.seed + i, 1.4, 'rgba(20,16,30,0.9)', 3);
        }
        break;
      }
      case 'boss': {
        const x = e.x, y = e.y;
        ctx.fillStyle = 'rgba(20,10,40,0.35)';
        ctx.beginPath();
        ctx.arc(x, y, 70 + Math.sin(t * 3) * 4, 0, Math.PI * 2);
        ctx.fill();
        for (let i = 0; i < 8; i++) {
          const a = Math.PI * 0.1 + (i / 7) * Math.PI * 0.8;
          const len = 44 + Math.sin(t * 3 + i) * 14;
          S.sLine(ctx, x + Math.cos(a) * 36, y + Math.sin(a) * 36, x + Math.cos(a) * (46 + len) + Math.sin(t * 2 + i) * 10, y + Math.sin(a) * (46 + len), e.seed + 10 + i, 4, 'rgba(20,10,40,0.9)', 12);
        }
        S.sCircle(ctx, x, y, e.r, e.seed, hitCol ?? '#2a2040', 2.2, 'rgba(230,220,255,0.8)');
        S.scribble(ctx, x, y, e.r * 0.95, e.seed + 1, 24, 'rgba(10,6,20,0.7)', 1.4);
        ctx.fillStyle = '#ffe89a';
        ctx.beginPath();
        ctx.ellipse(x - 16, y - 8, 9, 5, -0.3, 0, Math.PI * 2);
        ctx.ellipse(x + 16, y - 8, 9, 5, 0.3, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
    }
  }

  drawHudExtra(ctx: Ctx) {
    const cx = this.W / 2;
    this.text(ctx, cx, 30, this.wave > 0 ? `Волна ${this.wave}` : 'Готовься!', '#ffe89a', 28);
    let pips = '';
    for (let i = 0; i < 4; i++) pips += i < this.power ? '★' : '☆';
    this.text(ctx, cx, 58, 'Сила ' + pips, '#f7d060', 20);
    const boss = this.enemies.find((e) => e.kind === 'boss');
    if (boss) {
      const bw = Math.min(360, this.W * 0.6);
      const bx = cx - bw / 2, by = 76;
      S.sPoly(ctx, [bx, by, bx + bw, by, bx + bw, by + 12, bx, by + 12], 99, true, null, 1.3, 0.6, 'rgba(240,230,255,0.9)');
      ctx.fillStyle = S.hatch(ctx, '#b58cff', 1.5);
      ctx.fillRect(bx + 2, by + 2, (bw - 4) * Math.max(0, boss.hp / boss.maxHp), 8);
      this.text(ctx, cx, by + 26, 'Чернильный Кракен', '#b58cff', 20);
    }
  }
}
