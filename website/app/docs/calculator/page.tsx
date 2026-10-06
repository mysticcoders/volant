// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'The calculator — Volant docs',
  description:
    'Arithmetic, percentages, units, time zones, dates, colors and currency, answered as you type in the launcher.',
  alternates: { canonical: 'https://usevolant.com/docs/calculator' },
};

function Examples({ rows }: { rows: [string, string][] }) {
  return (
    <div className="docs-table-scroll">
      <table className="docs-table">
        <thead>
          <tr>
            <th>You type</th>
            <th>Answer</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(([query, answer]) => (
            <tr key={query}>
              <td><code>{query}</code></td>
              <td>{answer}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function Calculator() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / The calculator
      </p>
      <h1>The calculator</h1>
      <p className="docs-lede">
        Type a question into the launcher and the answer appears as a card at
        the top: your input on the left, the answer on the right, each with a
        short tag. Everything runs on your Mac except exchange rates.
      </p>

      <h2>Using an answer</h2>
      <ul>
        <li><strong>Return</strong> copies the answer.</li>
        <li>
          <strong>Command-Return</strong> puts the answer in the search field
          so you can keep calculating: <code>2 + 2</code>, Command-Return, then
          {' '}<code>* 3</code>.
        </li>
        <li>
          <strong>Shift-Command-Return</strong> runs a conversion the other
          way: <code>5 km in mi</code> becomes <code>3.106856 mi in km</code>.
        </li>
      </ul>

      <h2>Arithmetic</h2>
      <Examples
        rows={[
          ['2^10 / 3', '341.3333333333'],
          ['-2^2', '-4, as written math reads it'],
          ['52% of 900', '468'],
          ['20% off 80', '64'],
          ['15% tip on 42', '48.3, tagged with the 6.3 tip'],
          ['100 - 10%', '90'],
          ['10 mod 3', '1 (% always means percent)'],
          ['sin(90°)', '1 (radians unless marked °, deg)'],
          ['square root of 625', '25'],
          ['5!', '120'],
          ['max(3, 7, 5)', '7'],
          ['nCr(10, 3)', '120'],
        ]}
      />
      <p>
        Functions include <code>sqrt</code>, <code>cbrt</code>,{' '}
        <code>abs</code>, <code>round</code>, <code>floor</code>,{' '}
        <code>ceil</code>, trigonometric and hyperbolic functions and their
        inverses, <code>ln</code>, <code>log</code>, <code>log2</code>,{' '}
        <code>exp</code>, <code>min</code>, <code>max</code>,{' '}
        <code>atan2</code>, <code>hypot</code>, <code>gcd</code>,{' '}
        <code>lcm</code>, <code>nCr</code> and <code>nPr</code>.
      </p>
      <p>
        Numbers follow your Mac&rsquo;s region: <code>1,000</code> in English,
        {' '}<code>2,5</code> in German, <code>1 000</code> in French.
        Scientific notation (<code>1e3</code>) and magnitudes
        (<code>10K</code>, <code>2.5 million</code>) work too.
      </p>

      <h2>Units</h2>
      <Examples
        rows={[
          ['5 km in mi', '3.106856 mi'],
          ['72f to c', '22.222222 °C'],
          ['1 cup in ml', '236.588237 mL (US cup)'],
          ['5 sq ft in m2', '0.464515 m²'],
          ['1 gib in mb', '1073.741824 MB'],
          ['2rem in px', '32px'],
          ['2 inches in px at 72 ppi', '144px'],
        ]}
      />
      <p>
        Length, mass, volume, temperature, area, data, speed, energy, power,
        pressure and duration convert with exact definitions. CSS and design
        units use CSS&rsquo;s fixed ratios, with <code>at 18px</code> for a
        different rem base and <code>at 300 dpi</code> for print.
      </p>

      <h2>Time zones</h2>
      <Examples
        rows={[
          ['1pm EST in CET', '7:00 PM CEST'],
          ['3pm Lisbon in Tokyo', '11:00 PM in Tokyo'],
          ['time in JFK', 'the time in New York, by airport code'],
          ['time diff Tokyo', 'how far ahead or behind your clock it is'],
          ['time in 4 hours in Tokyo', 'the clock there later'],
          ['2024-03-15T14:30:00Z', 'the timestamp in your time'],
          ['unix 1700000000', 'a Unix time in your time'],
        ]}
      />
      <p>
        Zone abbreviations follow daylight saving the way people use them, and
        the answer names the one in effect. About 34,000 city names and 7,900
        airport codes work offline. When a city name is ambiguous, such as
        Springfield, you get one card per likely city.
      </p>

      <h2>Dates and durations</h2>
      <Examples
        rows={[
          ['7:30pm tomorrow', 'Tomorrow at 7:30 PM'],
          ['next friday', 'the next Friday that is not today'],
          ['days until christmas', 'a count, tagged with the date'],
          ['workdays until Dec 25', 'skips your region’s public holidays'],
          ['in 10 business days', 'a date'],
          ['monday in 3 weeks', 'that Monday'],
          ['August 5 + 5', 'August 10'],
          ['2h 20min + 55min', '3 hours 15 minutes'],
          ['145 mins to timespan', '2 hours 25 minutes'],
        ]}
      />
      <p>
        Workdays skip public holidays for the US, the UK (England and Wales),
        Germany, France and Canada, and only weekends elsewhere; the card says
        which. Named holidays such as Easter, Thanksgiving, Memorial Day and
        Boxing Day work wherever a date does.
      </p>

      <h2>Colors</h2>
      <Examples
        rows={[
          ['#ff6363', 'rgb(255 99 99), with a swatch'],
          ['hsl(120 100% 50%)', '#00ff00'],
          ['#ff0000 in oklch', 'oklch(62.8% 0.2577 29.23)'],
          ['rebeccapurple in hex', '#663399'],
        ]}
      />
      <p>
        Hex, rgb, hsl, hwb, lab, lch, oklab and oklch convert between each
        other following CSS Color 4. Named colors need a target format, so a
        plain word stays a search.
      </p>

      <h2>Currency and crypto</h2>
      <p>
        <code>100 usd in eur</code>, <code>$100 in gbp</code> and{' '}
        <code>USD1K in CHF</code> convert with the European Central
        Bank&rsquo;s daily reference rates, tagged with their date. Volant
        fetches the rates through a small separate helper the first time you
        type a currency conversion, then at most twice a day while you use
        them, and keeps them for offline use.
      </p>
      <p>
        With your own free CoinGecko Demo key in Settings → Data &amp;
        Configuration, major coins convert too: <code>0.5 btc in usd</code>,
        {' '}<code>100 eur in eth</code>. Prices refresh at most every ten
        minutes while you convert crypto. Data provided by{' '}
        <a href="https://www.coingecko.com">CoinGecko</a>. See{' '}
        <a href="/docs/privacy-and-security">Privacy and security</a> for what
        these requests send.
      </p>

      <DocFooterNav {...adjacentDocs('calculator')} />
    </>
  );
}
