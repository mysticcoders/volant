// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import type { Metadata } from 'next';
import Image from 'next/image';
import { ArrowRight, ArrowUpRight, Cloud, Calculator, LayoutGrid, Lock, Search, TextQuote } from 'lucide-react';
import { downloadURL, repositoryURL } from '@/components/site-chrome';
import { SiteShell } from '@/components/site-shell';
import { StarButton } from '@/components/star-button';
import './iphone.css';

export const metadata: Metadata = {
  title: 'Volant for iPhone — public beta',
  description:
    'Volant for iPhone is in public beta on TestFlight, ready for iPhone Duo folded or open: your Markdown notes through iCloud, the snippets and quicklinks you set up on your Mac, and Volant’s calculator. No account. No telemetry.',
  alternates: { canonical: 'https://usevolant.com/iphone' },
};

const features = [
  {
    icon: Cloud,
    title: 'Your notes, on every device',
    body: 'The same plain Markdown files as Volant on your Mac, through your own iCloud Drive. Turn on Sync settings and notes with iCloud in Volant 0.3.39 or later.',
  },
  {
    icon: TextQuote,
    title: 'Snippets and quicklinks',
    body: 'The ones you set up on your Mac, ready to copy or open. Add or edit them on either device.',
  },
  {
    icon: Calculator,
    title: 'The same calculator',
    body: 'Units, time zones, dates, percentages and more, answered as you type by the code that runs in Volant on your Mac.',
  },
  {
    icon: Search,
    title: 'One search',
    body: 'Notes, snippets and quicklinks together, with an answer from the calculator when you type a calculation.',
  },
  {
    icon: LayoutGrid,
    title: 'All over your iPhone',
    body: 'Home Screen and Lock Screen widgets, a Control Center control for a new note, Save to Volant from the share sheet, and Shortcuts actions.',
  },
  {
    icon: Lock,
    title: 'Your tools. Your say.',
    body: 'No Volant account. No telemetry. Your notes stay in your own iCloud.',
  },
] as const;

const screens = [
  { src: '/images/iphone/home.webp', alt: 'Volant for iPhone Home: quick actions for a new note, snippets, quicklinks and the calculator, above recent notes' },
  { src: '/images/iphone/note.webp', alt: 'A Markdown note in preview, with a checklist, a Swift code block and a quote' },
  { src: '/images/iphone/search.webp', alt: 'Search for “map” finding a note and quicklinks that search maps and the web' },
  { src: '/images/iphone/snippets.webp', alt: 'Snippets from the Mac with their keywords' },
] as const;

const betaURL = 'https://testflight.apple.com/join/rC8T5QFS';

/** The Volant for iPhone and iPad page, while the app is in public beta on TestFlight. Every claim
 * describes the beta build as it stands; no App Store link appears until the app is released there. */
export default function IPhonePage() {
  return (
    <SiteShell mainClassName="wrap iphone-page">
      <p className="home-kicker">PUBLIC BETA</p>
      <h1>
        Volant for <em>iPhone.</em>
      </h1>
      <p className="iphone-lede">
        Your notes, snippets, quicklinks and calculator from Volant on your Mac, on your iPhone and iPad. Now in
        public beta on TestFlight.
      </p>
      <div className="home-actions">
        <a className="button" href={betaURL}>
          Join the beta on TestFlight <ArrowUpRight size={18} />
        </a>
      </div>
      <div className="iphone-screens">
        {screens.map((screen) => (
          <Image key={screen.src} src={screen.src} alt={screen.alt} width={330} height={717} sizes="(max-width: 860px) 50vw, 25vw" />
        ))}
      </div>
      <section className="iphone-duo" aria-labelledby="iphone-duo-title">
        <div className="iphone-duo-copy">
          <p className="home-kicker">READY FOR IPHONE DUO</p>
          <h2 id="iphone-duo-title">Folded or open, Volant fits.</h2>
          <p>
            On the outer screen, Volant works the way it does on any iPhone. Unfold it and Notes spreads out: your
            notes on one side, the one you’re writing on the other, with the rest of Volant using the whole display.
          </p>
        </div>
        <div className="iphone-duo-shots">
          <Image
            className="iphone-duo-open"
            src="/images/iphone/duo-unfolded.webp"
            alt="Volant on iPhone Duo unfolded: the notes list beside an open note"
            width={1400}
            height={985}
            sizes="(max-width: 860px) 100vw, 60vw"
          />
          <Image
            className="iphone-duo-folded"
            src="/images/iphone/duo-folded.webp"
            alt="Volant Home on the folded iPhone Duo’s outer screen"
            width={520}
            height={757}
            sizes="(max-width: 860px) 40vw, 18vw"
          />
        </div>
      </section>
      <ul className="iphone-features">
        {features.map(({ icon: Icon, title, body }) => (
          <li key={title}>
            <Icon size={22} aria-hidden="true" />
            <h2>{title}</h2>
            <p>{body}</p>
          </li>
        ))}
      </ul>
      <section className="iphone-ready" aria-labelledby="iphone-ready-title">
        <h2 id="iphone-ready-title">Bring your Mac along</h2>
        <p>
          Install Volant 0.3.39 or later on your Mac and turn on <strong>Sync settings and notes with iCloud</strong> in
          Settings → Data &amp; Configuration. Your notes, snippets and quicklinks then appear in Volant for iPhone.
        </p>
        <div className="home-actions">
          <a className="button" href={downloadURL} download>
            Download for Mac <ArrowRight size={18} />
          </a>
          <StarButton href={repositoryURL} />
        </div>
      </section>
    </SiteShell>
  );
}
