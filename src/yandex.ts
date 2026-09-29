// Обёртка над Yandex Games SDK v2.
// На Яндекс Играх загружает /sdk.js (относительный путь — требование модерации).
// Локально SDK недоступен — все методы работают как безопасные заглушки.
import { sfx } from './game/audio';

/* eslint-disable @typescript-eslint/no-explicit-any */
type YSDK = any;
declare global {
  interface Window {
    YaGames?: { init: (opts?: object) => Promise<YSDK> };
  }
}

type Listener = () => void;

class Yandex {
  sdk: YSDK | null = null;
  available = false;
  adShowing = false;
  private readyPromise: Promise<void> | null = null;
  private pauseL = new Set<Listener>();
  private resumeL = new Set<Listener>();
  private gameplayOn = false;
  private readySent = false;
  private lastFullscreen = 0;

  init(): Promise<void> {
    if (this.readyPromise) return this.readyPromise;
    this.readyPromise = new Promise<void>((resolve) => {
      const done = () => resolve();
      const timeout = window.setTimeout(done, 4000);
      const script = document.createElement('script');
      script.src = '/sdk.js';
      script.async = true;
      script.onload = async () => {
        try {
          if (!window.YaGames) throw new Error('no YaGames');
          this.sdk = await window.YaGames.init();
          this.available = true;
          this.sdk.on?.('game_api_pause', () => this.emitPause());
          this.sdk.on?.('game_api_resume', () => this.emitResume());
        } catch (e) {
          console.info('[yandex] SDK недоступен, локальный режим', e);
        }
        clearTimeout(timeout);
        done();
      };
      script.onerror = () => {
        console.info('[yandex] /sdk.js не найден — локальный режим');
        clearTimeout(timeout);
        done();
      };
      document.head.appendChild(script);
    });
    return this.readyPromise;
  }

  /** Игра загружена и готова к взаимодействию */
  ready() {
    if (this.readySent) return;
    this.readySent = true;
    try {
      this.sdk?.features?.LoadingAPI?.ready();
    } catch {
      /* ignore */
    }
  }

  gameplayStart() {
    if (this.gameplayOn || this.adShowing) return;
    this.gameplayOn = true;
    try {
      this.sdk?.features?.GameplayAPI?.start();
    } catch {
      /* ignore */
    }
  }
  gameplayStop() {
    if (!this.gameplayOn) return;
    this.gameplayOn = false;
    try {
      this.sdk?.features?.GameplayAPI?.stop();
    } catch {
      /* ignore */
    }
  }

  onPause(cb: Listener) {
    this.pauseL.add(cb);
    return () => this.pauseL.delete(cb);
  }
  onResume(cb: Listener) {
    this.resumeL.add(cb);
    return () => this.resumeL.delete(cb);
  }
  private emitPause() {
    sfx.suspend(true);
    this.pauseL.forEach((f) => f());
  }
  private emitResume() {
    if (!this.adShowing) sfx.suspend(false);
    this.resumeL.forEach((f) => f());
  }

  private beginAd() {
    this.adShowing = true;
    this.gameplayStop();
    sfx.suspend(true);
  }
  private endAd() {
    this.adShowing = false;
    sfx.suspend(false);
  }

  /** Полноэкранная реклама между сессиями (частоту дополнительно ограничивает платформа) */
  showFullscreen(): Promise<boolean> {
    return new Promise((resolve) => {
      const sdk = this.sdk;
      if (!sdk?.adv || this.adShowing || Date.now() - this.lastFullscreen < 60000) return resolve(false);
      this.beginAd();
      let finished = false;
      const finish = (shown: boolean) => {
        if (finished) return;
        finished = true;
        if (shown) this.lastFullscreen = Date.now();
        this.endAd();
        resolve(shown);
      };
      try {
        sdk.adv.showFullscreenAdv({
          callbacks: {
            onClose: (wasShown: boolean) => finish(wasShown),
            onError: () => finish(false),
            onOffline: () => finish(false),
          },
        });
      } catch {
        finish(false);
      }
    });
  }

  /** Реклама с вознаграждением. Возвращает true, если награда засчитана. */
  showRewarded(): Promise<boolean> {
    return new Promise((resolve) => {
      const sdk = this.sdk;
      if (!sdk?.adv) {
        // Локальный режим: награда выдаётся сразу, чтобы можно было протестировать механику.
        resolve(true);
        return;
      }
      if (this.adShowing) return resolve(false);
      this.beginAd();
      let rewarded = false;
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        this.endAd();
        resolve(rewarded);
      };
      try {
        sdk.adv.showRewardedVideo({
          callbacks: {
            onRewarded: () => {
              rewarded = true;
            },
            onClose: () => finish(),
            onError: () => finish(),
          },
        });
      } catch {
        finish();
      }
    });
  }
}

export const yandex = new Yandex();
