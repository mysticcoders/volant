// oxlint-disable next/no-html-link-for-pages -- Plain anchors preserve production navigation; see QUALITY.md.
import type { Metadata } from 'next';
import { ArrowRight } from 'lucide-react';
import { downloadURL, repositoryURL } from '@/components/site-chrome';
import { SiteShell } from '@/components/site-shell';
import { StarButton } from '@/components/star-button';
import { TryLauncher } from '@/components/try-launcher';
import './try.css';

export const metadata: Metadata = {
  title: 'Try Volant in your browser',
  description:
    'Type into Volant in your browser: real Volant extensions and Volant’s own calculator, compiled to WebAssembly. Nothing you type leaves the page.',
  alternates: { canonical: 'https://usevolant.com/try' },
};

/** The interactive, clearly labeled browser demo of the launcher, running real Volant code, in the
 * homepage's design. The homepage hero hands typed text over as `?q=`. */
export default async function TryPage({ searchParams }: { searchParams: Promise<{ q?: string | string[] }> }) {
  const { q } = await searchParams;
  const initialQuery = (Array.isArray(q) ? q[0] : q ?? '').slice(0, 200);
  return (
    <SiteShell mainClassName="wrap try-page">
      <p className="home-kicker">RUNS IN YOUR BROWSER</p>
      <h1>Try Volant now.</h1>
      <p className="try-lede">
        Real Volant extensions and Volant’s own calculator, compiled to WebAssembly. Nothing you type leaves this page.
      </p>
      <TryLauncher initialQuery={initialQuery} />
      <ul className="try-notes">
        <li>Try <strong>15% of 80</strong>, <strong>5 km in miles</strong>, <strong>3pm tokyo in new york</strong> or <strong>100 usd in eur</strong>. Type <strong>hn</strong>, <strong>wiki</strong> or <strong>case</strong> and press Return for an extension.</li>
        <li>
          Extensions are WebAssembly. The module you install in Volant is the same file running on this page; the host,
          not the module, does any fetching. <a href="/docs/extensions">How extensions work</a>.
        </li>
        <li>Currency uses public rates this site refreshes on a schedule, so your query never reaches the providers. News and Wikipedia replay responses recorded once.</li>
        <li>Files, contacts, clipboard and agents need Volant on your Mac. The demo answers in English only; the full app formats numbers, dates and units for your language and region.</li>
      </ul>
      <div className="home-actions">
        <a className="button" href={downloadURL} download>
          Download for Mac <ArrowRight size={18} />
        </a>
        <StarButton href={repositoryURL} />
      </div>
      <p className="try-credits">
        Exchange rates:{' '}
        <a href="https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html">European Central Bank</a>
        {' · '}
        <a href="https://www.exchangerate-api.com">Rates By Exchange Rate API</a>
        {' · '}
        <a href="https://www.coingecko.com">Data provided by CoinGecko</a>
        {' · '}
        <a href={`${repositoryURL}/blob/main/docs/try-volant.md`}>How the demo works</a>
      </p>
    </SiteShell>
  );
}
