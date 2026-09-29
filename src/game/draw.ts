import type { ChapterDef } from './chapters';
import * as S from './sketch';

type Ctx = CanvasRenderingContext2D;

/** Цвет волос каждой феи: [основной, тень/контур, блик] */
const HAIR: Record<string, [string, string, string]> = {
  flower: ['#f2b441', '#b06f16', '#fff1b8'],
  water: ['#56b0e6', '#1d5f96', '#d8f2ff'],
  night: ['#d9d2ff', '#7d70cc', '#ffffff'],
  frost: ['#f2f8ff', '#86b4d6', '#ffffff'],
  star: ['#ffe07a', '#c48f16', '#fffbe0'],
  mushroom: ['#b8643a', '#6a2e16', '#f6c49a'],
  rainbow: ['#ff8fc2', '#b8457e', '#ffe0ef'],
  garden: ['#93c85c', '#46772a', '#e4f7c8'],
  storm: ['#8f9ac0', '#3c4668', '#e6ecff'],
};

/** Плавная замкнутая кривая через середины сторон */
function smoothClosed(ctx: Ctx, pts: number[]) {
  const n = pts.length / 2;
  const X = (i: number) => pts[((i + n) % n) * 2];
  const Y = (i: number) => pts[((i + n) % n) * 2 + 1];
  ctx.moveTo((X(-1) + X(0)) / 2, (Y(-1) + Y(0)) / 2);
  for (let i = 0; i < n; i++) ctx.quadraticCurveTo(X(i), Y(i), (X(i) + X(i + 1)) / 2, (Y(i) + Y(i + 1)) / 2);
  ctx.closePath();
}

function fillHair(ctx: Ctx, pts: number[], col: [string, string, string], lw: number) {
  ctx.beginPath();
  smoothClosed(ctx, pts);
  ctx.fillStyle = col[0];
  ctx.fill();
  ctx.fillStyle = S.hatch(ctx, col[1], 1.3);
  ctx.fill();
  ctx.strokeStyle = S.GRAPHITE;
  ctx.lineWidth = lw;
  ctx.stroke();
}

/** Длинные волосы за головой — развеваются на ветру */
function hairBack(ctx: Ctx, t: number, id: string) {
  const col = HAIR[id] ?? HAIR.flower;
  const w = (k: number) => Math.sin(t * 5 + k) * 1.7;
  const pts = [
    3, -17.6, -2, -18.9, -6.8, -16.6, -9, -12, -10.5 + w(0) * 0.4, -6.5, -13.5 + w(1), -1.5, -16.5 + w(2), 3.5,
    -19.5 + w(3), 8.5, -17.5 + w(3), 9.8, -14.5 + w(2.6), 7.2, -11.5 + w(2), 3.2, -8.5 + w(1), -1, -5.5, -4.5, -3, -6.5,
  ];
  fillHair(ctx, pts, col, 1.2);
  // пряди
  ctx.strokeStyle = col[1];
  ctx.globalAlpha = 0.65;
  ctx.lineWidth = 0.9;
  ctx.beginPath();
  ctx.moveTo(-5, -15.5);
  ctx.quadraticCurveTo(-11 + w(1), -5, -16.5 + w(3), 6.5);
  ctx.moveTo(-2.5, -16.5);
  ctx.quadraticCurveTo(-8 + w(1), -6, -12.5 + w(2.5), 5);
  ctx.moveTo(-7.5, -13);
  ctx.quadraticCurveTo(-13 + w(1.5), -4, -18 + w(3), 7.5);
  ctx.stroke();
  ctx.globalAlpha = 1;
}

