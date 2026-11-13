'use client';
// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import Image from 'next/image';
import { useEffect, useState } from 'react';
import recorded from '@/lib/try-hero-examples.json';
import '@/app/try/try.css';

type Row = { r?: string; s?: string; k?: string; e?: string; t?: string; b?: string[] };
type Extension = { name: string; placeholder: string; kind: string; icon?: string };
type Frame = [text: string, rows: number[], scope?: string];
type Capture = {
  capturedAt: string;
  extensions: Record<string, Extension>;
  rows: Row[];
  examples: { query: string; frames: Frame[] }[];
};

const capture = recorded as unknown as Capture;
const prompt = 'Try Volant in your browser now…';
const startDelay = 180;
const answerHold = 3750;
const extensionHold = 5000;
const fadeOut = 300;
const clearedRest = 1350;
const returnPause = 700;
const staticExample = capture.examples.find((example) => example.query === '5 km in miles') ?? capture.examples[0];

/** A fixed date for the label, so server and browser render the same text. */
function capturedLabel(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
}

/** Opens /try with what was typed, so the first keystroke carries over and the calculator starts at once. */
function handOff(text: string) {
  window.location.assign(text ? `/try?q=${encodeURIComponent(text.slice(0, 200))}` : '/try');
}

/** The pause before the keystrokes that turn `from` into `to`: 90–150 ms a character, about
 * 250 ms for the first character after a space, as a person types. */
function keystrokeDelay(from: string, to: string) {
  let delay = 0;
  for (let i = from.length; i < to.length; i++) delay += to[i - 1] === ' ' ? 230 + Math.random() * 40 : 90 + Math.random() * 60;
  return delay || 120;
}

/** An extension's icon, or the blank square /try draws when it has none. */
function Icon({ ext, size = 22 }: { ext?: Extension; size?: number }) {
  return ext?.icon ? <Image unoptimized src={ext.icon} alt="" width={size} height={size} /> : <span className="try-icon-blank" />;
}

/** One recorded row, drawn with /try's classes: a calculator answer, an extension command, or a
 * row from inside an extension. The first row is selected, as in /try. */
function RecordedRow({ row, selected }: { row: Row; selected: boolean }) {
  const ext = row.e ? capture.extensions[row.e] : undefined;
  if (row.r !== undefined) {
    return (
      <div className="try-row try-answer" aria-current={selected}>
        <span className="try-row-text">
          <span className="try-answer-result">{row.r}</span>
          <span className="try-subtitle">{row.s}</span>
        </span>
        {row.k ? <span className="try-kind">{row.k}</span> : null}
      </div>
    );
  }
  return (
    <div className="try-row" aria-current={selected}>
      <Icon ext={ext} />
      <span className="try-row-text">
        <span className="try-title">{row.t ?? ext?.name}</span>
        <span className="try-subtitle">{row.t ? row.s : ext?.placeholder}</span>
      </span>
      {row.t ? (row.b?.length ? <span className="try-badges">{row.b.map((b, i) => <span key={i} className="try-badge">{b}</span>)}</span> : null)
        : <span className="try-kind">{ext?.kind}</span>}
    </div>
  );
}

/** A recorded frame's rows. */
function FrameRows({ frame }: { frame: Frame | null }) {
  return (
    <ul className="try-results hero-results">
      {frame?.[1].map((index, i) => <li key={`${index}-${i}`}><RecordedRow row={capture.rows[index]} selected={i === 0} /></li>)}
    </ul>
  );
}

/** The field's overlay for a frame: the extension chip after Return, then the typed text or the
 * extension's own prompt, and a caret while typing. */
