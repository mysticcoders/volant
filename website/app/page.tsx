'use client';

import Image from 'next/image';

import {
  ArrowUpRight,
  ArrowRight,
  Command,
  Clipboard,
  LockKeyhole,
  Zap,
  FileText,
  Code2,
  CornerDownLeft,
} from 'lucide-react';
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionContent,
} from '@/components/ui/accordion';

const questions = [
  [
    'Can I download Volant yet?',
    'Volant is in active development. There isn’t a packaged public release yet. Download details will be added here when the public release is ready.',
  ],
  [
    'What Mac do I need?',
    'Volant requires macOS 15 or later. Building from source requires Xcode 26.',
  ],
  [
    'Where does my data live?',
    'Notes are plain Markdown files on your Mac. Clipboard history is encrypted locally using a key stored in Keychain. Your configuration is a portable text file. Volant has no network entitlement; websites and Shortcuts you open can use their own network access.',
  ],
  [
    'Does it work with Shortcuts?',
    'Yes. You can configure quicklinks to run named Apple Shortcuts, including passing text. You set these up explicitly; Volant doesn’t automatically discover every app’s actions.',
  ],
  [
    'Is Volant open source?',
    'The repository is currently private. Public source availability has not been announced.',
  ],
];

function Brand() {
  return (
    <span className="brand">
      <Image unoptimized src="/favicon.svg" alt="" width="30" height="30" />
      volant<span className="brand-dot">.</span>
    </span>
  );
}

