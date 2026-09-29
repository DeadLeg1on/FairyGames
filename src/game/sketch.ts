// Pencil-sketch rendering helpers: jittery "boiling" lines, hatch fills, scribbles.
type Ctx = CanvasRenderingContext2D;

export const GRAPHITE = 'rgba(38,34,32,0.85)';
export const GRAPHITE_SOFT = 'rgba(38,34,32,0.35)';

let boil = 0;
let boilFrozen = false;
export function setBoil(t: number) {
  if (!boilFrozen) boil = Math.floor(t * 8);
}
export function freezeBoil(on: boolean) {
  boilFrozen = on;
  if (on) boil = 0;
}

export function hash(n: number) {
  const s = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return s - Math.floor(s);
}
/** jitter in -0.5..0.5 that changes ~8 times per second */
export function jr(seed: number, i: number) {
  return hash(seed * 13.37 + i * 7.13 + boil * 3.17) - 0.5;
}

const XS = new Float32Array(64);
const YS = new Float32Array(64);

function closedCurve(ctx: Ctx, n: number) {
  let mx = (XS[n - 1] + XS[0]) / 2;
  let my = (YS[n - 1] + YS[0]) / 2;
  ctx.moveTo(mx, my);
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    mx = (XS[i] + XS[j]) / 2;
    my = (YS[i] + YS[j]) / 2;
    ctx.quadraticCurveTo(XS[i], YS[i], mx, my);
  }
}

export function ellipsePath(ctx: Ctx, x: number, y: number, rx: number, ry: number, seed: number, pass = 0, wob = 0.1) {
  const r = Math.max(rx, ry);
  const n = Math.max(7, Math.min(22, (r * 0.5) | 0));
  const a0 = jr(seed, pass * 50) * 1.2;
  for (let i = 0; i < n; i++) {
    const a = a0 + (i / n) * Math.PI * 2;
    const k = 1 + jr(seed, pass * 50 + i + 1) * wob;
    XS[i] = x + Math.cos(a) * rx * k + pass * 0.6;
    YS[i] = y + Math.sin(a) * ry * k - pass * 0.4;
  }
  closedCurve(ctx, n);
}

// ---------- hatch patterns ----------
const patCache = new Map<string, CanvasPattern>();
export function hatch(ctx: Ctx, color: string, dense = 1): CanvasPattern {
  const key = color + dense;
  let p = patCache.get(key);
  if (p) return p;
  const c = document.createElement('canvas');
  const S = 48;
  c.width = S;
  c.height = S;
  const g = c.getContext('2d')!;
  g.globalAlpha = 0.32;
  g.fillStyle = color;
  g.fillRect(0, 0, S, S);
  g.strokeStyle = color;
  g.lineCap = 'round';
  const step = 6 / dense;
  for (let i = -S; i < S * 2; i += step) {
    g.globalAlpha = 0.45 + Math.random() * 0.4;
    g.lineWidth = 0.8 + Math.random() * 1.1;
    g.beginPath();
    g.moveTo(i + Math.random() * 2, S + 1);
    g.lineTo(i + S + Math.random() * 2, -1);
    g.stroke();
  }
  p = ctx.createPattern(c, 'repeat')!;
  patCache.set(key, p);
  return p;
}

export function sEllipse(ctx: Ctx, x: number, y: number, rx: number, ry: number, seed: number, fill?: string | null, lw = 1.6, stroke: string = GRAPHITE) {
  ctx.beginPath();
  ellipsePath(ctx, x, y, rx, ry, seed, 0);
  if (fill) {
    ctx.fillStyle = hatch(ctx, fill);
    ctx.fill();
  }
  if (lw > 0) {
    ellipsePath(ctx, x, y, rx, ry, seed + 3, 1);
    ctx.strokeStyle = stroke;
    ctx.lineWidth = lw;
    ctx.stroke();
  }
}
export function sCircle(ctx: Ctx, x: number, y: number, r: number, seed: number, fill?: string | null, lw = 1.6, stroke: string = GRAPHITE) {
  sEllipse(ctx, x, y, r, r, seed, fill, lw, stroke);
}