/** Чёлка поверх головы + блик */
function hairFront(ctx: Ctx, id: string) {
  const col = HAIR[id] ?? HAIR.flower;
  const pts = [
    -7.3, -11, -7.7, -15, -4.2, -18.5, 1, -18.7, 5.6, -16.6, 7.7, -12.4, 6.1, -13.1, 4.6, -11.4, 3, -13.5, 1, -12.2,
    -1.1, -14.1, -3.2, -12.6, -5.2, -14.3,
  ];
  fillHair(ctx, pts, col, 1.1);
  ctx.strokeStyle = col[2];
  ctx.globalAlpha = 0.85;
  ctx.lineWidth = 1.3;
  ctx.beginPath();
  ctx.arc(-0.5, -12.2, 5.2, Math.PI * 1.2, Math.PI * 1.5);
  ctx.stroke();
  ctx.globalAlpha = 1;
}

export function drawFairy(ctx: Ctx, x: number, y: number, t: number, ch: ChapterDef, facing: number, scale = 1, glow = 0) {
  const { main, wing, accent } = ch.colors;
  ctx.save();
  ctx.translate(x, y + Math.sin(t * 5) * 2);
  ctx.scale(facing * scale, scale);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  if (glow > 0) {
    const g = ctx.createRadialGradient(0, 0, 2, 0, 0, 40);
    g.addColorStop(0, `rgba(255,236,150,${0.7 * glow})`);
    g.addColorStop(1, 'rgba(255,236,150,0)');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(0, 0, 40, 0, Math.PI * 2);
    ctx.fill();
  }

  // wings (flap)
  const flap = Math.sin(t * 28);
  const wy = 0.55 + 0.45 * Math.abs(flap);
  // верхнее крыло: от плеча назад-вверх, нижнее — назад-вниз
  ctx.save();
  ctx.translate(-2, -3);
  ctx.rotate(0.6);
  ctx.scale(1, wy);
  S.sEllipse(ctx, -14, 0, 14, 7, 11, wing, 1.2);
  ctx.restore();
  ctx.save();
  ctx.translate(-2, 0);
  ctx.rotate(-0.5);
  ctx.scale(1, wy);
  S.sEllipse(ctx, -11, 0, 11, 6, 17, wing, 1.2);
  ctx.restore();

  // длинные волосы (за телом)
  hairBack(ctx, t, ch.id);
  // dress
  S.sPoly(ctx, [0, -3, -9, 14, 9, 14], 21, true, main, 1.5, 0.8);
  // legs
  S.sLine(ctx, -3, 14, -4, 21, 23, 1.2);
  S.sLine(ctx, 3, 14, 5, 20, 24, 1.2);
  // arms
  S.sLine(ctx, 0, 0, 9, 5 + Math.sin(t * 6) * 2, 25, 1.2);
  // head
  S.sCircle(ctx, 0, -10, 7, 31, '#f6d9c0', 1.5);
  // eye
  ctx.fillStyle = S.GRAPHITE;
  ctx.beginPath();
  ctx.arc(3, -11, 1.1, 0, Math.PI * 2);
  ctx.fill();
  // румянец
  ctx.fillStyle = 'rgba(240,120,130,0.35)';
  ctx.beginPath();
  ctx.arc(2.5, -7.6, 1.8, 0, Math.PI * 2);
  ctx.fill();
  // чёлка
  hairFront(ctx, ch.id);

  // accessory per fairy kind
  switch (ch.id) {
    case 'flower':
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        S.sCircle(ctx, -1 + Math.cos(a) * 4, -19 + Math.sin(a) * 3, 2.8, 50 + i, main, 0.8);
      }
      S.sCircle(ctx, -1, -19, 2, 56, accent, 0.8);
      break;
    case 'water':
      S.sPoly(ctx, [0, -26, -4, -18, 4, -18], 60, true, wing, 1, 0.5);
      break;
    case 'night':
      ctx.beginPath();
      ctx.arc(1, -20, 5, Math.PI * 0.2, Math.PI * 1.3);
      ctx.arc(3, -21, 4, Math.PI * 1.3, Math.PI * 0.2, true);
      ctx.fillStyle = accent;
      ctx.fill();
      ctx.strokeStyle = S.GRAPHITE;
      ctx.lineWidth = 1;
      ctx.stroke();
      break;
    case 'frost':
      S.sPoly(ctx, [-6, -16, -4, -23, -1, -17, 1, -25, 3, -17, 6, -22, 6, -15], 70, false, null, 1.1, 0.5);
      break;
    case 'star':
      S.sLine(ctx, 9, 5, 16, -6, 80, 1.3);
      S.sPoly(ctx, S.starPts(17, -8, 5, 2.2, 5, t * 2), 81, true, accent, 1, 0.4);
      break;
    case 'mushroom':
      // шляпка-мухомор
      S.sPoly(ctx, [-9, -15, -6, -21, 0, -24, 6, -21, 9, -15], 90, true, main, 1.2, 0.4);
      ctx.fillStyle = '#fff4dc';
      ctx.beginPath();
      ctx.arc(-3, -19, 1.4, 0, 7);
      ctx.arc(3, -20, 1.2, 0, 7);
      ctx.arc(0, -17, 1, 0, 7);
      ctx.fill();
      break;
    case 'rainbow': {
      const cols = ['#e8504a', '#f2c230', '#3a8fd6'];
      cols.forEach((c, i) => {
        ctx.strokeStyle = c;
        ctx.lineWidth = 1.8;
        ctx.beginPath();
        ctx.arc(0, -12, 11 - i * 2, Math.PI * 1.1, Math.PI * 1.9);
        ctx.stroke();
      });
      break;
    }
    case 'garden':
      S.sLine(ctx, 0, -16, 2, -21, 95, 1.1);
      S.sEllipse(ctx, 5, -23, 5, 2.6, 96, main, 1);
      break;
    case 'storm':
      S.sPoly(ctx, [3, -30, -3, -21, 1, -21, -2, -14, 6, -24, 2, -24], 98, true, accent, 1, 0.3);
      break;
  }
  ctx.restore();
}

