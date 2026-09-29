// Часть III. «Светлячковый хоровод»: фея летит без остановки, за ней тянется хвост из светлячков.
// Длинный хоровод, доведённый до Лунного фонаря, приносит очки квадратично. Хвост можно порвать —
// самой себе или мотыльку-тени.
import { Arcade, type ArcadeEvents, type Ctx } from './base';
import { CHAPTERS } from '../game/chapters';
import * as S from '../game/sketch';
import { sfx } from '../game/audio';

interface Fly {
  x: number;
  y: number;
  vx: number;
  vy: number;
  a: number;
  seed: number;
  gold: boolean;
  flee: number;
  dead: boolean;
}
interface Moth {
  x: number;
  y: number;
  vx: number;
  vy: number;
  a: number;
  seed: number;
  scared: number;
  dead: boolean;
}

const GAP = 5; // сколько точек следа между звеньями хвоста (точка ≈ 3 px)
const TURN = 4.4;

export class FirefliesGame extends Arcade {
  ang = 0;
  tail = 0;
  best = 0;
  banked = 0;
  trail: { x: number; y: number }[] = [];
  flies: Fly[] = [];
  moths: Moth[] = [];
  lantern = { x: 0, y: 0, pulse: 0 };
  mothT = 0;

  constructor(canvas: HTMLCanvasElement, ev: ArcadeEvents) {
    super(canvas, ev, CHAPTERS[2]);
    this.dark = true;
    this.dashCdMax = 1.2;
    this.dashDur = 0.35;
    this.hint = 'Веди пальцем — фея повернёт туда';
    this.boot();
  }

  stat() {
    return this.banked;
  }

  // ---------------- мир
  reset() {
    this.hx = this.W * 0.3;
    this.hy = this.H * 0.55;
    this.ang = 0;
    this.tail = 0;
    this.best = 0;
    this.banked = 0;
    this.trail = [];
    this.flies = [];
    this.moths = [];
    this.mothT = 5;
    for (let i = 0; i < 4; i++) this.spawnFly(i === 0 ? { x: this.hx + 110, y: this.hy } : undefined);
    this.placeLantern(true);
  }

  idleReset() {
    this.hx = this.W * 0.5;
    this.hy = this.H * 0.5;
    this.ang = 0;
    this.tail = 8;
    this.trail = [];
    this.flies = [];
    this.moths = [];
    this.placeLantern(true);
  }

  onRevive() {
    for (const m of this.moths) {
      if (Math.hypot(m.x - this.hx, m.y - this.hy) < 220) m.dead = true;
    }
  }

  onResize() {
    this.hx = Math.min(Math.max(this.hx, 20), this.W - 20);
    this.hy = Math.min(Math.max(this.hy, 20), this.H - 20);
    this.lantern.x = Math.min(this.lantern.x, this.W - 50);
    this.lantern.y = Math.min(this.lantern.y, this.H - 50);
  }

  speed() {
    return (185 + Math.min(95, this.playT * 1.1)) * (this.dashT > 0 ? 1.9 : 1);
  }

  randPos(minDist = 130) {
    for (let i = 0; i < 12; i++) {
      const x = this.rand(50, this.W - 50), y = this.rand(110, this.H - 50);
      if (Math.hypot(x - this.hx, y - this.hy) > minDist) return { x, y };
    }
    return { x: this.rand(50, this.W - 50), y: this.rand(110, this.H - 50) };
  }

  spawnFly(at?: { x: number; y: number }) {
    const p = at ?? this.randPos();
    this.flies.push({ x: p.x, y: p.y, vx: 0, vy: 0, a: Math.random() * 6, seed: this.seedC++ * 1.618, gold: !at && Math.random() < 0.12, flee: 0, dead: false });
  }

  placeLantern(first = false) {
    let p = this.randPos(260);
    if (first) p = { x: this.W * 0.78, y: Math.max(120, this.H * 0.3) };
    this.lantern.x = Math.max(60, Math.min(this.W - 60, p.x));
    this.lantern.y = Math.max(110, Math.min(this.H - 60, p.y));
  }

