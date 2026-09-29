import { useCallback, useEffect, useRef, useState } from 'react';
import type { Arcade, ArcadeEvents } from './base';
import type { ChapterDef } from '../game/chapters';
import { sfx } from '../game/audio';
import { loadScores, saveScore, removeScore, type ScoreEntry } from '../game/scores';
import { loadPollen, savePollen, pollenFor, loadUpgrades } from '../game/shop';
import { FitCard, Portrait, ScoreTable, useViewport } from '../FairyBook';
import { yandex } from '../yandex';

export interface PartConfig {
  part: string;
  title: string;
  color: string;
  ch: ChapterDef;
  tagline: string;
  story: string;
  how: string[];
  scoreKey: string;
  col: string;
  fmt: (n: number) => string;
  overTitle: string;
  overText: (stat: number) => string;
  create: (canvas: HTMLCanvasElement, ev: ArcadeEvents) => Arcade;
}

type Screen = 'menu' | 'play' | 'paused' | 'over' | 'scores';

export default function ArcadeShell({ cfg, onExit }: { cfg: PartConfig; onExit: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const gameRef = useRef<Arcade | null>(null);
  const [screen, setScreen] = useState<Screen>('menu');
  const screenRef = useRef<Screen>('menu');
  const [scores, setScores] = useState<ScoreEntry[]>(() => loadScores(cfg.scoreKey));
  const [rank, setRank] = useState(-1);
  const [result, setResult] = useState({ score: 0, stat: 0 });
  const [muted, setMuted] = useState(sfx.muted);
  const [reviveUsed, setReviveUsed] = useState(false);
  const [adBusy, setAdBusy] = useState(false);
  const adBusyRef = useRef(false);
  const lastEntryRef = useRef(0);
  const runsRef = useRef(0);
  const grantedRef = useRef(0);
  const [pollen, setPollen] = useState(loadPollen);
  const [lastPollen, setLastPollen] = useState(0);
  const [doubled, setDoubled] = useState(false);
  const vp = useViewport();
  const wide = vp.w >= 640 && vp.w > vp.h * 1.2;
  const name = localStorage.getItem('fairy_name') || 'Фея';

  const go = useCallback((s: Screen) => {
    screenRef.current = s;
    setScreen(s);
    if (s === 'play') yandex.gameplayStart();
    else yandex.gameplayStop();
  }, []);

  const addPollen = useCallback((n: number) => {
    setPollen((v) => {
      const nv = Math.max(0, v + n);
      savePollen(nv);
      return nv;
    });
  }, []);

  useEffect(() => {
    const g = cfg.create(canvasRef.current!, {
      onGameOver: (score, stat) => {
        const entry: ScoreEntry = { name: name.slice(0, 14), score, chapter: stat, date: Date.now() };
        const [list, idx] = saveScore(entry, cfg.scoreKey);
        lastEntryRef.current = entry.date;
        setScores(list);
        setRank(idx);
        setResult({ score, stat });
        const gained = pollenFor(score - grantedRef.current, loadUpgrades().bag);
        grantedRef.current = score;
        addPollen(gained);
        setLastPollen(gained);
        setDoubled(false);
        go('over');
      },
    });
    gameRef.current = g;
    if (location.search.includes('fairytest')) (window as unknown as { __arcade: Arcade }).__arcade = g;
    return () => g.destroy();
  }, [cfg, go, name, addPollen]);

  const start = useCallback(async () => {
    if (adBusyRef.current) return;
    sfx.init();
    sfx.click();
    if (runsRef.current > 0) {
      adBusyRef.current = true;
      setAdBusy(true);
      await yandex.showFullscreen();
      adBusyRef.current = false;
      setAdBusy(false);
    }
    runsRef.current++;
    grantedRef.current = 0;
    setRank(-1);
    setReviveUsed(false);
    gameRef.current!.start();
    go('play');
  }, [go]);

  const rewarded = useCallback(async () => {
    if (adBusyRef.current) return false;
    adBusyRef.current = true;
    setAdBusy(true);
    const ok = await yandex.showRewarded();
    adBusyRef.current = false;
    setAdBusy(false);
    return ok;
  }, []);

  const continueForAd = useCallback(async () => {
    if (reviveUsed) return;
    if (!(await rewarded())) return;
    setReviveUsed(true);
    setScores(removeScore(lastEntryRef.current, cfg.scoreKey));
    setRank(-1);
    gameRef.current!.revive();
    go('play');
  }, [go, reviveUsed, rewarded, cfg.scoreKey]);

  const doublePollen = useCallback(async () => {
    if (doubled || lastPollen <= 0) return;
    if (!(await rewarded())) return;
    addPollen(lastPollen);
    setDoubled(true);
    sfx.bloom();
  }, [doubled, lastPollen, rewarded, addPollen]);

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
      else if (s === 'menu' && e.code === 'Escape') onExit();
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
    const off = yandex.onPause(pause);
    return () => {
      off();
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('blur', pause);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, [pause, resume, start, toggleMute, go, onExit]);

  const best = scores[0]?.score ?? 0;

  return (
    <div className="relative w-full h-full">
      <canvas ref={canvasRef} className="absolute inset-0" />
      <div className="absolute top-3 right-3 flex gap-2 z-10">
        <button className="sk-icon" onClick={toggleMute} aria-label="Звук">{muted ? '✕' : '♪'}</button>
        {screen === 'play' && <button className="sk-icon" onClick={pause} aria-label="Пауза">❚❚</button>}
      </div>

      {screen === 'menu' && (
        <FitCard maxW={wide ? 860 : 540} bg="rgba(239,232,216,0.28)" className="text-center">
          <div className={wide ? 'grid grid-cols-[1fr_1.2fr] gap-6 items-center' : ''}>
            <div>
              <p className="text-xl opacity-70 -mb-1">Мир Фей · {cfg.part}</p>
              <h1 className="text-5xl sm:text-6xl font-bold leading-none wobble inline-block" style={{ color: cfg.color }}>{cfg.title}</h1>
              <div className="flex justify-center my-1">
                <Portrait ch={cfg.ch} size={120} />
              </div>
              <p className="text-2xl leading-tight">{cfg.tagline}</p>
              {best > 0 && <p className="text-xl mt-1">Лучший результат: <b>{best}</b></p>}
            </div>
            <div>
              <p className="text-xl leading-snug text-left">{cfg.story}</p>
              <ul className="text-lg leading-snug text-left mt-2 list-none">
                {cfg.how.map((h, i) => (
                  <li key={i}>✎ {h}</li>
                ))}
              </ul>
              <div className="flex flex-wrap gap-3 justify-center mt-3">
                <button className="sk-btn primary text-3xl" disabled={adBusy} onClick={start}>Лететь! ➜</button>
                <button className="sk-btn text-xl" onClick={() => { sfx.click(); go('scores'); }}>Рекорды</button>
              </div>
              <button className="sk-btn text-xl mt-3" onClick={() => { sfx.click(); onExit(); }}>← К выбору части</button>
              <p className="text-base opacity-70 mt-2">Стрелки / WASD — полёт · Пробел — особое умение · Esc — пауза. На телефоне — веди пальцем, кнопка справа снизу.</p>
            </div>
          </div>
        </FitCard>
      )}

      {screen === 'paused' && (
        <FitCard maxW={380} bg="rgba(30,24,20,0.35)" className="text-center">
          <h2 className="text-6xl font-bold">Пауза</h2>
          <p className="text-2xl opacity-70 mb-4">Фея присела на листок отдохнуть…</p>
          <div className="flex flex-col gap-3">
            <button className="sk-btn primary" onClick={resume}>Продолжить</button>
            <button className="sk-btn" onClick={start}>Заново (R)</button>
            <button className="sk-btn" onClick={toMenu}>В меню</button>
          </div>
        </FitCard>
      )}

      {screen === 'over' && (
        <FitCard maxW={wide ? 760 : 480} bg="rgba(30,24,20,0.4)" className="text-center">
          <div className={wide ? 'grid grid-cols-2 gap-5 items-center' : ''}>
            <div>
              <p className="text-xl opacity-70">{cfg.part} · {cfg.title}</p>
              <h2 className="text-5xl font-bold leading-none" style={{ color: '#8a3b3b' }}>{cfg.overTitle}</h2>
              <p className="text-2xl mt-2">{cfg.overText(result.stat)}</p>
              <p className="text-5xl font-bold my-2">{result.score} очков</p>
              {rank === 0 && <p className="text-3xl wobble inline-block" style={{ color: '#c9446f' }}>✦ Новый рекорд! ✦</p>}
              {rank > 0 && <p className="text-2xl">Место в таблице: {rank + 1}</p>}
              <p className="text-xl mt-1" style={{ color: '#b08810' }}>
                +{doubled ? lastPollen * 2 : lastPollen} ✦ пыльцы {doubled && '(×2)'} · всего {pollen}
                <span className="block text-base opacity-80">тратится в «Лавке фей» (Часть I)</span>
              </p>
            </div>
            <div>
              <div className={'my-3 overflow-y-auto scroll-thin ' + (wide ? 'max-h-64' : 'max-h-44')}>
                <ScoreTable scores={scores} highlight={rank} col={cfg.col} fmt={cfg.fmt} />
              </div>
              {!reviveUsed && (
                <button className="sk-btn primary w-full mb-3" disabled={adBusy} onClick={continueForAd}>▶ Второй шанс за рекламу</button>
              )}
              {!doubled && lastPollen > 0 && (
                <button className="sk-btn w-full mb-3 text-xl" disabled={adBusy} onClick={doublePollen}>▶ Удвоить пыльцу за рекламу (+{lastPollen} ✦)</button>
              )}
              <div className="flex flex-wrap gap-3 justify-center">
                <button className="sk-btn" disabled={adBusy} onClick={start}>Ещё раз (R)</button>
                <button className="sk-btn" onClick={toMenu}>В меню</button>
              </div>
            </div>
          </div>
        </FitCard>
      )}

      {screen === 'scores' && (
        <FitCard maxW={480} bg="rgba(30,24,20,0.25)" className="text-center">
          <h2 className="text-5xl font-bold">Рекорды</h2>
          <p className="text-xl opacity-70 mb-2">{cfg.part} · {cfg.title}</p>
          <ScoreTable scores={scores} col={cfg.col} fmt={cfg.fmt} />
          <button className="sk-btn mt-4" onClick={() => { sfx.click(); go('menu'); }}>Назад</button>
        </FitCard>
      )}
    </div>
  );
}
