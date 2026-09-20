// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { docGroups } from './docs-nav';
import { appVersion } from '@/components/site-chrome';

export const metadata: Metadata = {
  title: 'Documentation — Volant',
  description:
    'How to install and use Volant: the launcher, notes, clipboard history, snippets, system control, Apple Shortcuts, agents, and the config.json reference.',
  alternates: { canonical: 'https://usevolant.com/docs' },
};

export default function DocsIndex() {
  return (
    <>
      <p className="eyebrow">DOCUMENTATION</p>
      <h1>Volant, end to end.</h1>
      <p className="docs-lede">
        Everything the app can do today, written against version {appVersion}. Where a
        feature is an early spike or has not been verified end to end, these
        pages say so rather than implying otherwise.
      </p>

      {docGroups.map((group) => (
        <section key={group.group}>
          <h2>{group.group.charAt(0) + group.group.slice(1).toLowerCase()}</h2>
          <div className="docs-card-grid">
            {group.links.map((link) => (
              <a
                className="docs-card"
                key={link.slug}
                href={`/docs/${link.slug}`}
              >
                <strong>{link.title}</strong>
                <span>{link.summary}</span>
              </a>
            ))}
          </div>
        </section>
      ))}

      <h2>Reading the source</h2>
      <p>
        Volant is open source under the MIT license. The engineering notes
        behind each feature, including the measurements and the parts still
        unverified, live in the{' '}
        <a href="https://github.com/mysticcoders/volant/tree/main/docs">
          docs directory
        </a>{' '}
        of the repository.
      </p>
    </>
  );
}
