import { useCallback, useEffect, useRef, useState } from 'react';
import { Runner } from './game2/runner';
import { CHAPTERS } from './game/chapters';
import { sfx } from './game/audio';
import { loadScores, saveScore, removeScore, type ScoreEntry } from './game/scores';
import { yandex } from './yandex';
import { Portrait, ScoreTable } from './FairyBook';

const KEY = 'fairy_runner_scores_v1';
type Screen = 'menu' | 'play' | 'paused' | 'over' | 'scores';

export default function RunnerGame({ onExit }: { onExit: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const gameRef = useRef<Runner | null>(null);
  const [screen, setScreen] = useState<Screen>('menu');
  const screenRef = useRef<Screen>('menu');
  const [scores, setScores] = useState<ScoreEntry[]>(() => loadScores(KEY));
  const [rank, setRank] = useState(-1);
  const [result, setResult] = useState({ score: 0, meters: 0, biome: 0 });
  const [muted, setMuted] = useState(sfx.muted);
  const name = localStorage.getItem('fairy_name') || 'Фея';

  const [reviveUsed, setReviveUsed] = useState(false);
  const [adBusy, setAdBusy] = useState(false);
  const adBusyRef = useRef(false);
  const lastEntryRef = useRef(0);
  const runsRef = useRef(0);

  const go = useCallback((s: Screen) => {
    screenRef.current = s;
    setScreen(s);
    if (s === 'play') yandex.gameplayStart();
    else yandex.gameplayStop();
  }, []);

  useEffect(() => {
    const g = new Runner(canvasRef.current!, {
      onGameOver: (score, meters, biome) => {
        const entry: ScoreEntry = { name: name.slice(0, 14), score: Math.floor(score), chapter: meters, date: Date.now() };
        const [list, idx] = saveScore(entry, KEY);
        lastEntryRef.current = entry.date;
        setScores(list);
        setRank(idx);
        setResult({ score: Math.floor(score), meters, biome });
        go('over');
      },
    });
    gameRef.current = g;
    return () => g.destroy();
  }, [go, name]);

  const start = useCallback(async () => {
    if (adBusyRef.current) return;
    sfx.init();
    sfx.click();
    // полноэкранная реклама перед повторным забегом (не перед самым первым)
    if (runsRef.current > 0) {
      adBusyRef.current = true;
      setAdBusy(true);
      await yandex.showFullscreen();
      adBusyRef.current = false;
      setAdBusy(false);
    }
    runsRef.current++;
    setRank(-1);
    setReviveUsed(false);
    gameRef.current!.start();
    go('play');
  }, [go]);

  /** Реклама с вознаграждением: второй шанс с той же дистанции */
  const continueForAd = useCallback(async () => {
    if (adBusyRef.current || reviveUsed) return;
    adBusyRef.current = true;
    setAdBusy(true);
    const ok = await yandex.showRewarded();
    adBusyRef.current = false;
    setAdBusy(false);
    if (!ok) return;
    setReviveUsed(true);
    setScores(removeScore(lastEntryRef.current, KEY));
    setRank(-1);
    gameRef.current!.revive();
    go('play');
  }, [go, reviveUsed]);
  const pause = useCallback(() => {
    if (screenRef.current === 'play') {
      gameRef.current!.pause();
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
    gameRef.current!.toIdle();
    go('menu');
  }, [go]);
  const toggleMute = useCallback(() => {
    sfx.setMuted(!sfx.muted);
    setMuted(sfx.muted);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (adBusyRef.current) return;
      const s = screenRef.current;
      if (e.code === 'KeyM') toggleMute();
      if (s === 'play' && (e.code === 'Escape' || e.code === 'KeyP')) pause();
      else if (s === 'paused' && (e.code === 'Escape' || e.code === 'KeyP' || e.code === 'Enter')) resume();
      else if (s === 'menu' && e.code === 'Enter') start();
      else if (s === 'scores' && e.code === 'Escape') go('menu');
      if ((s === 'over' || s === 'paused') && e.code === 'KeyR') start();
      if (s === 'over' && (e.code === 'Enter' || e.code === 'Space')) {
        e.preventDefault();
        start();
      }
    };
    const onVis = () => document.hidden && pause();
    window.addEventListener('keydown', onKey);
    window.addEventListener('blur', pause);
    document.addEventListener('visibilitychange', onVis);
    const offPause = yandex.onPause(pause);
    return () => {
      offPause();
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('blur', pause);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [pause, resume, start, toggleMute, go]);

  const overlay = 'absolute inset-0 flex items-center justify-center p-3 sm:p-6';
  const card = 'sk-card pop-in w-full max-h-[94vh] overflow-y-auto scroll-thin px-5 py-4 sm:px-8 sm:py-6';
  const best = scores[0]?.score ?? 0;

  return (
    <div className="relative w-full h-full">
      <canvas ref={canvasRef} className="absolute inset-0" />
      <div className="absolute top-3 right-3 flex gap-2 z-10">
        <button className="sk-icon" onClick={toggleMute} aria-label="Звук">{muted ? '✕' : '♪'}</button>
        {screen === 'play' && <button className="sk-icon" onClick={pause} aria-label="Пауза">❚❚</button>}
      </div>

      {screen === 'menu' && (
        <div className={overlay} style={{ background: 'rgba(239,232,216,0.3)' }}>
          <div className={card + ' max-w-lg text-center'}>
            <p className="text-xl opacity-70 -mb-1">Книга Фей · часть вторая</p>
            <h1 className="text-5xl sm:text-6xl font-bold wobble inline-block" style={{ color: '#3a8fd6' }}>Полёт над страницей</h1>
            <p className="text-2xl mt-1 leading-tight">
              Король Теней пролил чернила на Книгу Фей! Лети без остановки через земли всех пяти фей, собирай звёзды и уворачивайся от колючих лоз и клякс.
            </p>
            <div className="flex justify-center my-1">
              <div className="wobble"><Portrait ch={CHAPTERS[1]} size={110} /></div>
            </div>
            {best > 0 && <p className="text-2xl mb-2">Лучший результат: <b>{best}</b></p>}
            <div className="flex flex-col sm:flex-row gap-3 justify-center">
              <button className="sk-btn primary" onClick={start}>Взлететь! ✦</button>
              <button className="sk-btn" onClick={() => { sfx.click(); go('scores'); }}>Рекорды</button>
            </div>
            <button className="sk-btn mt-3 text-xl" onClick={() => { sfx.click(); onExit(); }}>← К выбору игры</button>
            <div className="mt-4 text-lg sm:text-xl leading-snug opacity-80">
              <p><b>Клавиатура:</b> стрелки / WASD — полёт, Пробел — рывок сквозь всё, Esc — пауза</p>
              <p><b>Касание:</b> веди пальцем — полёт, «Рывок» или второй палец — рывок</p>
              <p>✎ Рывок сбивает кляксы и ос. Пролети впритык к лозе — получишь «Чуть-чуть!»</p>
            </div>
          </div>
        </div>
      )}

      {screen === 'paused' && (
        <div className={overlay} style={{ background: 'rgba(30,24,20,0.35)' }}>
          <div className={card + ' max-w-sm text-center'}>
            <h2 className="text-6xl font-bold">Пауза</h2>
            <p className="text-2xl opacity-70 mb-4">Страница замерла…</p>
            <div className="flex flex-col gap-3">
              <button className="sk-btn primary" onClick={resume}>Продолжить</button>
              <button className="sk-btn" onClick={start}>Заново (R)</button>
              <button className="sk-btn" onClick={toMenu}>В меню</button>
            </div>
          </div>
        </div>
      )}

      {screen === 'over' && (
        <div className={overlay} style={{ background: 'rgba(30,24,20,0.4)' }}>
          <div className={card + ' max-w-md text-center'}>
            <h2 className="text-5xl sm:text-6xl font-bold leading-none" style={{ color: '#8a3b3b' }}>Чернила победили…</h2>
            <p className="text-2xl mt-2">
              Пролетела {result.meters} м и добралась до земель: {CHAPTERS[result.biome % CHAPTERS.length].kind.toLowerCase()}.
            </p>
            <p className="text-5xl font-bold my-2">{result.score} очков</p>
            {rank === 0 && <p className="text-3xl wobble inline-block" style={{ color: '#c9446f' }}>✦ Новый рекорд! ✦</p>}
            {rank > 0 && <p className="text-2xl">Место в таблице: {rank + 1}</p>}
            <div className="my-3 max-h-56 overflow-y-auto scroll-thin">
              <ScoreTable scores={scores} highlight={rank} col="Метры" fmt={(n) => n + ' м'} />
            </div>
            {!reviveUsed && (
              <button className="sk-btn primary w-full mb-3" disabled={adBusy} onClick={continueForAd}>
                ▶ Второй шанс за рекламу
              </button>
            )}
            <div className="flex flex-col sm:flex-row gap-3 justify-center">
              <button className="sk-btn" disabled={adBusy} onClick={start}>Ещё раз (R)</button>
              <button className="sk-btn" onClick={toMenu}>В меню</button>
            </div>
          </div>
        </div>
      )}

      {screen === 'scores' && (
        <div className={overlay} style={{ background: 'rgba(30,24,20,0.25)' }}>
          <div className={card + ' max-w-md text-center'}>
            <h2 className="text-6xl font-bold">Рекорды полёта</h2>
            <ScoreTable scores={scores} col="Метры" fmt={(n) => n + ' м'} />
            <button className="sk-btn mt-4" onClick={() => { sfx.click(); go('menu'); }}>Назад</button>
          </div>
        </div>
      )}
    </div>
  );
}
