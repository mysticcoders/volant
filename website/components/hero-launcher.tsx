'use client';
// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import Image from 'next/image';
import { useEffect, useRef, useState } from 'react';
import examples from '@/lib/try-hero-examples.json';
import '@/app/try/try.css';

type Example = (typeof examples.examples)[number];
/** What the card shows: the prompt at rest, or an example being typed and then answered. */
type Shown = { example: Example | null; typed: number; settled: boolean };

const restDelay = 3200;
const typingDelay = 70;
const answerHold = 2600;

/** A fixed date for the label, so server and browser render the same text. */
function capturedLabel(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
}

/** Opens /try with what was typed, so the first keystroke carries over and the calculator starts at once. */
function handOff(text: string) {
  window.location.assign(text ? `/try?q=${encodeURIComponent(text.slice(0, 200))}` : '/try');
}

/** The homepage hero's launcher card: the /try card in plain HTML. At rest it shows the prompt;
 * after a pause it types one of three examples and shows the answer /try gave when it was captured
 * (lib/try-hero-examples.json, refreshed by every website build), then returns to the prompt. It
 * computes nothing. Clicking it, typing, or pressing Return hands over to /try. Under reduced
 * motion it stays on the prompt. `large` is the launcher-as-hero variant. */
export function HeroLauncher({ large = false }: { large?: boolean }) {
  const [shown, setShown] = useState<Shown>({ example: null, typed: 0, settled: false });
  const [paused, setPaused] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || paused) return;
    let index = 0, typed = 0, timer = 0;
    /** Rests on the prompt, types the next example, holds its answer, then clears to the prompt. */
    const step = () => {
      const example = examples.examples[index];
      if (typed < example.query.length) {
        typed += 1;
        setShown({ example, typed, settled: false });
        timer = window.setTimeout(step, typingDelay);
      } else if (typed === example.query.length) {
        typed += 1;
        setShown({ example, typed: example.query.length, settled: true });
        timer = window.setTimeout(step, answerHold);
      } else {
        setShown({ example: null, typed: 0, settled: false });
        index = (index + 1) % examples.examples.length;
        typed = 0;
        timer = window.setTimeout(step, restDelay);
      }
    };
    timer = window.setTimeout(step, restDelay);
    return () => window.clearTimeout(timer);
  }, [paused]);

  const { example, typed, settled } = shown;
  const prompt = 'Try Volant in your browser now…';

  return (
    <section className={`try-launcher hero-launcher${large ? ' hero-launcher-large' : ''}`} aria-label="Volant launcher demo">
      <div className="try-bar">
        <input
          ref={input}
          placeholder={paused ? prompt : ''}
          aria-label="Try Volant in your browser now"
          onFocus={() => setPaused(true)}
          onPointerDown={() => handOff('')}
          onInput={(event) => handOff(event.currentTarget.value)}
          onKeyDown={(event) => { if (event.key === 'Enter') handOff(event.currentTarget.value); }}
          spellCheck={false}
          autoComplete="off"
        />
        {!paused ? (
          <span className="hero-ghost" aria-hidden>
            {example ? example.query.slice(0, typed) : <span className="hero-placeholder">{prompt}</span>}
            {example && !settled ? <span className="hero-caret" /> : null}
          </span>
        ) : null}
      </div>
      <ul className="try-results" aria-hidden>
        {!paused && example && settled && example.kind === 'answer' ? (
          <li>
            <span className="try-row try-answer" aria-current>
              <span className="try-row-text">
                <span className="try-answer-result">{example.result}</span>
                <span className="try-subtitle">{example.query}{example.detail ? ` · ${example.detail}` : ''}</span>
              </span>
            </span>
          </li>
        ) : null}
        {!paused && example && settled && example.kind === 'rows' && example.rows
          ? example.rows.map((row, i) => (
              <li key={row.title}>
                <span className="try-row" aria-current={i === 0}>
                  <Image unoptimized src={example.icon ?? '/try/extensions/hackernews/icon.webp'} alt="" width={22} height={22} />
                  <span className="try-row-text">
                    <span className="try-title">{row.title}</span>
                    {row.subtitle ? <span className="try-subtitle">{row.subtitle}</span> : null}
                  </span>
                </span>
              </li>
            ))
          : null}
      </ul>
      <div className="try-footer">
        <span className="try-footer-note">
          {paused
            ? 'Start typing to try Volant in your browser'
            : `Real Volant code in your browser. Examples captured ${capturedLabel(examples.capturedAt)}${example?.kind === 'rows' ? ' from Hacker News sample data' : ''}.`}
        </span>
        <a className="hero-try-link" href="/try">Open the demo</a>
      </div>
    </section>
  );
}