  seg(i: number) {
    return this.trail[Math.min(this.trail.length - 1, (i + 1) * GAP)];
  }

  /** хвост рвётся на звене i — хвост за ним разлетается и снова ловится */
  cutTail(i: number, reason: string) {
    const lost = this.tail - i;
    if (lost <= 0) return;
    for (let k = i; k < this.tail && k < i + 8; k++) {
      const s = this.seg(k);
      if (!s) continue;
      const a = Math.random() * Math.PI * 2;
      this.flies.push({ x: s.x, y: s.y, vx: Math.cos(a) * 200, vy: Math.sin(a) * 200, a: Math.random() * 6, seed: this.seedC++ * 1.618, gold: false, flee: 1, dead: false });
    }
    const s = this.seg(i);
    if (s) this.burst(s.x, s.y, 16, '#f5e27a', 200, 1);
    this.tail = i;
    this.combo = 0;
    this.shake = Math.max(this.shake, 6);
    this.popText(this.hx, this.hy - 34, `${reason} −${lost}`, '#ff9aa0', 22);
    sfx.crash();
  }

  onHurt() {
    if (this.tail > 0) this.cutTail(Math.floor(this.tail / 2), 'Ох!');
  }

  onDash() {
    for (let i = 0; i < 8; i++) this.trailSpark('#f5e27a');
  }

  move(dt: number, steer: boolean) {
    const inp = this.input();
    if (steer && inp.len > 0.2) {
      const target = Math.atan2(inp.y, inp.x);
      let d = target - this.ang;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      const turn = TURN * (this.dashT > 0 ? 0.6 : 1) * dt;
      this.ang += Math.max(-turn, Math.min(turn, d));
    }
    const sp = this.speed();
    this.hx += Math.cos(this.ang) * sp * dt;
    this.hy += Math.sin(this.ang) * sp * dt;
    const r = 16;
    let bounced = false;
    if (this.hx < r || this.hx > this.W - r) {
      this.hx = Math.max(r, Math.min(this.W - r, this.hx));
      this.ang = Math.PI - this.ang;
      bounced = true;
    }
    if (this.hy < r + 10 || this.hy > this.H - r) {
      this.hy = Math.max(r + 10, Math.min(this.H - r, this.hy));
      this.ang = -this.ang;
      bounced = true;
    }
    if (bounced && steer) {
      this.shake = Math.max(this.shake, 2);
      sfx.tone(300, 0.06, 'triangle', 0.05);
    }
    this.facing = Math.cos(this.ang) >= 0 ? 1 : -1;
    const last = this.trail[0];
    if (!last || Math.hypot(last.x - this.hx, last.y - this.hy) >= 3) {
      this.trail.unshift({ x: this.hx, y: this.hy });
      const cap = (this.tail + 3) * GAP + 10;
      if (this.trail.length > cap) this.trail.length = cap;
    }
    if (Math.random() < dt * 25) this.trailSpark();
  }

  idleStep(dt: number) {
    this.ang += dt * 1.1;
    this.move(dt, false);
    this.lantern.pulse = Math.max(0, this.lantern.pulse - dt);
  }

