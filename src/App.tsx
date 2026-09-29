import { useEffect, useState } from 'react';
import { yandex } from './yandex';
import FairyBook, { Portrait } from './FairyBook';
import RunnerGame from './RunnerGame';
import ArcadeShell from './arcade/ArcadeShell';
import { PART_FIREFLIES, PART_JUMPER, PART_GUARD } from './arcade/parts';
import { CHAPTERS } from './game/chapters';
import { sfx } from './game/audio';
import { loadScores } from './game/scores';
import { loadPollen } from './game/shop';

type Mode = 'hub' | 'book' | 'runner' | 'p3' | 'p4' | 'p5';

const CARDS: { id: Mode; part: string; kind: string; title: string; desc: string; color: string; ch: number; key: string }[] = [
  { id: 'book', part: 'Часть I', kind: 'сюжетная', title: 'Книга Фей', desc: 'Девять глав, девять видов фей, у каждой своя история и квест. Лавка улучшений.', color: '#e86a92', ch: 0, key: 'fairy_book_scores_v1' },
  { id: 'runner', part: 'Часть II', kind: 'бесконечный полёт', title: 'Полёт над страницей', desc: 'Лети сквозь земли фей, собирай звёзды, уворачивайся от лоз и клякс.', color: '#3a8fd6', ch: 1, key: 'fairy_runner_scores_v1' },
  { id: 'p3', part: 'Часть III', kind: 'хоровод', title: 'Светлячковый хоровод', desc: 'Собери длинный хоровод светлячков и приведи его к Лунному фонарю.', color: '#7a6cd6', ch: 2, key: PART_FIREFLIES.scoreKey },
  { id: 'p4', part: 'Часть IV', kind: 'прыжки ввысь', title: 'Выше облаков', desc: 'Прыгай по облакам, листьям и грибам-батутам всё выше, к самой Луне.', color: '#f07a3a', ch: 6, key: PART_JUMPER.scoreKey },
  { id: 'p5', part: 'Часть V', kind: 'звёздная битва', title: 'Звёздная стража', desc: 'Отбивайся звёздной пыльцой от волн чернильных чудищ и Кракена.', color: '#e0a526', ch: 4, key: PART_GUARD.scoreKey },
];

export default function App() {
  const [mode, setMode] = useState<Mode>('hub');

  useEffect(() => {
    // Yandex SDK: инициализация и сигнал Game Ready после загрузки шрифтов
    const fonts = (document as Document & { fonts?: FontFaceSet }).fonts;
    Promise.all([yandex.init(), fonts ? fonts.ready : Promise.resolve()]).then(() => yandex.ready());
    const noMenu = (e: Event) => e.preventDefault();
    document.addEventListener('contextmenu', noMenu);
    return () => document.removeEventListener('contextmenu', noMenu);
  }, []);

  const pick = (m: Mode) => {
    sfx.init();
    sfx.click();
    setMode(m);
  };
  const back = () => setMode('hub');

  if (mode === 'book') return <FairyBook key="book" onExit={back} />;
  if (mode === 'runner') return <RunnerGame key="runner" onExit={back} />;
  if (mode === 'p3') return <ArcadeShell key="p3" cfg={PART_FIREFLIES} onExit={back} />;
  if (mode === 'p4') return <ArcadeShell key="p4" cfg={PART_JUMPER} onExit={back} />;
  if (mode === 'p5') return <ArcadeShell key="p5" cfg={PART_GUARD} onExit={back} />;

  const pollen = loadPollen();

  return (
    <div className="w-full h-full overflow-y-auto scroll-thin" style={{ background: 'radial-gradient(ellipse at center, #f7f1e3 40%, #e3d8bf 100%)' }}>
      <div className="min-h-full flex flex-col items-center justify-center px-3 py-4">
        <h1 className="text-5xl sm:text-7xl font-bold wobble inline-block leading-none" style={{ color: '#c9446f' }}>Мир Фей</h1>
        <p className="text-xl sm:text-2xl opacity-75">Пять карандашных сказок — выбери, какую рассказать</p>
        {pollen > 0 && <p className="text-xl mb-1" style={{ color: '#b08810' }}>✦ {pollen} пыльцы — копится во всех частях, тратится в «Лавке фей»</p>}
        <div className="flex flex-wrap justify-center gap-4 mt-2 max-w-[1100px]">
          {CARDS.map((c, i) => {
            const best = loadScores(c.key)[0]?.score ?? 0;
            return (
              <button
                key={c.id}
                className="sk-card pop-in hub-card text-left cursor-pointer"
                style={{ animationDelay: i * 0.06 + 's' }}
                onClick={() => pick(c.id)}
              >
                <div className="shrink-0">
                  <Portrait ch={CHAPTERS[c.ch]} size={84} />
                </div>
                <div className="min-w-0">
                  <p className="text-lg opacity-60 leading-none">{c.part} · {c.kind}</p>
                  <h2 className="text-3xl font-bold leading-none mt-0.5" style={{ color: c.color }}>{c.title}</h2>
                  <p className="text-lg leading-tight mt-1">{c.desc}</p>
                  {best > 0 && <p className="text-lg mt-0.5">Рекорд: <b>{best}</b></p>}
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
