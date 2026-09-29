import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { Game, type GameMode } from './game/engine';
import { CHAPTERS, type ChapterDef } from './game/chapters';
import { drawFairy } from './game/draw';
import { sfx } from './game/audio';
import { setBoil } from './game/sketch';
import { loadScores, saveScore, removeScore, type ScoreEntry } from './game/scores';
import { yandex } from './yandex';
import { UPGRADES, loadUpgrades, saveUpgrades, loadPollen, savePollen, priceOf, pollenFor, type Upgrades, type UpgradeId } from './game/shop';

type Screen = 'menu' | 'select' | 'story' | 'play' | 'paused' | 'over' | 'win' | 'result' | 'scores' | 'shop';

const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX'];
const NCH = CHAPTERS.length;
const UNLOCK_KEY = 'fairy_unlocked';

interface ModeDef {
  id: GameMode;
  icon: string;
  title: string;
  desc: string;
  key: string;
  col: string;
  fmt: (n: number) => string;
}
export const MODES: ModeDef[] = [
  { id: 'story', icon: '✎', title: 'Сказка', desc: 'Все девять глав подряд. После каждой главы +1 ♥.', key: 'fairy_book_scores_v1', col: 'Глав', fmt: (n) => n + '/' + NCH },
  { id: 'chapter', icon: '❧', title: 'Одна глава', desc: 'Любая открытая глава отдельно — побей свой рекорд.', key: 'fairy_book_chapter_v1', col: 'Глава', fmt: (n) => ROMAN[n] ?? '?' },
  { id: 'endless', icon: '∞', title: 'Бесконечная охота', desc: 'Глава без конца: враги всё злее, каждые 10 целей +1 ♥.', key: 'fairy_book_endless_v1', col: 'Глава', fmt: (n) => ROMAN[n] ?? '?' },
  { id: 'hard', icon: '✧', title: 'Одно перо', desc: 'Сказка с одним сердцем и без лечения. Очки ×2.', key: 'fairy_book_hard_v1', col: 'Глав', fmt: (n) => n + '/' + NCH },
];
const modeDef = (m: GameMode) => MODES.find((x) => x.id === m)!;