  step(dt: number) {
    const playing = this.state === 'play';
    this.tryDash();
    this.move(dt, playing);
    this.lantern.pulse = Math.max(0, this.lantern.pulse - dt);

    // самопересечение (короткий хвост не может себя задеть)
    if (playing && this.dashT <= 0 && this.inv <= 0) {
      for (let i = 6; i < this.tail; i++) {
        const s = this.seg(i);
        if (s && Math.hypot(s.x - this.hx, s.y - this.hy) < 9) {
          this.cutTail(i, 'Хоровод порвался!');
          break;
        }
      }
    }

    // светлячки
    let alive = 0;
    for (const f of this.flies) {
      if (f.dead) continue;
      f.a += dt;
      if (f.flee > 0) {
        f.flee -= dt;
        f.vx *= 0.95;
        f.vy *= 0.95;
      } else {
        f.vx = Math.cos(f.a * 0.9 + f.seed) * 35;
        f.vy = Math.sin(f.a * 1.2 + f.seed) * 28;
      }
      f.x = Math.max(20, Math.min(this.W - 20, f.x + f.vx * dt));
      f.y = Math.max(60, Math.min(this.H - 20, f.y + f.vy * dt));
      if (f.flee <= 0 && playing && Math.hypot(f.x - this.hx, f.y - this.hy) < 24) {
        f.dead = true;
        const n = f.gold ? 3 : 1;
        this.tail += n;
        this.best = Math.max(this.best, this.tail);
        this.addScore(f.gold ? 40 : 10, f.x, f.y, f.gold ? '#ffd24a' : '#f5e27a');
        this.burst(f.x, f.y, f.gold ? 20 : 10, '#f5e27a', 180, 1);
        this.ring(f.x, f.y, 26, '#f5e27a');
        sfx.pickup(this.combo);
      } else alive++;
    }
    this.flies = this.flies.filter((f) => !f.dead);
    if (playing && alive < 4 + Math.min(3, Math.floor(this.playT / 30))) this.spawnFly();

    // фонарь
    const L = this.lantern;
    if (playing && this.tail > 0 && Math.hypot(L.x - this.hx, L.y - this.hy) < 38) {
      const n = this.tail;
      this.banked += n;
      this.addScore(20 * n + 4 * n * n, L.x, L.y - 36, '#f5e27a');
      for (let i = 0; i < n; i++) {
        const s = this.seg(i);
        if (!s) continue;
        const dx = L.x - s.x, dy = L.y - s.y;
        this.addParticle({ x: s.x, y: s.y, vx: dx * 2.2, vy: dy * 2.2, life: 0.45, max: 0.45, size: 3, color: '#f5e27a', kind: 0, g: 0, rot: 0 });
      }
      this.burst(L.x, L.y, 24 + n * 2, '#f5e27a', 260, 1);
      this.ring(L.x, L.y, 90 + n * 2, '#f5e27a');
      this.shake = Math.min(18, 6 + n * 0.6);
      this.hitstop = Math.min(0.12, 0.03 + n * 0.004);
      if (n >= 12) this.popText(this.W / 2, this.H * 0.35, 'Великий хоровод!', '#ffd24a', 40);
      else if (n >= 6) this.popText(this.W / 2, this.H * 0.35, 'Чудесный хоровод!', '#f5e27a', 32);
      this.tail = 0;
      L.pulse = 1;
      sfx.bloom();
      const old = { x: L.x, y: L.y };
      this.placeLantern();
      this.ring(old.x, old.y, 50, '#c9c1ff');
      this.ring(L.x, L.y, 60, '#f5e27a');
    }

    // мотыльки-тени
    this.mothT -= dt;
    const maxM = Math.min(7, 2 + Math.floor(this.playT / 18));
    if (playing && this.mothT <= 0 && this.moths.length < maxM) {
      const side = Math.floor(Math.random() * 4);
      const x = side === 0 ? -30 : side === 1 ? this.W + 30 : this.rand(0, this.W);
      const y = side === 2 ? -30 : side === 3 ? this.H + 30 : this.rand(60, this.H);
      this.moths.push({ x, y, vx: 0, vy: 0, a: Math.random() * 6, seed: this.seedC++ * 1.618, scared: 0, dead: false });
      this.mothT = Math.max(1.6, 4 - this.playT * 0.03);
    }
    const light = this.lightR();
    for (const m of this.moths) {
      if (m.dead) continue;
      m.a += dt;
      const dx = this.hx - m.x, dy = this.hy - m.y;
      const d = Math.hypot(dx, dy) || 1;
      let tx: number, ty: number;
      if (m.scared > 0) {
        m.scared -= dt;
        tx = (-dx / d) * 140;
        ty = (-dy / d) * 140;
      } else if (this.tail >= 3 || d < light) {
        // мотыльков тянет на свет хоровода
        const sp = Math.min(210, 75 + this.playT * 0.8 + this.tail * 2);
        tx = (dx / d) * sp + Math.cos(m.a * 3 + m.seed) * 40;
        ty = (dy / d) * sp + Math.sin(m.a * 3 + m.seed) * 40;
      } else {
        tx = Math.cos(m.a * 0.7 + m.seed) * 70 + (this.W / 2 - m.x) * 0.15;
        ty = Math.sin(m.a * 0.9 + m.seed) * 60 + (this.H / 2 - m.y) * 0.15;
      }
      m.vx += (tx - m.vx) * Math.min(1, dt * 2.2);
      m.vy += (ty - m.vy) * Math.min(1, dt * 2.2);
      m.x += m.vx * dt;
      m.y += m.vy * dt;
      if (!playing) continue;
      if (d < 26) {
        if (this.dashT > 0) {
          m.dead = true;
          this.addScore(30, m.x, m.y, '#c9c1ff');
          this.burst(m.x, m.y, 20, '#c9c1ff', 260, 1);
          this.burst(m.x, m.y, 10, '#1a1628', 200, 5);
          this.ring(m.x, m.y, 50, '#c9c1ff');
          this.shake = 9;
          this.hitstop = 0.05;
          sfx.kill();
          continue;
        }
        if (this.hurt()) m.scared = 1.5;
        continue;
      }
      if (m.scared <= 0) {
        for (let i = 0; i < this.tail; i++) {
          const s = this.seg(i);
          if (s && Math.hypot(s.x - m.x, s.y - m.y) < 13) {
            this.cutTail(i, 'Тень!');
            m.scared = 1.4;
            break;
          }
        }
      }
    }
    this.moths = this.moths.filter((m) => !m.dead);
  }