export default function Home() {
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <header id="top" className="nav wrap">
        <a href="#top" aria-label="Volant home">
          <Brand />
        </a>
        <nav aria-label="Main navigation">
          <a href="#notes">Live Notes</a>
          <a href="#features">The little things</a>
          <a href="#get" className="nav-source">
            Release status <ArrowUpRight size={14} />
          </a>
        </nav>
        <a className="button small" href="#get">
          Meet Volant <ArrowRight size={14} />
        </a>
      </header>
      <main id="main">
        <section className="hero wrap">
          <div className="hero-copy">
            <p className="eyebrow">
              <span className="status-dot" /> A SMALL UTILITY FOR YOUR MAC
            </p>
            <h1>
              A little less
              <br />
              friction.
              <br />
              <span>A lot more flow.</span>
            </h1>
            <p className="intro">
              Find your app. Catch a thought. Reuse that snippet.
              <br className="desktop-break" /> Volant keeps the little things
              one shortcut away.
            </p>
            <div className="hero-actions">
              <a href="#notes" className="button">
                Find your flow <ArrowRight size={17} />
              </a>
              <a href="#get" className="text-link">
                Release status <ArrowUpRight size={15} />
              </a>
            </div>
            <p className="availability">
              Made for macOS 15+ <span>·</span> Local first <span>·</span> In
              development
            </p>
          </div>
          <div className="hero-visual">
            <div className="orbit-label">
              <Command size={14} /> Less reaching. More doing.
            </div>
            <Image
              unoptimized
              className="app-preview"
              src="/images/live-notes.png"
              width="1120"
              height="1240"
              alt="Volant Live Notes editor showing Markdown and a Python code block with a local Auto language selector and Copy Code action."
            />
            <div className="preview-caption">
              <span className="tiny-line" /> Live Notes · current development
              preview
            </div>
          </div>
        </section>
        <div className="principles wrap">
          <span>
            <Command size={17} /> Keyboard first
          </span>
          <span>
            <LockKeyhole size={17} /> Local by design
          </span>
          <span>
            <FileText size={17} /> Plain Markdown
          </span>
          <span>
            <Code2 size={17} /> Local first
          </span>
        </div>
        <section className="notes-section wrap" id="notes">
          <div className="section-intro">
            <p className="eyebrow">01 / A PLACE FOR THE THOUGHT</p>
            <h2>
              Open. Write.
              <br />
              <span>Carry on.</span>
            </h2>
            <p>
              A note shouldn’t become another project. Bring up a quiet space,
              get it down, and get back to what you were doing.
            </p>
            <a className="text-link" href="#get">
              Get Volant <ArrowUpRight size={15} />
            </a>
          </div>
          <div className="notes-details">
            <article>
              <span className="detail-number">01</span>
              <div>
                <h3>Markdown that keeps up.</h3>
                <p>
                  Type a code fence and keep writing. Live mode styles your
                  Markdown as you go. Pick a language, or let Auto make a local
                  guess.
                </p>
                <div
                  className="code-sample"
                  aria-label="Example Markdown code fence"
                >
                  <code>
                    <span>```</span>python
                  </code>
                  <span className="code-tag">Auto · Python</span>
                </div>
              </div>
            </article>
            <article>
              <span className="detail-number">02</span>
              <div>
                <h3>The useful bits, within reach.</h3>
                <p>
                  Copy code without its fences. Pin the note you keep coming
                  back to. Search your notes without leaving the keyboard.
                </p>
                <div className="key-row">
                  <kbd>⌘</kbd>
                  <kbd>P</kbd>
                  <span>Find a note</span>
                  <kbd>⌘</kbd>
                  <kbd>K</kbd>
                  <span>Find an action</span>
                </div>
              </div>
            </article>
            <article>
              <span className="detail-number">03</span>
              <div>
                <h3>Your words. Your files.</h3>
                <p>
                  Ordinary .md files, right on your Mac. Open them in another
                  editor whenever you like.
                </p>
              </div>
            </article>
          </div>
        </section>
        <section className="features-section" id="features">
          <div className="wrap">
            <div className="features-heading">
              <div>
                <p className="eyebrow">02 / SMALL THINGS, HANDLED</p>
                <h2>
                  Less repeat.
                  <br />
                  <span>More rhythm.</span>
                </h2>
              </div>
              <p>
                The everyday helpers you reach for again and again, together in
                one small Mac utility.
              </p>
            </div>
            <div className="feature-grid">
              <article>
                <Zap />
                <h3>A faster way there.</h3>
                <p>
                  Launch apps with ranking that learns from your choices. Set an
                  app hotkey to bring it forward, then hide it when you’re done.
                </p>
                <div className="mini-search">
                  <span>
                    <Command size={16} /> sa
                  </span>
                  <span>
                    Safari <CornerDownLeft size={15} />
                  </span>
                </div>
              </article>
              <article>
                <Clipboard />
                <h3>Keep the good copies.</h3>
                <p>
                  A local, encrypted history for text and images. Choose how
                  many items to keep, with password-manager copies skipped.
                </p>
                <div className="retention">
                  <span>Clipboard history</span>
                  <strong>
                    500 <small>items by default</small>
                  </strong>
                </div>
              </article>
              <article>
                <FileText />
                <h3>Write it once.</h3>
                <p>
                  Reuse snippets with date and clipboard placeholders. Give your
                  favorite links an alias. Keep it all in portable text
                  configuration.
                </p>
                <div className="snippet">
                  <code>
                    Today’s update — <span>{'{date}'}</span>
                  </code>
                </div>
              </article>
            </div>
          </div>
        </section>
        <section className="philosophy wrap">
          <p className="eyebrow">03 / DELIBERATELY PERSONAL</p>
          <h2>
            Your Mac.
            <br />
            Your tools. <span>Your business.</span>
          </h2>
          <p>
            No account to create. No telemetry to turn off. Volant works
            locally, with readable files and a configuration you control.
          </p>
          <a href="#details" className="text-link">
            How your data stays local. <ArrowUpRight size={15} />
          </a>
        </section>
        <section className="faq wrap" id="details">
          <div>
            <p className="eyebrow">A FEW DETAILS</p>
            <h2>Good to know.</h2>
          </div>
          <Accordion>
            {questions.map(([q, a]) => (
              <AccordionItem key={q} value={q}>
                <AccordionTrigger>{q}</AccordionTrigger>
                <AccordionContent>
                  <p>{a}</p>
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </section>
        <section className="get wrap" id="get">
          <Image
            unoptimized
            src="/images/volant-icon.png"
            alt="Volant app icon"
            width="84"
            height="84"
          />
          <p className="eyebrow">A LITTLE SPACE IN YOUR WORKFLOW</p>
          <h2>Make room for Volant.</h2>
          <p>
            We’re building a calmer way to get the little things done.
            <br />
            The public release is on its way.
          </p>
          <a className="button" href="#get">
            View Volant on Release status <ArrowUpRight size={17} />
          </a>
          <span className="availability">
            In development · No public download yet
          </span>
        </section>
      </main>
      <footer className="wrap">
        <a href="#top" aria-label="Back to top">
          <Brand />
        </a>
        <span>
          Made by <a href="https://mysticcoders.com">Mystic Coders</a>.
        </span>
        <a href="#top">
          Back to top <ArrowUpRight size={12} />
        </a>
      </footer>
    </>
  );
}