export function useViewport() {
  const [vp, setVp] = useState(() => ({ w: window.innerWidth, h: window.innerHeight }));
  useEffect(() => {
    const on = () => setVp({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener('resize', on);
    window.addEventListener('orientationchange', on);
    return () => {
      window.removeEventListener('resize', on);
      window.removeEventListener('orientationchange', on);
    };
  }, []);
  return vp;
}

/**
 * Карточка, которая всегда помещается в экран: ширина ограничена экраном,
 * а если содержимое выше экрана — карточка плавно уменьшается (scale).
 * Если уменьшать дальше некуда (< 55%) — появляется прокрутка.
 */
export function FitCard({ maxW, bg, className = '', children }: { maxW: number; bg: string; className?: string; children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState({ w: Math.min(maxW, window.innerWidth - 24), h: 0, s: 1 });

  useLayoutEffect(() => {
    const fit = () => {
      const o = outer.current;
      const i = inner.current;
      if (!o || !i) return;
      const pad = 12;
      const aw = o.clientWidth - pad * 2;
      const ah = o.clientHeight - pad * 2;
      const w = Math.min(maxW, aw);
      if (Math.abs(parseFloat(i.style.width) - w) > 0.5) i.style.width = w + 'px';
      const h = i.offsetHeight;
      const s = Math.max(0.5, Math.min(1, ah / Math.max(1, h)));
      setBox((b) => (Math.abs(b.w - w) < 0.5 && Math.abs(b.h - h) < 0.5 && Math.abs(b.s - s) < 0.005 ? b : { w, h, s }));
    };
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(inner.current!);
    ro.observe(outer.current!);
    return () => ro.disconnect();
  }, [maxW]);

  return (
    <div ref={outer} className="absolute inset-0 overflow-auto scroll-thin flex" style={{ background: bg }}>
      <div style={{ margin: 'auto', padding: 12, boxSizing: 'content-box', width: box.w * box.s, height: box.h ? box.h * box.s : undefined }}>
        <div ref={inner} style={{ width: box.w, transform: `scale(${box.s})`, transformOrigin: 'top left' }}>
          <div className={'sk-card pop-in w-full px-4 py-3 sm:px-8 sm:py-6 ' + className}>{children}</div>
        </div>
      </div>
    </div>
  );
}

export function Portrait({ ch, size = 150 }: { ch: ChapterDef; size?: number }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const c = ref.current!;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    c.width = size * dpr;
    c.height = size * dpr;
    const ctx = c.getContext('2d')!;
    let raf = 0;
    const loop = (now: number) => {
      const t = now / 1000;
      setBoil(t);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, c.width, c.height);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      // фея с крыльями, волосами и аксессуаром занимает ~52×54 единиц — вписываем целиком
      const sc = size / 60;
      drawFairy(ctx, size / 2 + 4 * sc, size / 2 + 4.5 * sc, t, ch, 1, sc, 0);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [ch, size]);
  return <canvas ref={ref} style={{ width: size, height: size }} />;
}

export function ScoreTable({ scores, highlight = -1, col = 'Глав', fmt = (n: number) => n + '/5' }: { scores: ScoreEntry[]; highlight?: number; col?: string; fmt?: (n: number) => string }) {
  if (!scores.length) return <p className="text-2xl opacity-70 text-center py-3">Пока пусто — стань первой легендой!</p>;
  return (
    <table className="w-full text-xl sm:text-2xl">
      <thead>
        <tr className="opacity-60 text-lg">
          <th className="text-left pl-2">#</th>
          <th className="text-left">Имя</th>
          <th className="text-center">{col}</th>
          <th className="text-right pr-2">Очки</th>
        </tr>
      </thead>
      <tbody>
        {scores.map((s, i) => (
          <tr key={s.date + '-' + i} className={i === highlight ? 'font-bold' : ''} style={i === highlight ? { background: 'rgba(232,106,146,0.22)' } : undefined}>
            <td className="pl-2">{i === 0 ? '♛' : i + 1}</td>
            <td className="truncate max-w-[9rem]">{s.name}</td>
            <td className="text-center">{fmt(s.chapter)}</td>
            <td className="text-right pr-2">{s.score}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function FairyBook({ onExit }: { onExit: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const gameRef = useRef<Game | null>(null);
  const [screen, setScreen] = useState<Screen>('menu');
  const screenRef = useRef<Screen>('menu');
  const [mode, setModeState] = useState<GameMode>('story');
  const modeRef = useRef<GameMode>('story');
  const [storyIdx, setStoryIdx] = useState(0);
  const storyIdxRef = useRef(0);
  const [prevClear, setPrevClear] = useState<{ idx: number; bonus: number; score: number } | null>(null);
  const [finalScore, setFinalScore] = useState(0);
  const [finalChapter, setFinalChapter] = useState(0);
  const [finalProgress, setFinalProgress] = useState(0);
  const [scores, setScores] = useState<ScoreEntry[]>(() => loadScores(modeDef('story').key));
  const [scoresTab, setScoresTab] = useState<GameMode>('story');
  const [rank, setRank] = useState(-1);
  const [name, setName] = useState(() => localStorage.getItem('fairy_name') || 'Фея');
  const nameRef = useRef(name);
  const [muted, setMuted] = useState(sfx.muted);
  const [unlocked, setUnlocked] = useState(() => Math.max(1, Math.min(NCH, parseInt(localStorage.getItem(UNLOCK_KEY) || '1', 10) || 1)));
  const vp = useViewport();
  const wide = vp.w >= 640 && vp.w > vp.h * 1.2;
  /** компактный текст: горизонтальный экран или маленький телефон */
  const small = wide || vp.w < 480 || vp.h < 600;

  const [pollen, setPollen] = useState(loadPollen);
  const [upgrades, setUpgrades] = useState<Upgrades>(loadUpgrades);
  const upgradesRef = useRef(upgrades);
  const grantedRef = useRef(0);
  const [lastPollen, setLastPollen] = useState(0);
  const [doubled, setDoubled] = useState(false);
  const [shopFlash, setShopFlash] = useState<UpgradeId | null>(null);
  const shopBackRef = useRef<Screen>('menu');
  const [reviveUsed, setReviveUsed] = useState(false);
  const [adBusy, setAdBusy] = useState(false);
  const adBusyRef = useRef(false);
  const lastEntryRef = useRef(0);

  const setMode = useCallback((m: GameMode) => {
    modeRef.current = m;
    setModeState(m);
  }, []);

  const go = useCallback((s: Screen) => {
    screenRef.current = s;
    setScreen(s);
    if (s === 'play') yandex.gameplayStart();
    else yandex.gameplayStop();
  }, []);

  const unlock = useCallback((n: number) => {
    setUnlocked((u) => {
      const v = Math.min(NCH, Math.max(u, n));
      localStorage.setItem(UNLOCK_KEY, String(v));
      return v;
    });
  }, []);

  /** Показывает полноэкранную рекламу (если платформа разрешит), затем выполняет действие */
  const withAd = useCallback(async (action: () => void) => {
    if (adBusyRef.current) return;
    adBusyRef.current = true;
    setAdBusy(true);
    await yandex.showFullscreen();
    adBusyRef.current = false;
    setAdBusy(false);
    action();
  }, []);

  useEffect(() => {
    nameRef.current = name;
    localStorage.setItem('fairy_name', name);
  }, [name]);

  const record = useCallback((score: number, chapter: number) => {
    const def = modeDef(modeRef.current);
    const entry: ScoreEntry = { name: (nameRef.current || 'Фея').slice(0, 14), score, chapter, date: Date.now() };
    const [list, idx] = saveScore(entry, def.key);
    lastEntryRef.current = entry.date;
    // пыльца за очки, набранные с прошлого начисления (после «второго шанса» — только прирост)
    const gained = pollenFor(score - grantedRef.current, upgradesRef.current.bag);
    grantedRef.current = score;
    setPollen((v) => {
      const nv = v + gained;
      savePollen(nv);
      return nv;
    });
    setLastPollen(gained);
    setDoubled(false);
    setScores(list);
    setScoresTab(def.id);
    setRank(idx);
    setFinalScore(score);
    setFinalChapter(chapter);
  }, []);

  useEffect(() => {
    const g = new Game(canvasRef.current!, {
      onChapterClear: (idx, bonus, score) => {
        const m = modeRef.current;
        unlock(idx + 2); // пройденная глава открывает следующую для режимов «Одна глава» и «Бесконечная охота»
        if (m === 'chapter') {
          record(score, idx);
          go('result');
          return;
        }
        if (idx >= CHAPTERS.length - 1) {
          record(score, CHAPTERS.length);
          go('win');
        } else {
          setPrevClear({ idx, bonus, score });
          storyIdxRef.current = idx + 1;
          setStoryIdx(idx + 1);
          g.preview(idx + 1);
          go('story');
        }
      },
      onGameOver: (score, ch) => {
        setFinalProgress(g.progress);
        record(score, ch);
        go('over');
      },
    });
    gameRef.current = g;
    g.upgrades = { ...upgradesRef.current };
    // доступ для автотестов: только с ?fairytest в адресе
    if (location.search.includes('fairytest')) (window as unknown as { __fairy: Game }).__fairy = g;
    return () => g.destroy();
  }, [go, record, unlock]);

  useEffect(() => {
    upgradesRef.current = upgrades;
    if (gameRef.current) gameRef.current.upgrades = { ...upgrades };
  }, [upgrades]);

  const addPollen = useCallback((n: number) => {
    setPollen((v) => {
      const nv = Math.max(0, v + n);
      savePollen(nv);
      return nv;
    });
  }, []);

  /** Покупка улучшения: за пыльцу или за рекламу с вознаграждением */
  const buyUpgrade = useCallback(
    async (id: UpgradeId, viaAd: boolean) => {
      if (adBusyRef.current) return;
      const def = UPGRADES.find((d) => d.id === id)!;
      const lvl = upgradesRef.current[id];
      const price = priceOf(def, lvl);
      if (price === null) return;
      if (viaAd) {
        adBusyRef.current = true;
        setAdBusy(true);
        const ok = await yandex.showRewarded();
        adBusyRef.current = false;
        setAdBusy(false);
        if (!ok) return;
      } else {
        if (loadPollen() < price) return;
        addPollen(-price);
      }
      const nu = { ...upgradesRef.current, [id]: lvl + 1 };
      upgradesRef.current = nu;
      saveUpgrades(nu);
      setUpgrades(nu);
      setShopFlash(id);
      window.setTimeout(() => setShopFlash(null), 600);
      sfx.bloom();
    },
    [addPollen],
  );

  /** Удвоить пыльцу за забег (реклама с вознаграждением) */
  const doublePollen = useCallback(async () => {
    if (adBusyRef.current || doubled || lastPollen <= 0) return;
    adBusyRef.current = true;
    setAdBusy(true);
    const ok = await yandex.showRewarded();
    adBusyRef.current = false;
    setAdBusy(false);
    if (!ok) return;
    addPollen(lastPollen);
    setDoubled(true);
    sfx.bloom();
  }, [addPollen, doubled, lastPollen]);

  const openShop = useCallback(() => {
    sfx.click();
    shopBackRef.current = screenRef.current;
    go('shop');
  }, [go]);
  const closeShop = useCallback(() => {
    sfx.click();
    go(shopBackRef.current);
  }, [go]);

  /** Выбор режима в меню */
  const chooseMode = useCallback(
    (m: GameMode) => {
      sfx.init();
      sfx.click();
      setMode(m);
      setReviveUsed(false);
      setPrevClear(null);
      grantedRef.current = 0;
      if (m === 'story' || m === 'hard') {
        const g = gameRef.current!;
        g.newRun(m);
        g.preview(0);
        storyIdxRef.current = 0;
        setStoryIdx(0);
        go('story');
      } else {
        go('select');
      }
    },
    [go, setMode],
  );

  /** Выбор главы (режимы «Одна глава» и «Бесконечная охота») */
  const pickChapter = useCallback(
    (idx: number) => {
      if (idx >= unlocked) return;
      sfx.click();
      const g = gameRef.current!;
      g.newRun(modeRef.current);
      g.preview(idx);
      storyIdxRef.current = idx;
      setStoryIdx(idx);
      setPrevClear(null);
      setReviveUsed(false);
      grantedRef.current = 0;
      go('story');
    },
    [go, unlocked],
  );

  const beginChapter = useCallback(() => {
    sfx.init();
    const run = () => {
      const g = gameRef.current!;
      if (modeRef.current === 'chapter' || modeRef.current === 'endless') g.newRun(modeRef.current);
      g.startChapter(storyIdxRef.current);
      setRank(-1);
      go('play');
    };
    // полноэкранная реклама — только в естественных паузах между сессиями
    const story = modeRef.current === 'story' || modeRef.current === 'hard';
    if (!story || storyIdxRef.current > 0) withAd(run);
    else run();
  }, [go, withAd]);

  const restart = useCallback(() => {
    sfx.init();
    withAd(() => {
      gameRef.current!.restart();
      grantedRef.current = 0;
      setRank(-1);
      setReviveUsed(false);
      setPrevClear(null);
      go('play');
    });
  }, [go, withAd]);

  const nextChapter = useCallback(() => {
    const n = storyIdxRef.current + 1;
    if (n < CHAPTERS.length) pickChapter(n);
  }, [pickChapter]);

  /** Реклама с вознаграждением: второй шанс в текущей главе */
  const continueForAd = useCallback(async () => {
    if (adBusyRef.current || reviveUsed) return;
    adBusyRef.current = true;
    setAdBusy(true);
    const ok = await yandex.showRewarded();
    adBusyRef.current = false;
    setAdBusy(false);
    if (!ok) return;
    setReviveUsed(true);
    setScores(removeScore(lastEntryRef.current, modeDef(modeRef.current).key));
    setRank(-1);
    gameRef.current!.revive();
    go('play');
  }, [go, reviveUsed]);

  const pause = useCallback(() => {
    const g = gameRef.current!;
    if (screenRef.current === 'play') {
      g.pause();
      go('paused');
    }
  }, [go]);
  const resume = useCallback(() => {
    if (screenRef.current === 'paused') {
      gameRef.current!.resume();
      go('play');
    }
  }, [go]);

  const toMenu = useCallback(() => {
    gameRef.current!.preview(0);
    go('menu');
  }, [go]);

  const toSelect = useCallback(() => {
    gameRef.current!.preview(storyIdxRef.current);
    go('select');
  }, [go]);

  const openScores = useCallback(
    (tab: GameMode) => {
      sfx.click();
      setScoresTab(tab);
      setScores(loadScores(modeDef(tab).key));
      setRank(-1);
      go('scores');
    },
    [go],
  );

  const toggleMute = useCallback(() => {
    sfx.setMuted(!sfx.muted);
    setMuted(sfx.muted);
  }, []);

  // клавиатура
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (adBusyRef.current) return;
      const s = screenRef.current;
      const inInput = (e.target as HTMLElement)?.tagName === 'INPUT';
      if (e.code === 'KeyM' && !inInput) toggleMute();
      if (s === 'play' && (e.code === 'Escape' || e.code === 'KeyP')) pause();
      else if (s === 'paused' && (e.code === 'Escape' || e.code === 'KeyP' || e.code === 'Enter')) resume();
      else if (s === 'story' && (e.code === 'Enter' || e.code === 'Space')) {
        e.preventDefault();
        beginChapter();
      } else if (s === 'story' && e.code === 'Escape') {
        if (modeRef.current === 'chapter' || modeRef.current === 'endless') toSelect();
        else toMenu();
      } else if (s === 'menu' && e.code === 'Enter' && !inInput) chooseMode('story');
      else if (s === 'select' && e.code === 'Escape') toMenu();
      else if (s === 'select' && /^Digit[1-5]$/.test(e.code)) pickChapter(parseInt(e.code.slice(5), 10) - 1);
      else if (s === 'result' && (e.code === 'Enter' || e.code === 'Space')) {
        e.preventDefault();
        if (storyIdxRef.current < CHAPTERS.length - 1) nextChapter();
        else restart();
      }
      if ((s === 'over' || s === 'win' || s === 'paused' || s === 'result') && e.code === 'KeyR') restart();
      if ((s === 'over' || s === 'win') && (e.code === 'Enter' || e.code === 'Space')) {
        e.preventDefault();
        restart();
      }
      if (s === 'scores' && e.code === 'Escape') go('menu');
      if (s === 'shop' && e.code === 'Escape') closeShop();
    };
    const onVis = () => {
      if (document.hidden) pause();
    };
    window.addEventListener('keydown', onKey);
    document.addEventListener('visibilitychange', onVis);
    window.addEventListener('blur', pause);
    const offPause = yandex.onPause(pause);
    return () => {
      offPause();
      window.removeEventListener('keydown', onKey);
      document.removeEventListener('visibilitychange', onVis);
      window.removeEventListener('blur', pause);
    };
  }, [pause, resume, beginChapter, chooseMode, pickChapter, nextChapter, restart, toggleMute, toMenu, toSelect, go, closeShop]);

  const ch = CHAPTERS[storyIdx];
  const md = modeDef(mode);
  const single = mode === 'chapter' || mode === 'endless';
  const DIM = 'rgba(30,24,20,0.25)';

  const storyText = (
    <>
      {ch.story.map((p, i) => (
        <p key={i} className={(small ? 'text-xl' : 'text-2xl') + ' leading-snug mt-2 first:mt-0'}>
          {p}
        </p>
      ))}
      <div className="mt-3 p-3 rounded-lg" style={{ background: 'rgba(255,255,255,0.55)', border: '2px dashed rgba(42,36,32,0.5)' }}>
        {mode === 'endless' ? (
          <>
            <p className={small ? 'text-xl' : 'text-2xl'}><b>Бесконечная охота:</b> цель не кончается — копи очки, пока есть сердца. Каждые 10 целей +1 ♥, а враги с каждой минутой злее.</p>
            <p className="text-lg opacity-80 mt-1">Как играть: {ch.quest}</p>
          </>
        ) : (
          <p className={small ? 'text-xl' : 'text-2xl'}><b>Задание:</b> {ch.quest}</p>
        )}
        {mode === 'hard' && <p className="text-lg mt-1" style={{ color: '#c8433b' }}>✧ Одно перо: одно сердце на всю сказку, очки ×2.</p>}
        <p className="text-lg opacity-80 mt-1">✎ {ch.hint}</p>
      </div>
    </>
  );

  const storyFooter = (
    <div className={'text-center ' + (wide ? 'mt-3' : 'mt-4')}>
      <div className="flex gap-3 justify-center items-center flex-wrap">
        {single && (
          <button className="sk-btn text-xl" onClick={toSelect}>
            ← Главы
          </button>
        )}
        <button className={'sk-btn primary ' + (small ? 'text-2xl' : 'text-3xl')} disabled={adBusy} onClick={beginChapter}>
          Лететь! ➜
        </button>
      </div>
      <p className="text-base opacity-60 mt-1 hidden sm:block">Enter / Пробел</p>
    </div>
  );

  const chapterHead = (
    <>
      <p className={(small ? 'text-xl' : 'text-2xl') + ' opacity-70'}>
        {ch.num} · {ch.kind}
        {mode !== 'story' && <span style={{ color: mode === 'hard' ? '#c8433b' : ch.colors.main }}> · {md.title}</span>}
      </p>
      <h2 className={(small ? 'text-4xl' : 'text-5xl') + ' font-bold leading-none'} style={{ color: ch.colors.main }}>
        {ch.title}
      </h2>
      <p className={small ? 'text-xl' : 'text-2xl'}>Героиня: фея {ch.name}</p>
    </>
  );

  return (
    <div className="relative w-full h-full">
      <canvas ref={canvasRef} className="absolute inset-0" />

      {/* кнопки справа сверху */}
      <div className="absolute top-3 right-3 flex gap-2 z-10">
        <button className="sk-icon" onClick={toggleMute} aria-label="Звук" title="Звук (M)">
          {muted ? '✕' : '♪'}
        </button>
        {screen === 'play' && (
          <button className="sk-icon" onClick={pause} aria-label="Пауза" title="Пауза (Esc)">
            ❚❚
          </button>
        )}
      </div>

      {screen === 'menu' && (
        <FitCard maxW={wide ? 860 : 540} bg="rgba(239,232,216,0.35)" className="text-center">
          <div className={wide ? 'grid grid-cols-[1fr_1.25fr] gap-6 items-center' : ''}>
            <div>
              <p className="text-xl opacity-70 -mb-1">карандашная сказка в девяти главах</p>
              <h1 className="text-6xl sm:text-7xl font-bold wobble inline-block" style={{ color: '#c9446f' }}>
                Книга Фей
              </h1>
              <div className="flex justify-center flex-wrap my-1 px-2">
                {CHAPTERS.map((c) => (
                  <div key={c.id} className="-mx-[11px] -my-1">
                    <Portrait ch={c} size={52} />
                  </div>
                ))}
              </div>
              <label className="block text-xl opacity-80">Как тебя зовут?</label>
              <input className="sk-input mb-2" value={name} maxLength={14} onChange={(e) => setName(e.target.value)} />
            </div>
            <div>
              <div className="grid grid-cols-2 gap-3 mt-2">
                {MODES.map((m) => (
                  <button key={m.id} className={'sk-btn mode-btn ' + (m.id === 'story' ? 'primary' : '')} onClick={() => chooseMode(m.id)}>
                    <span className="block text-3xl leading-none">
                      <span className="opacity-70 mr-1">{m.icon}</span>
                      {m.title}
                    </span>
                    <span className="block text-base font-semibold opacity-75 leading-tight mt-1">{m.desc}</span>
                  </button>
                ))}
              </div>
              <div className="flex gap-3 justify-center mt-3 flex-wrap">
                <button className="sk-btn primary text-xl" onClick={openShop}>
                  Лавка фей · ✦ {pollen}
                </button>
                <button className="sk-btn text-xl" onClick={() => openScores('story')}>
                  Рекорды
                </button>
                <button className="sk-btn text-xl" onClick={() => { sfx.click(); onExit(); }}>
                  ← К выбору игры
                </button>
              </div>
              <div className="mt-3 text-lg leading-snug opacity-80">
                <p><b>Клавиатура:</b> стрелки / WASD — полёт, Пробел / Shift — рывок, Esc — пауза, R — заново</p>
                <p><b>Касание:</b> веди пальцем — полёт, «Рывок» или второй палец — рывок</p>
              </div>
            </div>
          </div>
        </FitCard>
      )}

      {screen === 'select' && (
        <FitCard maxW={wide ? 900 : 560} bg={DIM} className="text-center">
          <p className="text-xl opacity-70">{md.icon} {md.title}</p>
          <h2 className="text-5xl font-bold leading-none mb-1">Выбери главу</h2>
          <p className="text-lg opacity-75 mb-3">{md.desc} Новые главы открываются по мере прохождения.</p>
          <div className={'grid gap-3 ' + (wide ? 'grid-cols-5' : 'grid-cols-2 sm:grid-cols-3')}>
            {CHAPTERS.map((c, i) => {
              const locked = i >= unlocked;
              const best = loadScores(md.key).filter((s) => s.chapter === i)[0]?.score;
              return (
                <button key={c.id} className={'sk-btn chapter-btn ' + (locked ? 'locked' : '')} disabled={locked} onClick={() => pickChapter(i)}>
                  <div className="flex justify-center -my-2">
                    <Portrait ch={c} size={64} />
                  </div>
                  <span className="block text-base opacity-70">{c.num}</span>
                  <span className="block text-xl leading-tight" style={{ color: locked ? undefined : c.colors.main }}>
                    {c.title}
                  </span>
                  <span className="block text-base opacity-70 mt-0.5">{locked ? '🔒 пройди предыдущую' : best ? `рекорд ${best}` : c.kind}</span>
                </button>
              );
            })}
          </div>
          <div className="flex gap-3 justify-center mt-4 flex-wrap">
            <button className="sk-btn text-xl" onClick={() => openScores(mode)}>
              Рекорды режима
            </button>
            <button className="sk-btn text-xl" onClick={toMenu}>
              ← В меню
            </button>
          </div>
        </FitCard>
      )}

      {screen === 'story' && (
        <FitCard key={storyIdx + mode} maxW={wide ? 980 : 680} bg={DIM}>
          {prevClear && (
            <div className="text-center mb-2 pb-2 border-b-2 border-dashed border-[#2a2420]/40">
              <p className={(small ? 'text-xl' : 'text-2xl') + ' italic'}>«{CHAPTERS[prevClear.idx].outro}»</p>
              <p className="text-lg opacity-80">
                Бонус за главу: +{prevClear.bonus} · Всего очков: {prevClear.score}
                {mode === 'story' ? ' · +1 ♥' : ''}
              </p>
            </div>
          )}
          {wide ? (
            <div className="grid grid-cols-[minmax(0,0.8fr)_minmax(0,2fr)] gap-5 items-center">
              <div className="text-center">
                <div className="flex justify-center wobble">
                  <Portrait ch={ch} size={110} />
                </div>
                {chapterHead}
              </div>
              <div>
                {storyText}
                {storyFooter}
              </div>
            </div>
          ) : (
            <>
              <div className="flex flex-col sm:flex-row items-center gap-2 sm:gap-4 mb-2">
                <div className="shrink-0 wobble">
                  <Portrait ch={ch} size={small ? 84 : 110} />
                </div>
                <div className="text-center sm:text-left">{chapterHead}</div>
              </div>
              {storyText}
              {storyFooter}
            </>
          )}
        </FitCard>
      )}

      {screen === 'paused' && (
        <FitCard maxW={380} bg="rgba(30,24,20,0.35)" className="text-center">
          <h2 className="text-6xl font-bold">Пауза</h2>
          <p className="text-2xl opacity-70 mb-4">Фея присела на листок отдохнуть…</p>
          <div className="flex flex-col gap-3">
            <button className="sk-btn primary" onClick={resume}>Продолжить</button>
            <button className="sk-btn" onClick={restart}>Заново (R)</button>
            {single && <button className="sk-btn" onClick={toSelect}>К главам</button>}
            <button className="sk-btn" onClick={toMenu}>В меню</button>
          </div>
        </FitCard>
      )}

      {(screen === 'over' || screen === 'win' || screen === 'result') && (
        <FitCard maxW={wide ? 760 : 480} bg={screen === 'over' ? 'rgba(30,24,20,0.4)' : 'rgba(255,240,200,0.3)'} className="text-center">
          <div className={wide ? 'grid grid-cols-2 gap-5 items-center' : ''}>
            <div>
              <p className="text-xl opacity-70">{md.icon} {md.title}</p>
              <h2 className="text-5xl sm:text-6xl font-bold leading-none" style={{ color: screen === 'over' ? '#8a3b3b' : screen === 'win' ? '#e0a526' : ch.colors.main }}>
                {screen === 'win'
                  ? 'И жили они долго и счастливо!'
                  : screen === 'result'
                    ? 'Глава пройдена!'
                    : mode === 'endless'
                      ? 'Охота окончена!'
                      : mode === 'chapter'
                        ? 'Глава не удалась…'
                        : 'Сказка оборвалась…'}
              </h2>
              <p className="text-2xl mt-2">
                {screen === 'win'
                  ? mode === 'hard'
                    ? 'Все девять фей спасены — и всего с одним пером! Легенда.'
                    : 'Все девять фей спасены, а последний осколок тени погас.'
                  : screen === 'result'
                    ? `${ch.num} · ${ch.title}. ${ch.outro}`
                    : mode === 'endless'
                      ? `${ch.kind}: ${ch.goalLabel.toLowerCase()} — ${finalProgress}. Враги оказались сильнее… пока что.`
                      : mode === 'chapter'
                        ? `${ch.num} · ${ch.title}. Попробуй ещё раз!`
                        : `Пройдено глав: ${finalChapter} из ${NCH}. Но любую сказку можно рассказать заново.`}
              </p>
              <p className="text-5xl font-bold my-2">{finalScore} очков</p>
              {rank === 0 && <p className="text-3xl wobble inline-block" style={{ color: '#c9446f' }}>✦ Новый рекорд! ✦</p>}
              {rank > 0 && <p className="text-2xl">Место в таблице: {rank + 1}</p>}
              <p className="text-2xl mt-1" style={{ color: '#b08810' }}>
                +{doubled ? lastPollen * 2 : lastPollen} ✦ пыльцы {doubled && '(×2)'} · всего {pollen}
              </p>
            </div>
            <div>
              <div className={'my-3 overflow-y-auto scroll-thin ' + (wide ? 'max-h-64' : 'max-h-48')}>
                <ScoreTable scores={scores} highlight={rank} col={md.col} fmt={md.fmt} />
              </div>
              {screen === 'over' && !reviveUsed && (
                <button className="sk-btn primary w-full mb-3" disabled={adBusy} onClick={continueForAd}>
                  ▶ {mode === 'endless' ? 'Продолжить охоту' : 'Продолжить главу'} за рекламу
                </button>
              )}
              {screen === 'result' && storyIdx < CHAPTERS.length - 1 && (
                <button className="sk-btn primary w-full mb-3" disabled={adBusy} onClick={nextChapter}>
                  Следующая глава ➜
                </button>
              )}
              {!doubled && lastPollen > 0 && (
                <button className="sk-btn w-full mb-3 text-xl" disabled={adBusy} onClick={doublePollen}>
                  ▶ Удвоить пыльцу за рекламу (+{lastPollen} ✦)
                </button>
              )}
              <div className="flex gap-3 justify-center flex-wrap">
                <button className="sk-btn" disabled={adBusy} onClick={restart}>Ещё раз (R)</button>
                {single && <button className="sk-btn" onClick={toSelect}>Главы</button>}
                <button className="sk-btn" onClick={openShop}>Лавка</button>
                <button className="sk-btn" onClick={toMenu}>В меню</button>
              </div>
            </div>
          </div>
        </FitCard>
      )}

      {screen === 'shop' && (
        <FitCard maxW={wide ? 940 : 560} bg="rgba(30,24,20,0.3)" className="text-center">
          <h2 className="text-6xl font-bold leading-none" style={{ color: '#b08810' }}>
            Лавка фей
          </h2>
          {!small && <p className="text-xl opacity-75">Пыльца даётся за очки в конце каждого забега. Улучшения работают во всех режимах.</p>}
          <p className={(small ? 'text-3xl my-1' : 'text-4xl my-2') + ' font-bold'} style={{ color: '#b08810' }}>
            ✦ {pollen} пыльцы
          </p>
          <div className={'grid ' + (wide ? 'grid-cols-3 ' : 'grid-cols-2 ') + (small ? 'gap-2' : 'gap-3')}>
            {UPGRADES.map((d) => {
              const lvl = upgrades[d.id];
              const price = priceOf(d, lvl);
              const maxed = price === null;
              return (
                <div key={d.id} className={'shop-item ' + (shopFlash === d.id ? 'bought' : '')}>
                  <div className="flex items-center gap-2">
                    <span className={(small ? 'text-3xl w-7' : 'text-4xl w-10') + ' leading-none shrink-0'}>{d.icon}</span>
                    <div className="text-left">
                      <p className={(small ? 'text-xl' : 'text-2xl') + ' font-bold leading-none'}>{d.title}</p>
                      <p className="text-lg tracking-widest" style={{ color: '#b08810' }}>
                        {Array.from({ length: d.max }, (_, i) => (i < lvl ? '●' : '○')).join(' ')}
                      </p>
                    </div>
                  </div>
                  <p className={(small ? 'text-base' : 'text-lg') + ' leading-tight text-left opacity-80 mt-1 flex-1'}>{d.desc}</p>
                  {maxed ? (
                    <p className="text-xl font-bold mt-2" style={{ color: '#5c9e3a' }}>✓ Максимум</p>
                  ) : (
                    <div className={'flex gap-2 mt-2 ' + (small && !wide ? 'flex-col' : '')}>
                      <button className="sk-btn text-lg flex-1 !px-2" disabled={adBusy || pollen < price} onClick={() => buyUpgrade(d.id, false)}>
                        ✦ {price}
                      </button>
                      <button className="sk-btn primary text-lg flex-1 !px-2" disabled={adBusy} onClick={() => buyUpgrade(d.id, true)}>
                        ▶ Реклама
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
          <button className="sk-btn mt-4" onClick={closeShop}>
            ← Назад
          </button>
        </FitCard>
      )}

      {screen === 'scores' && (
        <FitCard maxW={520} bg={DIM} className="text-center">
          <h2 className="text-6xl font-bold">Рекорды</h2>
          <p className="text-xl opacity-70 mb-2">Летопись самых храбрых фей</p>
          <div className="flex flex-wrap justify-center gap-2 mb-3">
            {MODES.map((m) => (
              <button key={m.id} className={'sk-tab ' + (scoresTab === m.id ? 'active' : '')} onClick={() => openScores(m.id)}>
                {m.icon} {m.title}
              </button>
            ))}
          </div>
          <ScoreTable scores={scores} col={modeDef(scoresTab).col} fmt={modeDef(scoresTab).fmt} />
          <button className="sk-btn mt-4" onClick={() => { sfx.click(); go('menu'); }}>
            Назад
          </button>
        </FitCard>
      )}
    </div>
  );
}