/** Draw a chapter scene background into ctx in world coords (W x H) */
export function drawScene(ctx: Ctx, ch: ChapterDef, W: number, H: number, ground: number) {
  S.freezeBoil(true);
  const gy = H - ground;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  const rnd = (i: number) => S.hash(i * 3.3 + 1.7);
  const soft = 'rgba(38,34,32,0.45)';

  // color wash
  const wash = ctx.createLinearGradient(0, 0, 0, H);
  const washes: Record<string, [string, string]> = {
    flower: ['rgba(255,220,230,0.35)', 'rgba(200,235,180,0.35)'],
    water: ['rgba(200,230,255,0.35)', 'rgba(150,210,230,0.4)'],
    night: ['rgba(60,50,110,0.5)', 'rgba(30,30,60,0.55)'],
    frost: ['rgba(220,240,255,0.5)', 'rgba(240,250,255,0.3)'],
    star: ['rgba(40,30,80,0.55)', 'rgba(90,60,120,0.45)'],
    mushroom: ['rgba(235,205,170,0.42)', 'rgba(150,115,80,0.42)'],
    rainbow: ['rgba(255,235,210,0.35)', 'rgba(205,240,255,0.38)'],
    garden: ['rgba(240,250,210,0.35)', 'rgba(185,225,140,0.4)'],
    storm: ['rgba(105,115,150,0.55)', 'rgba(70,80,110,0.55)'],
  };
  const [c1, c2] = washes[ch.id];
  wash.addColorStop(0, c1);
  wash.addColorStop(1, c2);
  ctx.fillStyle = wash;
  ctx.fillRect(0, 0, W, H);

  // far hills / mountains
  const pts: number[] = [];
  const steps = Math.ceil(W / 60) + 1;
  for (let i = 0; i <= steps; i++) {
    const x = i * 60;
    let y: number;
    if (ch.id === 'frost') y = gy - 120 - (i % 2 === 0 ? 120 + rnd(i) * 80 : 20 + rnd(i) * 30);
    else y = gy - 70 - Math.sin(i * 0.7) * 30 - rnd(i) * 30;
    pts.push(x, y);
  }
  const hillFill: Record<string, string> = { flower: '#9cc97a', water: '#7fb8a0', night: '#3a3560', frost: '#bcd9ec', star: '#2c2450', mushroom: '#a88a58', rainbow: '#a8d890', garden: '#8cc063', storm: '#56648a' };
  S.sPoly(ctx, [...pts, W, gy, 0, gy], 5, true, hillFill[ch.id], 1.2, 2, soft);
  if (ch.id === 'frost') {
    for (let i = 0; i < steps; i += 2) {
      const x = pts[i * 2], y = pts[i * 2 + 1];
      S.sPoly(ctx, [x - 22, y + 30, x, y, x + 22, y + 30], 90 + i, false, null, 1.2, 1.5, soft);
    }
  }

  // sky details
  if (ch.id === 'night' || ch.id === 'star') {
    for (let i = 0; i < 60; i++) {
      const x = rnd(i + 100) * W, y = rnd(i + 200) * (gy - 150);
      const r = 1 + rnd(i + 300) * 2.5;
      S.sPoly(ctx, S.starPts(x, y, r * 2, r * 0.7, 4, 0), 300 + i, true, ch.id === 'star' ? '#ffe89a' : '#f5f0c0', 0.6, 0.3, 'rgba(255,250,220,0.6)');
    }
    // moon
    S.sCircle(ctx, W * 0.82, 90, 42, 400, '#f5eeb8', 1.5, 'rgba(255,250,220,0.8)');
    S.sCircle(ctx, W * 0.82 + 10, 80, 8, 401, null, 1, 'rgba(90,80,40,0.4)');
    S.sCircle(ctx, W * 0.82 - 14, 100, 5, 402, null, 1, 'rgba(90,80,40,0.4)');
  } else {
    if (ch.id === 'rainbow') {
      const cols = ['#e8504a', '#f08a2c', '#f2c230', '#6fb04e', '#3a8fd6', '#7a6cd6'];
      cols.forEach((c, i) => {
        ctx.strokeStyle = c;
        ctx.globalAlpha = 0.5;
        ctx.lineWidth = 9;
        ctx.beginPath();
        ctx.arc(W * 0.5, gy + 40, Math.min(W * 0.45, gy * 0.9) - i * 9, Math.PI * 1.05, Math.PI * 1.95);
        ctx.stroke();
      });
      ctx.globalAlpha = 1;
    }
    if (ch.id === 'storm') {
      for (let i = 0; i < 7; i++) {
        const cx = (i / 6) * W, cy = 40 + rnd(i + 900) * 40;
        for (let k = 0; k < 3; k++) S.sCircle(ctx, cx + k * 30 - 30, cy + (k % 2) * 10, 34 + (k % 2) * 10, 910 + i * 5 + k, '#56607e', 1.4, soft);
      }
    }
    // sun + clouds
    if (ch.id !== 'frost' && ch.id !== 'storm') {
      S.sCircle(ctx, W * 0.85, 80, 34, 410, '#f7d060', 1.4, soft);
      for (let i = 0; i < 10; i++) {
        const a = (i / 10) * Math.PI * 2;
        S.sLine(ctx, W * 0.85 + Math.cos(a) * 44, 80 + Math.sin(a) * 44, W * 0.85 + Math.cos(a) * 58, 80 + Math.sin(a) * 58, 420 + i, 1.2, soft);
      }
    }
    for (let i = 0; i < 4; i++) {
      const cx = rnd(i + 500) * W * 0.75, cy = 60 + rnd(i + 510) * 120;
      for (let k = 0; k < 4; k++) S.sCircle(ctx, cx + k * 22, cy + (k % 2) * -8, 18 + (k % 2) * 6, 520 + i * 7 + k, null, 1.1, soft);
    }
  }

  // ground
  const gp: number[] = [];
  for (let x = -10; x <= W + 20; x += 40) gp.push(x, gy + Math.sin(x * 0.02) * 4);
  const groundFill: Record<string, string> = { flower: '#7fbf5a', water: '#5aa0c8', night: '#2a2848', frost: '#e6f4ff', star: '#3b2f5c', mushroom: '#8a6a45', rainbow: '#98cf7a', garden: '#7a5a3a', storm: '#4a5a76' };
  S.sPoly(ctx, [...gp, W + 20, H + 10, -10, H + 10], 600, true, groundFill[ch.id], 1.8, 1.5);

  // ground decoration
  const n = Math.floor(W / 18);
  for (let i = 0; i < n; i++) {
    const x = i * 18 + rnd(i + 700) * 10;
    const y = gy + Math.sin(x * 0.02) * 4;
    if (ch.id === 'water') {
      if (i % 3 === 0) S.sLine(ctx, x, y + 14 + rnd(i) * 20, x + 14, y + 14 + rnd(i) * 20, 700 + i, 1, 'rgba(255,255,255,0.7)');
      if (i % 5 === 0) S.sLine(ctx, x, y, x + 3, y - 30 - rnd(i) * 20, 710 + i, 1.4, soft); // reeds
    } else if (ch.id === 'frost') {
      if (i % 4 === 0) S.sLine(ctx, x, y + 10, x + 20, y + 12, 700 + i, 1, soft);
    } else {
      S.sLine(ctx, x, y, x - 3 + rnd(i) * 6, y - 8 - rnd(i + 1) * 10, 700 + i, 1.1, ch.id === 'night' || ch.id === 'star' ? 'rgba(200,190,255,0.35)' : ch.id === 'storm' ? 'rgba(215,225,245,0.4)' : 'rgba(40,80,30,0.6)');
    }
  }

  // trees for flower / night
  if (ch.id === 'garden') {
    for (let x = 20; x < W; x += 46) {
      S.sPoly(ctx, [x - 5, gy + 2, x - 5, gy - 44, x, gy - 52, x + 5, gy - 44, x + 5, gy + 2], 850 + x, true, '#d8c49a', 1.2, 0.8);
    }
    S.sLine(ctx, 0, gy - 30, W, gy - 30, 870, 1.6, soft, 3);
    S.sLine(ctx, 0, gy - 14, W, gy - 14, 871, 1.6, soft, 3);
  }
  if (ch.id === 'mushroom') {
    const xs = [W * 0.16, W * 0.84, W * 0.5];
    xs.forEach((x, k) => {
      const h = 34 + k * 6;
      S.sPoly(ctx, [x - 7, gy, x - 5, gy - h, x + 5, gy - h, x + 7, gy], 880 + k, true, '#f3e6c8', 1.3, 0.8);
      S.sPoly(ctx, [x - 26, gy - h + 4, x - 18, gy - h - 16, x, gy - h - 22, x + 18, gy - h - 16, x + 26, gy - h + 4], 885 + k, true, '#c8643a', 1.4, 1);
    });
  }
  if (ch.id === 'flower' || ch.id === 'night' || ch.id === 'water' || ch.id === 'mushroom') {
    const tx = [W * 0.06, W * 0.94];
    tx.forEach((x, k) => {
      S.sPoly(ctx, [x - 8, gy, x - 5, gy - 110, x + 5, gy - 110, x + 8, gy], 800 + k, true, '#8a6a4a', 1.5, 1.5);
      const leaf = ch.id === 'night' ? '#2f3a55' : ch.id === 'water' ? '#6fae7a' : ch.id === 'mushroom' ? '#d98a3a' : '#5ea34a';
      S.sCircle(ctx, x, gy - 140, 46, 810 + k, leaf, 1.6);
      S.sCircle(ctx, x - 26, gy - 115, 28, 820 + k, leaf, 1.3);
      S.sCircle(ctx, x + 26, gy - 118, 30, 830 + k, leaf, 1.3);
    });
  }
  S.freezeBoil(false);
}