  lightR() {
    return Math.min(330, 115 + this.tail * 7);
  }

  // ---------------- рисование
  drawFirefly(ctx: Ctx, x: number, y: number, seed: number, gold = false) {
    const fl = 0.6 + Math.sin(this.time * 8 + seed) * 0.4;
    ctx.fillStyle = gold ? `rgba(255,200,60,${0.45 * fl})` : `rgba(255,230,110,${0.35 * fl})`;
    ctx.beginPath();
    ctx.arc(x, y, gold ? 16 : 12, 0, Math.PI * 2);
    ctx.fill();
    S.sCircle(ctx, x, y, gold ? 5.5 : 4, seed, gold ? '#ffc93a' : '#f5e27a', 1);
    S.sEllipse(ctx, x - 3, y - 5, 4, 2, seed + 1, null, 0.8, 'rgba(240,235,255,0.7)');
    S.sEllipse(ctx, x + 3, y - 5, 4, 2, seed + 2, null, 0.8, 'rgba(240,235,255,0.7)');
  }

  drawWorld(ctx: Ctx) {
    const L = this.lantern;
    // фонарь
    const x = L.x, y = L.y;
    const lc = 'rgba(240,230,255,0.9)';
    S.sLine(ctx, x, y - 30, x, y - 58, 901, 1.3, 'rgba(230,220,255,0.7)');
    S.sPoly(ctx, [x - 16, y - 26, x + 16, y - 26, x + 20, y + 22, x - 20, y + 22], 902, true, '#f5e27a', 1.8, 1, lc);
    S.sPoly(ctx, [x - 22, y - 26, x + 22, y - 26], 903, false, null, 2, 1, lc);
    S.sPoly(ctx, [x - 24, y + 22, x + 24, y + 22], 904, false, null, 2, 1, lc);
    // свободные светлячки
    for (const f of this.flies) {
      ctx.globalAlpha = f.flee > 0 ? 0.5 : 1;
      this.drawFirefly(ctx, f.x, f.y, f.seed, f.gold);
    }
    ctx.globalAlpha = 1;
    // хоровод-хвост
    if (this.tail > 0) {
      ctx.strokeStyle = 'rgba(245,226,122,0.25)';
      ctx.lineWidth = 3;
      ctx.beginPath();
      const end = Math.min(this.trail.length - 1, this.tail * GAP);
      for (let i = 0; i <= end; i += 2) {
        const p = this.trail[i];
        if (i === 0) ctx.moveTo(p.x, p.y);
        else ctx.lineTo(p.x, p.y);
      }
      ctx.stroke();
      for (let i = this.tail - 1; i >= 0; i--) {
        const s = this.seg(i);
        if (s) this.drawFirefly(ctx, s.x, s.y + Math.sin(this.time * 6 + i) * 1.5, i + 900);
      }
    }
    // мотыльки
    for (const m of this.moths) {
      const wf = 0.5 + Math.abs(Math.sin(this.time * 12 + m.seed)) * 0.5;
      ctx.save();
      ctx.translate(m.x, m.y);
      ctx.scale(wf, 1);
      S.sEllipse(ctx, -14, -2, 14, 10, m.seed, '#3a3450', 1.2, 'rgba(10,8,20,0.8)');
      S.sEllipse(ctx, 14, -2, 14, 10, m.seed + 1, '#3a3450', 1.2, 'rgba(10,8,20,0.8)');
      ctx.restore();
      S.scribble(ctx, m.x, m.y, 7, m.seed, 12, 'rgba(10,8,20,0.9)', 1.6);
    }
    this.drawHero(ctx, 1.2);
  }

