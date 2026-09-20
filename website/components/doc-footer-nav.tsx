// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { DocLink } from '@/app/docs/docs-nav';

export function DocFooterNav({
  previous,
  next,
}: {
  previous?: DocLink;
  next?: DocLink;
}) {
  return (
    <div className="docs-footer-nav">
      <span>
        {previous ? (
          <a href={`/docs/${previous.slug}`}>&larr; {previous.title}</a>
        ) : null}
      </span>
      <span>
        {next ? <a href={`/docs/${next.slug}`}>{next.title} &rarr;</a> : null}
      </span>
    </div>
  );
}
