export interface ScoreEntry {
  name: string;
  score: number;
  chapter: number; // game 1: chapters completed; game 2: distance in meters
  date: number;
}

const DEFAULT_KEY = 'fairy_book_scores_v1';

export function loadScores(key = DEFAULT_KEY): ScoreEntry[] {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    const arr = JSON.parse(raw) as ScoreEntry[];
    return Array.isArray(arr) ? arr : [];
  } catch {
    return [];
  }
}

export function removeScore(date: number, key = DEFAULT_KEY): ScoreEntry[] {
  const list = loadScores(key).filter((e) => e.date !== date);
  try {
    localStorage.setItem(key, JSON.stringify(list));
  } catch {
    /* ignore */
  }
  return list;
}

/** saves and returns [list, index of new entry or -1] */
export function saveScore(e: ScoreEntry, key = DEFAULT_KEY): [ScoreEntry[], number] {
  const list = loadScores(key);
  list.push(e);
  list.sort((a, b) => b.score - a.score);
  const top = list.slice(0, 10);
  try {
    localStorage.setItem(key, JSON.stringify(top));
  } catch {
    /* ignore */
  }
  return [top, top.indexOf(e)];
}
