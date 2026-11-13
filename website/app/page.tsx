'use client';
// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import Image from 'next/image';
import { useState } from 'react';
import { HeroLauncher } from '@/components/hero-launcher';
import { AppearanceButton } from '@/components/site-shell';
import {
  ArrowRight,
  ArrowUpRight,
  Search,
  Calculator,
  Clipboard,
  Target,
  FileText,
  Code2,
  SlidersHorizontal,
  Check,
} from 'lucide-react';
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionContent,
} from '@/components/ui/accordion';
import {
  SiteFooter,
  SiteHeader,
  downloadURL,
  appVersion,
  repositoryURL,
} from '@/components/site-chrome';
import './home.css';

const questions = [
  [
    'Can I download Volant yet?',
    'Yes. Download the macOS disk image, open it, and drag Volant into Applications, or install it with Homebrew: brew install --cask mysticcoders/tap/volant. This is an early release, signed with Developer ID and notarized by Apple. Volant includes Check for Updates in its menu.',
  ],
  [
    'What Mac do I need?',
    'Volant requires macOS 15 or later on a Mac with Apple silicon.',
  ],
  [
    'Where does my data live?',
    'Notes are plain Markdown files on your Mac, or in your own iCloud Drive when you turn on iCloud sync. Clipboard history is encrypted locally with a Keychain key. You choose what to attach to AI prompts; cloud providers receive the messages you send. Updates, optional AI connections, and exchange rates use separate helpers. Opt-in iCloud sync carries selected settings and your notes between your Macs and excludes clipboard history and keys.',
  ],
  [
    'Are all the features here in the download?',
    `Yes. Everything on this page is in the current download, Volant ${appVersion}, including Focus with app and website blocking, Breaks, the expanded calculator, color themes and theme import, the system commands, and iCloud settings sync.`,
  ],
  [
    'Does it work with Shortcuts?',
    'Yes. You can configure quicklinks to run named Apple Shortcuts, including passing text. You set these up explicitly; Volant doesn’t automatically discover every app’s actions.',
  ],
  [
    'Is Volant open source?',
    'Yes. Volant is open source under the MIT license. You can read the code, report issues, and contribute on GitHub.',
  ],
];

const benefits = [
  {
    id: 'launcher',
    icon: Search,
    title: 'Get there without the detour.',
    text: 'Find apps, files, and contacts. Join your next meeting. Keep the keyboard, lose the hunt.',
    link: '/docs/launcher',
    label: 'Explore the launcher',
  },
  {
    id: 'answers',
    icon: Calculator,
    title: 'An answer. Then back to work.',
    text: 'Calculate, convert units and currencies, or check a time zone right where you search.',
    link: '/docs/calculator',
    label: 'Explore the calculator',
  },
  {
    id: 'notes',
    icon: Clipboard,
    title: 'Keep the useful bits close.',
    text: 'Find that thing you copied. Jot down a Markdown note. Reuse a snippet instead of typing it again.',
    link: '/docs/clipboard-and-snippets',
    label: 'Explore clipboard & snippets',
  },
  {
    id: 'focus',
    icon: Target,
    title: 'Keep distractions out of reach.',
    text: 'New in 0.4.0: Focus hides distracting apps and blanks blocked sites in Safari, Chrome, Brave and Vivaldi. Breaks reminds you to step away.',
    link: '/docs/focus-and-breaks',
    label: 'Explore Focus & Breaks',
  },
];