  drawScreenOver(ctx: Ctx) {
    // ночная тьма с пятном света вокруг хоровода
    const light = this.lightR();
    const g = ctx.createRadialGradient(this.hx, this.hy, light * 0.35, this.hx, this.hy, light);
    g.addColorStop(0, 'rgba(14,12,34,0)');
    g.addColorStop(1, 'rgba(14,12,34,0.88)');
    ctx.fillStyle = g;
    ctx.fillRect(-20, -20, this.W + 40, this.H + 40);
    ctx.globalCompositeOperation = 'lighter';
    const glow = (x: number, y: number, r: number, a: number) => {
      const gg = ctx.createRadialGradient(x, y, 0, x, y, r);
      gg.addColorStop(0, `rgba(255,230,120,${a})`);
      gg.addColorStop(1, 'rgba(255,230,120,0)');
      ctx.fillStyle = gg;
      ctx.fillRect(x - r, y - r, r * 2, r * 2);
    };
    glow(this.lantern.x, this.lantern.y, 80 + this.lantern.pulse * 60 + Math.sin(this.time * 3) * 6, 0.5);
    for (const f of this.flies) glow(f.x, f.y, f.gold ? 34 : 24, f.flee > 0 ? 0.25 : 0.5);
    for (let i = 0; i < this.tail; i += 2) {
      const s = this.seg(i);
      if (s) glow(s.x, s.y, 22, 0.35);
    }
    ctx.fillStyle = 'rgba(255,60,80,0.8)';
    for (const m of this.moths) {
      ctx.beginPath();
      ctx.arc(m.x - 4, m.y - 3, 2, 0, Math.PI * 2);
      ctx.arc(m.x + 4, m.y - 3, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  drawHudExtra(ctx: Ctx) {
    const cx = this.W / 2;
    this.text(ctx, cx, 30, `Хоровод: ${this.tail}  ·  у фонаря: ${this.banked}`, '#f5e27a', 26);
    if (this.tail > 0) {
      const n = this.tail;
      this.text(ctx, cx, 58, `К фонарю → +${(20 * n + 4 * n * n) * this.mult()}`, '#c9c1ff', 20);
    } else if (this.playT < 6) {
      this.text(ctx, cx, 58, 'Собери светлячков и веди их к фонарю!', '#c9c1ff', 20);
    }
  }
}
