// Лавка фей: улучшения за пыльцу или за рекламу. Пыльца начисляется за очки в конце забега.

export type UpgradeId = 'heart' | 'speed' | 'dash' | 'magnet' | 'shield' | 'bag';
export type Upgrades = Record<UpgradeId, number>;

export interface UpgradeDef {
  id: UpgradeId;
  icon: string;
  title: string;
  desc: string;
  max: number;
  prices: number[];
}

export const UPGRADES: UpgradeDef[] = [
  { id: 'heart', icon: '♥', title: 'Крепкое сердце', desc: '+1 сердце в начале забега (кроме «Одного пера»).', max: 2, prices: [350, 800] },
  { id: 'speed', icon: '➶', title: 'Быстрые крылья', desc: 'Полёт быстрее на 7% за уровень.', max: 3, prices: [150, 300, 550] },
  { id: 'dash', icon: '⚡', title: 'Лёгкий рывок', desc: 'Рывок перезаряжается на 12% быстрее.', max: 3, prices: [150, 320, 560] },
  { id: 'magnet', icon: '✧', title: 'Магнит', desc: 'Притягивает пыльцу, росу, звёзды, снежинки и солнца.', max: 3, prices: [120, 260, 450] },
  { id: 'shield', icon: '❀', title: 'Щит из лепестков', desc: 'В начале каждой главы — щит на один удар (кроме «Одного пера»).', max: 1, prices: [500] },
  { id: 'bag', icon: '✿', title: 'Волшебный мешочек', desc: '+25% пыльцы за каждый забег.', max: 3, prices: [200, 420, 750] },
];

export const EMPTY_UPGRADES: Upgrades = { heart: 0, speed: 0, dash: 0, magnet: 0, shield: 0, bag: 0 };

const UP_KEY = 'fairy_upgrades';
const POLLEN_KEY = 'fairy_pollen';
/** сколько очков стоит одна пылинка */
export const SCORE_PER_POLLEN = 40;

export function loadUpgrades(): Upgrades {
  try {
    const raw = JSON.parse(localStorage.getItem(UP_KEY) || '{}');
    const u = { ...EMPTY_UPGRADES };
    for (const d of UPGRADES) u[d.id] = Math.max(0, Math.min(d.max, Number(raw[d.id]) || 0));
    return u;
  } catch {
    return { ...EMPTY_UPGRADES };
  }
}
export function saveUpgrades(u: Upgrades) {
  try {
    localStorage.setItem(UP_KEY, JSON.stringify(u));
  } catch {
    /* ignore */
  }
}
export function loadPollen(): number {
  return Math.max(0, Math.floor(Number(localStorage.getItem(POLLEN_KEY)) || 0));
}
export function savePollen(n: number) {
  try {
    localStorage.setItem(POLLEN_KEY, String(Math.max(0, Math.floor(n))));
  } catch {
    /* ignore */
  }
}
export function priceOf(d: UpgradeDef, level: number): number | null {
  return level >= d.max ? null : d.prices[level];
}
/** пыльца за набранные очки с учётом «Волшебного мешочка» */
export function pollenFor(scoreDelta: number, bag: number): number {
  return Math.floor((Math.max(0, scoreDelta) / SCORE_PER_POLLEN) * (1 + 0.25 * bag));
}