/** The homepage: the headline, intro and Download above the in-browser launcher card. */
export default function Home() {
  const [appearance, setAppearance] = useState('system');
  return (
    <div className="home-refresh" data-theme={appearance}>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <SiteHeader>
        <AppearanceButton value={appearance} onChange={setAppearance} />
      </SiteHeader>
      <main id="main">
        <section className="home-hero wrap home-hero-try">
          <div className="home-hero-copy">
            <a className="home-announce" href="/iphone">
              Volant for iPhone is in public beta <ArrowRight size={14} />
            </a>
            <p className="home-kicker">
              A LITTLE LESS FRICTION. A LOT MORE FLOW.
            </p>
            <h1>
              Less clicking.
              <br />
              More <em>doing.</em>
            </h1>
            <p className="home-intro">
              Launch apps, find what you copied, get quick answers, and reach
              your AI agents. One native Mac launcher. One shortcut to keep
              moving.
            </p>
            <div className="home-actions">
              <a className="button" href={downloadURL} download>
                Download for Mac <ArrowRight size={18} />
              </a>
              <a className="home-secondary" href="/try">
                Try it now <ArrowUpRight size={16} />
              </a>
            </div>
            <p className="home-requirements">
              Free & open source · macOS 15+ · Apple silicon
            </p>
          </div>
          <HeroLauncher />
        </section>
        <div className="home-proof wrap">
          <span>
            <Check size={15} /> Native to your Mac
          </span>
          <span>
            <Check size={15} /> No Volant account
          </span>
          <span>
            <Check size={15} /> No telemetry
          </span>
          <a href={repositoryURL}>
            Open source. MIT licensed. <ArrowUpRight size={14} />
          </a>
        </div>
        <section
          className="home-benefits wrap"
          id="features"
          aria-labelledby="benefits-title"
        >
          <div className="home-section-heading">
            <p className="home-kicker">SMALL TASKS. FEWER INTERRUPTIONS.</p>
            <h2 id="benefits-title">Stay with what you’re doing.</h2>
          </div>
          <div className="home-benefit-grid">
            {benefits.map(({ id, icon: Icon, title, text, link, label }) => (
              <article id={id} key={id}>
                <Icon size={24} aria-hidden="true" />
                <h3>{title}</h3>
                <p>{text}</p>
                <a href={link}>
                  {label} <ArrowUpRight size={15} />
                </a>
              </article>
            ))}
          </div>
        </section>
        <section
          className="home-agents wrap"
          id="agents"
          aria-labelledby="agents-title"
        >
          <div>
            <p className="home-kicker">FOR THE WAY YOU WORK NOW</p>
            <h2 id="agents-title">
              Your agents need you.
              <br />
              <em>Skip the tab hunt.</em>
            </h2>
            <p>
              Find the session waiting for a decision. Jump to a Rex pane,
              answer supported Herdr questions, or open a native AI conversation
              without leaving your flow.
            </p>
            <a href="/docs/agents">
              Meet your agent workspace <ArrowUpRight size={16} />
            </a>
            <p className="home-fineprint">
              Uses your installed agents and integrations. Cloud chat uses your
              chosen provider; local model servers are supported too.
            </p>
          </div>
          <figure>
            <a
              href="/images/agent-attention-dark.png"
              aria-label="View the full-size native agent question"
            >
              <Image
                unoptimized
                src="/images/agent-attention-dark.png"
                alt="Native Volant showing a fictional Codex question waiting for a decision."
                width={1500}
                height={960}
              />
            </a>
            <figcaption>
              Native development capture · fictional question
            </figcaption>
          </figure>
        </section>
        <section
          className="home-more wrap"
          aria-label="More ways to use Volant"
        >
          <a href="/docs/notes">
            <FileText size={20} />
            <span>
              <strong>Think in Markdown.</strong> Notes that stay ordinary
              files.
            </span>
            <ArrowUpRight size={16} />
          </a>
          <a href="/docs/system-control">
            <SlidersHorizontal size={20} />
            <span>
              <strong>Keep your Mac in reach.</strong> Audio, Wi-Fi, and
              everyday controls.
            </span>
            <ArrowUpRight size={16} />
          </a>
        </section>
        <section className="home-wasm wrap" aria-labelledby="wasm-title">
          <p className="home-kicker">EXTENSIONS ARE WEBASSEMBLY</p>
          <h2 id="wasm-title">One module. Your Mac and your browser.</h2>
          <p>
            A Volant extension is a small WebAssembly module. The file you
            install in Volant runs in its sandboxed helper on your Mac, and
            the very same file runs on the Try it page in a modern browser.
            The module never reaches the network itself: Volant fetches only
            the addresses you approve and hands it the answer.
          </p>
          <div className="home-wasm-links">
            <a href="/try">
              Run one in your browser <ArrowUpRight size={15} />
            </a>
            <a href="/docs/extensions">
              How extensions work <ArrowUpRight size={15} />
            </a>
            <a href="https://github.com/mysticcoders/volant-extensions">
              Browse the catalog <ArrowUpRight size={15} />
            </a>
          </div>
        </section>
        <section className="home-bottom wrap">
          <div className="home-privacy">
            <Code2 size={25} aria-hidden="true" />
            <h2>
              Your tools.
              <br />
              Your say.
            </h2>
            <p>
              Your notes stay on your Mac, or in your own iCloud when you turn
              on sync. Clipboard history stays encrypted on your Mac. You choose
              what to send to AI. No Volant account. No telemetry.
            </p>
            <a href="/docs/privacy-and-security">
              Read the privacy details <ArrowUpRight size={15} />
            </a>
          </div>
          <div className="home-faq" id="details">
            <p className="home-kicker">GOOD TO KNOW</p>
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
          </div>
        </section>
        <section className="home-download wrap" id="get">
          <div>
            <p className="home-kicker">MAKE ROOM FOR THE WORK.</p>
            <h2>Your next move starts here.</h2>
            <p>Volant {appVersion} · Free & open source · Early release</p>
          </div>
          <a className="button" href={downloadURL} download>
            Download for Mac <ArrowRight size={18} />
          </a>
          <p className="home-brew">
            Prefer Homebrew?{' '}
            <code>brew install --cask mysticcoders/tap/volant</code>
          </p>
        </section>
      </main>
      <SiteFooter />
    </div>
  );
}