function FrameField({ frame, caret }: { frame: Frame; caret: boolean }) {
  const scope = frame[2] ? capture.extensions[frame[2]] : undefined;
  return (
    <span className="hero-ghost">
      {scope ? <span className="try-chip"><span>‹</span><Icon ext={scope} size={16} />{scope.name}</span> : null}
      <span className="hero-ghost-text">
        {frame[0] || (scope ? <span className="hero-placeholder">{scope.placeholder}</span> : null)}
        {caret ? <span className="hero-caret" /> : null}
      </span>
    </span>
  );
}

/** The homepage hero's launcher card, the /try card in plain HTML. It first paints like an empty
 * launcher: the prompt and an empty results area. After hydration it replays examples recorded
 * keystroke by keystroke from the code /try runs (lib/try-hero-examples.json, refreshed by every
 * website build): each character appears with a human cadence and the results change to what /try
 * showed for exactly that text, including nothing. The final frame holds (longer for the
 * extension's list), fades and clears like Escape, and after a rest on the prompt the next example
 * starts. It computes nothing. Focusing the field stops and clears the replay;
 * clicking the card or typing hands over to /try with what was typed. Under reduced motion there is
 * no replay: the CSS shows one example's final frame with a caption. */
export function HeroLauncher() {
  const [frame, setFrame] = useState<Frame | null>(null);
  const [caret, setCaret] = useState(false);
  const [stopped, setStopped] = useState(false);
  const [fading, setFading] = useState(false);

  useEffect(() => {
    if (stopped || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let example = 0, step = 0, timer = 0;
    /** Shows the next recorded frame and schedules the one after it; after the last one the card
     * fades, clears, and rests on the prompt before the next example. */
    const advance = () => {
      const { frames } = capture.examples[example];
      if (step < frames.length) {
        const current = frames[step];
        const next = frames[step + 1];
        setFrame(current);
        setCaret(!current[2] && step < frames.length - 1);
        step += 1;
        timer = window.setTimeout(advance, !next ? (current[2] ? extensionHold : answerHold) : next[2] ? returnPause : keystrokeDelay(current[0], next[0]));
      } else if (step === frames.length) {
        setFading(true);
        step += 1;
        timer = window.setTimeout(advance, fadeOut);
      } else {
        setFrame(null); setCaret(false); setFading(false);
        example = (example + 1) % capture.examples.length;
        step = 0;
        timer = window.setTimeout(advance, clearedRest);
      }
    };
    timer = window.setTimeout(advance, startDelay);
    return () => window.clearTimeout(timer);
  }, [stopped]);

  const shown = stopped ? null : frame;
  const staticFrame = staticExample.frames[staticExample.frames.length - 1];

  return (
    <section
      className="try-launcher hero-launcher"
      aria-label="Volant launcher demo"
      data-fading={fading && !stopped ? '' : undefined}
      onPointerDown={(event) => { if (!(event.target as Element).closest('a')) handOff(''); }}
    >
      <div className="try-bar">
        <input
          placeholder={prompt}
          className={shown ? 'hero-typing' : undefined}
          aria-label="Try Volant in your browser now"
          aria-describedby="hero-launcher-about"
          onFocus={() => { setStopped(true); setFrame(null); }}
          onInput={(event) => handOff(event.currentTarget.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') handOff(event.currentTarget.value); }}
          spellCheck={false}
          autoComplete="off"
        />
        <span className="hero-live" aria-hidden>{shown ? <FrameField frame={shown} caret={caret} /> : null}</span>
      </div>
      <div className="hero-live" aria-hidden><FrameRows frame={shown} /></div>
      <div className="hero-static">
        <FrameRows frame={staticFrame} />
        <p className="hero-static-caption">{`Recorded example: “${staticExample.query}”`}</p>
      </div>
      <div className="try-footer">
        <span className="try-footer-note" id="hero-launcher-about">
          {`Recorded from real Volant code, keystroke by keystroke. Examples captured ${capturedLabel(capture.capturedAt)}; Hacker News from sample data.`}
        </span>
        <a className="hero-try-link" href="/try">Open the demo</a>
      </div>
    </section>
  );
}