/** polygon/polyline from flat point list with jitter; two pencil passes */
export function sPoly(ctx: Ctx, pts: number[], seed: number, closed: boolean, fill?: string | null, lw = 1.6, amp = 1.6, stroke: string = GRAPHITE) {
  const n = pts.length / 2;
  for (let pass = 0; pass < 2; pass++) {
    ctx.beginPath();
    for (let i = 0; i < n; i++) {
      const x = pts[i * 2] + jr(seed + pass * 9, i * 2) * amp * 2;
      const y = pts[i * 2 + 1] + jr(seed + pass * 9, i * 2 + 1) * amp * 2;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    if (closed) ctx.closePath();
    if (pass === 0 && fill) {
      ctx.fillStyle = hatch(ctx, fill);
      ctx.fill();
    }
    if (lw > 0) {
      ctx.strokeStyle = stroke;
      ctx.lineWidth = pass === 0 ? lw : lw * 0.6;
      ctx.stroke();
    }
  }
}

export function sLine(ctx: Ctx, x1: number, y1: number, x2: number, y2: number, seed: number, lw = 1.5, stroke: string = GRAPHITE, bend = 2) {
  ctx.strokeStyle = stroke;
  for (let pass = 0; pass < 2; pass++) {
    const mx = (x1 + x2) / 2 + jr(seed, pass * 4) * bend * 2;
    const my = (y1 + y2) / 2 + jr(seed, pass * 4 + 1) * bend * 2;
    ctx.beginPath();
    ctx.moveTo(x1 + jr(seed, pass * 4 + 2) * 1.5, y1 + jr(seed, pass * 4 + 3) * 1.5);
    ctx.quadraticCurveTo(mx, my, x2, y2);
    ctx.lineWidth = pass === 0 ? lw : lw * 0.55;
    ctx.stroke();
  }
}

/** dense zig-zag graphite scribble inside a circle — for shadowy things */
export function scribble(ctx: Ctx, x: number, y: number, r: number, seed: number, n = 10, color = 'rgba(30,26,30,0.8)', lw = 1.3) {
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const a = jr(seed, i) * Math.PI * 4;
    const d = (0.3 + (jr(seed, i + 30) + 0.5) * 0.7) * r;
    const px = x + Math.cos(a) * d;
    const py = y + Math.sin(a) * d;
    if (i === 0) ctx.moveTo(px, py);
    else ctx.lineTo(px, py);
  }
  ctx.strokeStyle = color;
  ctx.lineWidth = lw;
  ctx.stroke();
}

export function heartPath(ctx: Ctx, x: number, y: number, s: number, seed: number) {
  const j = (i: number) => jr(seed, i) * s * 0.12;
  ctx.moveTo(x + j(0), y + s * 0.35 + j(1));
  ctx.bezierCurveTo(x - s * 0.1, y + s * 0.05, x - s * 0.9 + j(2), y - s * 0.1, x - s * 0.5, y - s * 0.55 + j(3));
  ctx.bezierCurveTo(x - s * 0.25, y - s * 0.8, x + j(4), y - s * 0.55, x, y - s * 0.3);
  ctx.bezierCurveTo(x + j(5), y - s * 0.55, x + s * 0.25, y - s * 0.8, x + s * 0.5, y - s * 0.55 + j(6));
  ctx.bezierCurveTo(x + s * 0.9 + j(7), y - s * 0.1, x + s * 0.1, y + s * 0.05, x + j(0), y + s * 0.35 + j(1));
}

export function starPts(x: number, y: number, r1: number, r2: number, n: number, rot: number) {
  const pts: number[] = [];
  for (let i = 0; i < n * 2; i++) {
    const a = rot + (i / (n * 2)) * Math.PI * 2 - Math.PI / 2;
    const r = i % 2 === 0 ? r1 : r2;
    pts.push(x + Math.cos(a) * r, y + Math.sin(a) * r);
  }
  return pts;
}

// ---------- paper ----------
let noiseTile: HTMLCanvasElement | null = null;
export function paperNoise(): HTMLCanvasElement {
  if (noiseTile) return noiseTile;
  const c = document.createElement('canvas');
  c.width = c.height = 200;
  const g = c.getContext('2d')!;
  const img = g.createImageData(200, 200);
  for (let i = 0; i < img.data.length; i += 4) {
    const v = Math.random();
    const d = v < 0.5 ? 0 : 255;
    img.data[i] = d === 0 ? 70 : 255;
    img.data[i + 1] = d === 0 ? 60 : 250;
    img.data[i + 2] = d === 0 ? 50 : 240;
    img.data[i + 3] = Math.random() * 22;
  }
  g.putImageData(img, 0, 0);
  noiseTile = c;
  return c;
}
