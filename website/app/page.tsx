'use client';

// oxlint-disable next/no-html-link-for-pages -- Keep the site's working plain-anchor
// navigation while vinext's production next/link handler is broken. See QUALITY.md.

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
  Calculator,
  SlidersHorizontal,
  Sparkles,
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

const answerExamples = [
  ['35% of 260', '91', 'Percentages'],
  ['$45/hour * 37.5 hours', '$1,687.50', 'Pay for time'],
  ['1 1/2 cups bread flour in g', '180 g · approximate', 'Cooking'],
  [
    '#3a7bd5 in swiftui',
    'Color(red: 0.227, green: 0.482, blue: 0.835)',
    'Design',
  ],
];

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
    'Notes are plain Markdown files on your Mac. Clipboard history is encrypted locally with a Keychain key. You choose what to attach to AI prompts; cloud providers receive the messages you send. Updates, optional AI connections, and exchange rates use separate helpers. Opt-in iCloud settings sync carries selected settings between your Macs and excludes notes, clipboard history, and keys.',
  ],
  [
    'Are all the features here in the download?',
    `Yes. Everything on this page is in the current download, Volant ${appVersion}, including the expanded calculator, color themes and theme import, the system commands, and iCloud settings sync.`,
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
              Your Mac.
              <br />
              Your agents.
              <br />
              <span>One shortcut away.</span>
            </h1>
            <p className="intro">
              Find what you need, answer everyday questions, and keep your
              agents moving—all from a native Mac launcher. Your notes and
              clipboard stay local; you choose what to share with AI.
            </p>
            <div className="hero-actions">
              <a href={downloadURL} className="button" download>
                Download for Mac <ArrowRight size={17} />
              </a>
              <a href="#get" className="text-link">
                What’s in the download <ArrowUpRight size={15} />
              </a>
            </div>
            <p className="availability">
              Made for macOS 15+ <span>·</span> Local first <span>·</span> Early
              release
            </p>
          </div>
          <div className="hero-visual">
            <div className="orbit-label">
              <Command size={14} /> One place to keep work moving.
            </div>
            <figure className="native-launcher-preview">
              {/* oxlint-disable-next-line next/no-html-link-for-pages -- Direct PNG asset, not a Next.js route. */}
              <a
                href="/images/launcher-dark.png"
                aria-label="View the full-size Volant launcher capture"
              >
                <Image
                  unoptimized
                  src="/images/launcher-dark.png"
                  alt="Volant’s native launcher with coral accents, Safari results, and expanded Herdr pane details showing each fictional project, provider, and status."
                  width={1500}
                  height={960}
                  priority
                />
              </a>
            </figure>
            <div className="preview-caption">
              <span className="tiny-line" /> Native Volant capture · fictional
              activity
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
            <Calculator size={17} /> Answers as you type
          </span>
          <span>
            <Code2 size={17} /> Agent conversations
          </span>
        </div>
        <section
          className="answers-section wrap"
          id="answers"
          aria-labelledby="answers-title"
        >
          <div className="features-heading">
            <div>
              <p className="eyebrow">
                01 / ANSWERS AS YOU TYPE{' '}
                <span className="release-badge">New in 0.2.0</span>
              </p>
              <h2 id="answers-title">
                Ask it.
                <br />
                <span>Carry on.</span>
              </h2>
            </div>
            <p>
              Work out a percentage, plan across time zones, convert currencies,
              or find the right color. One search field. An answer you can copy
              and use.
            </p>
          </div>
          <div className="answer-showcase">
            <figure className="product-capture">
              <a
                href="/images/calculator-dark.png"
                aria-label="View the full-size native calculator preview"
              >
                <Image
                  unoptimized
                  src="/images/calculator-dark.png"
                  alt="Native Volant development preview answering 35% of 260 with 91 in a two-sided calculator card."
                  width={1500}
                  height={960}
                />
              </a>
              <figcaption>
                Native development capture · next-release calculator
              </figcaption>
            </figure>
            <div
              className="answer-examples"
              aria-label="Examples supported by the next-release calculator"
            >
              {answerExamples.map(([query, answer, category]) => (
                <div className="answer-example" key={query}>
                  <span>{category}</span>
                  <code>{query}</code>
                  <strong>{answer}</strong>
                </div>
              ))}
            </div>
          </div>
          <p className="section-footnote">
            Time zones, dates, units, and colors work on your Mac. Currency and
            crypto conversions fetch rates on demand.{' '}
            <a href="/docs/calculator">
              Explore the calculator <ArrowUpRight size={14} />
            </a>
          </p>
        </section>
        <section
          className="notes-section wrap"
          id="agents"
          aria-labelledby="agents-title"
        >
          <div className="section-intro">
            <p className="eyebrow">02 / KEEP YOUR AGENTS MOVING</p>
            <h2 id="agents-title">
              When they need you.
              <br />
              <span>You’re right there.</span>
            </h2>
            <p>
              Find the session that needs a decision, see its question, and
              respond without losing your place.
            </p>
            <a className="text-link" href="/docs/agents">
              See agent workflows <ArrowUpRight size={15} />
            </a>
          </div>
          <div className="notes-details">
            <figure className="product-capture">
              <a
                href="/images/agent-attention-dark.png"
                aria-label="View the full-size native agent question preview"
              >
                <Image
                  unoptimized
                  src="/images/agent-attention-dark.png"
                  alt="Native Volant with fictional Herdr activity and a Codex question waiting for an explicit answer."
                  width={1500}
                  height={960}
                />
              </a>
              <figcaption>Native development capture · fictional agent question</figcaption>
            </figure>
            <article>
              <span className="detail-number">01</span>
              <div>
                <h3>Find the right session.</h3>
                <p>
                  Search Herdr panes by project, provider, or status. The launcher
                  footer shows how many are waiting on you, and you can answer supported
                  Claude Code and Codex questions and approvals. Saved remote
                  machines need compatible Herdr installations.
                </p>
              </div>
            </article>
            <article>
              <span className="detail-number">02</span>
              <div>
                <h3>The agents you already use.</h3>
                <p>
                  Start a new native conversation with OpenCode, Claude Code, or
                  Codex. Read streamed replies and tool activity, make explicit
                  permission choices, and cancel a turn. Claude Code and Codex
                  use ACP adapters.
                </p>
              </div>
            </article>
            <article>
              <span className="detail-number">03</span>
              <div>
                <h3>Keep your place.</h3>
                <p>
                  Your active conversation and draft survive hiding the
                  launcher. Return when you’re ready. New conversations are
                  separate from existing terminal sessions; Cursor’s ACP
                  connection remains unverified.
                </p>
              </div>
            </article>
          </div>
        </section>
        <section
          className="features-section"
          id="ai"
          aria-labelledby="ai-title"
        >
          <div className="wrap">
            <div className="features-heading">
              <div>
                <p className="eyebrow">AI ON YOUR TERMS</p>
                <h2 id="ai-title">
                  Choose the model.
                  <br />
                  <span>Choose the context.</span>
                </h2>
              </div>
              <p>
                Use your coding agent, bring an API key, connect a local model
                server, or use Apple Intelligence on an eligible Mac with macOS
                26.
              </p>
            </div>
            <div className="ai-showcase">
              <figure className="product-capture">
                <a
                  href="/images/chat-context-dark.png"
                  aria-label="View the full-size native chat attachment preview"
                >
                  <Image
                    unoptimized
                    src="/images/chat-context-dark.png"
                    alt="Native Volant AI Chat with an unsent draft and an explicitly attached fictional Markdown note."
                    width={1500}
                    height={960}
                  />
                </a>
                <figcaption>
                  Native development capture · fictional draft, no prompt sent
                </figcaption>
              </figure>
              <div className="notes-details">
                <article>
                  <Sparkles aria-hidden="true" />
                  <div>
                    <h3>A conversation within reach.</h3>
                    <p>
                      Open AI Chat when you need it. Cloud models use your API
                      account; local servers use your selected model. Apple
                      Intelligence runs on device when available.
                    </p>
                  </div>
                </article>
                <article>
                  <FileText aria-hidden="true" />
                  <div>
                    <h3>Bring just what matters.</h3>
                    <p>
                      Type @ in chat to choose a note or recent clipboard text.
                      Review the attachment chips before sending. Nothing is
                      attached automatically.
                    </p>
                  </div>
                </article>
                <article>
                  <LockKeyhole aria-hidden="true" />
                  <div>
                    <h3>You decide what leaves your Mac.</h3>
                    <p>
                      API keys stay in Keychain. A cloud connection receives
                      your submitted prompt and selected context. Local models
                      have no automatic cloud fallback.
                    </p>
                  </div>
                </article>
                <a className="text-link" href="/docs/agents">
                  Setup, requirements, and current limits{' '}
                  <ArrowUpRight size={15} />
                </a>
              </div>
            </div>
          </div>
        </section>
        <section
          className="answers-section wrap"
          id="launcher"
          aria-labelledby="launcher-title"
        >
          <div className="features-heading">
            <div>
              <p className="eyebrow">03 / MOVE AROUND YOUR MAC</p>
              <h2 id="launcher-title">
                Find it.
                <br />
                <span>Get there.</span>
              </h2>
            </div>
            <p>
              Apps, files, people, and everyday actions. A familiar starting
              point that learns the way you work.
            </p>
          </div>
          <div className="feature-grid">
            <article>
              <Zap aria-hidden="true" />
              <h3>A faster way there.</h3>
              <p>
                Launch apps with ranking that learns from your choices. Use
                aliases and per-app hotkeys to bring an app forward, then hide
                it when you’re done.
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
              <SlidersHorizontal aria-hidden="true" />
              <h3>Your Mac, within reach.</h3>
              <p>
                Switch audio routes, adjust volume, find Wi-Fi networks, or keep
                your Mac awake. Open the right System Settings pane from a
                search.
              </p>
              <a className="feature-link" href="/docs/system-control">
                Explore Mac controls <ArrowUpRight size={14} />
              </a>
            </article>
            <article>
              <CornerDownLeft aria-hidden="true" />
              <h3>Make the next meeting.</h3>
              <p>
                Find files and contacts. Type cal for today and tomorrow’s
                agenda, then press Return to join a meeting. Run your explicitly
                configured Apple Shortcuts.
              </p>
            </article>
          </div>
        </section>
        <section className="notes-section wrap" id="notes">
          <div className="section-intro">
            <p className="eyebrow">04 / KEEP USEFUL THINGS CLOSE</p>
            <h2>
              Open. Write.
              <br />
              <span>Carry on.</span>
            </h2>
            <p>
              A note shouldn’t become another project. Bring up a quiet space,
              get it down, and get back to what you were doing.
            </p>
            <a className="text-link" href="/docs/notes">
              Explore Live Notes <ArrowUpRight size={15} />
            </a>
          </div>
          <div className="notes-details">
            <Image
              unoptimized
              className="notes-preview"
              src="/images/live-notes.png"
              width="1120"
              height="1240"
              alt="Development preview of Live Notes with Markdown and a Python code block, language selection, and Copy Code."
            />
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
                <LockKeyhole />
                <h3>Make it yours.</h3>
                <p>
                  Choose shortcuts and aliases, bring supported notes and
                  snippets from Raycast, and keep preferences in portable text
                  configuration.
                </p>
                <a className="feature-link" href="/docs/importing-from-raycast">
                  Bring your setup <ArrowUpRight size={14} />
                </a>
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
        <section
          className="next-release wrap"
          id="next"
          aria-labelledby="next-title"
        >
          <p className="eyebrow">
            NEW IN 0.2.0
          </p>
          <h2 id="next-title">More ways to make it yours.</h2>
          <div className="feature-grid">
            <article>
              <h3>Color that fits your Mac.</h3>
              <p>
                Follow your macOS accent, choose a color theme, or import a
                Raycast theme from a file or link. Notes follows your active
                theme too.
              </p>
            </article>
            <article>
              <h3>One shortcut to step away.</h3>
              <p>
                Lock your screen, sleep your Mac or displays, and start the
                screen saver. Restart, shut down, and log out use macOS
                confirmation dialogs.
              </p>
            </article>
            <article>
              <h3>Your setup on another Mac.</h3>
              <p>
                Opt-in iCloud sync for selected shortcuts, snippets, quicklinks,
                aliases, and appearance. Notes, clipboard history, and keys stay
                out.
              </p>
            </article>
          </div>
          <p className="section-footnote">
            The expanded calculator above is new in 0.2.0 too. Download{' '}
            {appVersion} today, or{' '}
            <a href={`${repositoryURL}/pulls?q=is%3Apr+is%3Amerged`}>
              follow development on GitHub <ArrowUpRight size={14} />
            </a>
            .
          </p>
        </section>
        <section className="philosophy wrap">
          <p className="eyebrow">05 / DELIBERATELY PERSONAL</p>
          <h2>
            Open source.
            <br />
            MIT licensed. <span>Yours to make.</span>
          </h2>
          <p>
            Built in the open, with the code on GitHub. Use it, change it, and
            make it yours. No Volant account. No telemetry. Notes and encrypted
            clipboard history stay on your Mac. Sharing context with AI is
            always your choice.
          </p>
          <a href={repositoryURL} className="text-link">
            <Image
              unoptimized
              src="/icons/github.svg"
              alt=""
              width={18}
              height={18}
              className="social-icon"
            />{' '}
            Explore the source <ArrowUpRight size={15} />
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
                  <p>
                    {a}
                    {q === 'Is Volant open source?' && (
                      <>
                        {' '}
                        <a className="faq-source" href={repositoryURL}>
                          View the source
                        </a>{' '}
                        ·{' '}
                        <a
                          className="faq-source"
                          href={`${repositoryURL}/blob/main/LICENSE`}
                        >
                          Read the MIT license
                        </a>
                        .
                      </>
                    )}
                  </p>
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
            Keep your work moving. One shortcut away.
            <br />
            Open source. MIT licensed.
          </p>
          <a className="button" href={downloadURL} download>
            Download for Mac <ArrowRight size={17} />
          </a>
          <span className="availability">
            Version {appVersion} · macOS 15+ · Apple silicon &amp; Intel
          </span>
          <p className="download-scope">
            <a href="#next">New in 0.2.0</a>: the expanded calculator, color
            themes, system commands, and iCloud settings sync.
          </p>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}
