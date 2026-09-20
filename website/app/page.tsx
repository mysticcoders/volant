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

import {
  SiteFooter,
  SiteHeader,
  downloadURL,
  repositoryURL,
} from '@/components/site-chrome';

const questions = [
  [
    'Can I download Volant yet?',
    'Yes. Download the macOS disk image, open it, and drag Volant into Applications. This is an early release, signed with Developer ID and notarized by Apple. Volant includes Check for Updates in its menu.',
  ],
  [
    'What Mac do I need?',
    'Volant requires macOS 15 or later. The download includes both Apple silicon and Intel versions.',
  ],
  [
    'Where does my data live?',
    'Notes are plain Markdown files on your Mac. Clipboard history is encrypted locally using a key stored in Keychain. Your configuration is a portable text file. The main app keeps its network access disabled. Update checks and downloads use Sparkle’s separate helper. Optional agent connections use a separate local helper; external harnesses, websites, and Shortcuts have their own access and data handling.',
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

export default function Home() {
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <SiteHeader />
      <main id="main">
        <section className="hero wrap">
          <div className="hero-copy">
            <a className="eyebrow open-source-label" href={repositoryURL}>
              <Code2 size={16} aria-hidden="true" /> OPEN SOURCE · MIT LICENSED
            </a>
            <h1>
              Your Mac.<br />
              Your agents.<br />
              <span>One shortcut away.</span>
            </h1>
            <p className="intro">
              Launch apps, find what you need, follow your agents, and start a
              conversation—all from a native Mac launcher. Keep notes, clipboard
              history, and reusable snippets close at hand.
            </p>
            <div className="hero-actions">
              <a href={downloadURL} className="button" download>
                Download for Mac <ArrowRight size={17} />
              </a>
              <a href="#get" className="text-link">
                Release status <ArrowUpRight size={15} />
              </a>
            </div>
            <p className="availability">
              Made for macOS 15+ <span>·</span> Local first <span>·</span> Early release
            </p>
          </div>
          <div className="hero-visual">
            <div className="orbit-label"><Command size={14} /> One place to keep work moving.</div>
            <figure className="native-launcher-preview">
              {/* oxlint-disable-next-line next/no-html-link-for-pages -- Direct PNG asset, not a Next.js route. */}
              <a href="/images/launcher-dark.png" aria-label="View the full-size Volant launcher capture">
              <Image unoptimized src="/images/launcher-dark.png" alt="Volant’s native launcher with coral accents, Safari results, and expanded Herdr pane details showing each fictional project, provider, and status." width={1500} height={960} priority />
              </a>
            </figure>
            <div className="preview-caption"><span className="tiny-line" /> Native Volant capture · fictional activity</div>
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
            <FileText size={17} /> Portable files
          </span>
          <span>
            <Code2 size={17} /> Agent conversations
          </span>
        </div>
        <section className="notes-section wrap" id="agents" aria-labelledby="agents-title">
          <div className="section-intro">
            <p className="eyebrow">01 / AGENT WORKFLOWS · IN DEVELOPMENT</p>
            <h2 id="agents-title">Your agents.<br /><span>Within reach.</span></h2>
            <p>A native place to find the session that needs you, return to its pane, and keep work moving.</p>
            <a className="text-link" href="#get">Follow release status <ArrowUpRight size={15} /></a>
          </div>
          <div className="notes-details">
            <article><span className="detail-number">01</span><div><h3>Find the right session.</h3><p>Find Herdr panes by project, harness, or status, then jump back to the right pane. Pin a harness below the search field, then optionally expand its overview to see each project, provider, and status without opening the agent list.</p></div></article>
            <article><span className="detail-number">02</span><div><h3>The harnesses you already use.</h3><p>Start native ACP conversations with OpenCode, Claude Code, and Codex. Read streamed responses and tool activity, respond to permission requests, and cancel a turn from Volant. Claude Code and Codex connect through ACP adapters.</p></div></article>
            <article><span className="detail-number">03</span><div><h3>Clear about what’s next.</h3><p>ACP starts a new Volant-owned conversation; it doesn’t attach to an existing terminal session. Cursor support is awaiting verification. Reviewed note and snippet handoff is next; context is never sent automatically.</p></div></article>
          </div>
        </section>
        <section className="features-section" id="launcher">
          <div className="wrap">
            <div className="features-heading"><div><p className="eyebrow">02 / MOVE AROUND YOUR MAC</p><h2>Find it.<br /><span>Get there.</span></h2></div><p>Apps, files, people, and everyday actions. A familiar starting point that learns the way you work.</p></div>
            <div className="feature-grid">
              <article><Zap /><h3>A faster way there.</h3><p>Launch apps with ranking that learns from your choices. Use aliases and per-app hotkeys to bring an app forward, then hide it when you’re done.</p><div className="mini-search"><span><Command size={16} /> sa</span><span>Safari <CornerDownLeft size={15} /></span></div></article>
              <article><Command /><h3>Keep your hands moving.</h3><p>Search files and contacts, calculate, and convert units from the launcher. Run explicitly configured Apple Shortcuts, with optional text input.</p></article>
              <article><CornerDownLeft /><h3>Make the next meeting.</h3><p>Type cal to see today and tomorrow’s agenda. Select a meeting and press Return to join from its meeting link.</p></article>
            </div>
          </div>
        </section>
        <section className="notes-section wrap" id="notes">
          <div className="section-intro">
            <p className="eyebrow">03 / KEEP USEFUL THINGS CLOSE</p>
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
              Release status <ArrowUpRight size={15} />
            </a>
          </div>
          <div className="notes-details">
            <Image unoptimized className="notes-preview" src="/images/live-notes.png" width="1120" height="1240" alt="Development preview of Live Notes with Markdown and a Python code block, language selection, and Copy Code." />
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
                <p className="eyebrow">YOUR EVERYDAY TOOLKIT</p>
                <h2>
                  Less repeat.
                  <br />
                  <span>More rhythm.</span>
                </h2>
              </div>
              <p>
                Save what matters. Reuse what works. Keep your everyday tools
                together, with storage and settings you control.
              </p>
            </div>
            <div className="feature-grid">
              <article>
                <LockKeyhole /><h3>Make it yours.</h3>
                <p>Keep aliases, quicklinks, and preferences in portable text configuration. Export a backup, and choose whether Volant appears in the Dock or stays in the menu bar.</p>
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
          <p className="eyebrow">04 / DELIBERATELY PERSONAL</p>
          <h2>
            Open source.
            <br />
            MIT licensed. <span>Yours to make.</span>
          </h2>
          <p>
            Built in the open, with the code on GitHub. Use it, change it, and
            make it yours. No Volant account. No telemetry. Your notes, clipboard
            history, and configuration stay on your Mac.
          </p>
          <a href={repositoryURL} className="text-link">
            <Image unoptimized src="/icons/github.svg" alt="" width={18} height={18} className="social-icon" /> Explore the source <ArrowUpRight size={15} />
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
                  <p>{a}{q === 'Is Volant open source?' && <> <a className="faq-source" href={repositoryURL}>View the source</a> · <a className="faq-source" href={`${repositoryURL}/blob/main/LICENSE`}>Read the MIT license</a>.</>}</p>
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
          <p className="eyebrow">YOUR MAC. YOUR AGENTS. YOUR WORKSPACE.</p>
          <h2>Move faster with Volant.</h2>
          <p>
            Apps, agents, and notes. One shortcut away.
            <br />
            Open source. MIT licensed.
          </p>
          <a className="button" href={downloadURL} download>
            Download for Mac <ArrowRight size={17} />
          </a>
          <span className="availability">
            Version 0.1.4 · macOS 15+ · Apple silicon & Intel
          </span>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}
