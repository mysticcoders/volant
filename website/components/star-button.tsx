import githubStars from '@/lib/github-stars.json';

/** Shortens a star count to the form GitHub shows, such as 1.2k. */
function formatStars(stars: number) {
  return stars >= 1000 ? `${(stars / 1000).toFixed(stars >= 10000 ? 0 : 1).replace(/\.0$/, '')}k` : String(stars);
}

/**
 * A Star on GitHub button for the site header, with the star count read at build time by
 * scripts/stars.mjs. Without a count it is a plain Star link.
 */
export function StarButton({ href }: { href: string }) {
  const stars = typeof githubStars.stars === 'number' ? githubStars.stars : null;
  return (
    <a
      href={href}
      className="nav-star"
      aria-label={stars === null ? 'Star Volant on GitHub' : `Star Volant on GitHub, ${stars} stars`}
    >
      <span className="nav-star-icon" aria-hidden="true" />
      Star
      {stars !== null && <span className="nav-star-count">{formatStars(stars)}</span>}
    </a>
  );
}
