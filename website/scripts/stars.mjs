import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const repository = 'mysticcoders/volant';

// Reads the star count once per build: through the signed-in gh CLI when present (authenticated, so it
// is not subject to the shared unauthenticated rate limit), otherwise GitHub's public API. A failure
// writes null, and the header then shows the button without a count.
async function starCount() {
  try {
    const stars = Number(execFileSync('gh', ['api', `repos/${repository}`, '--jq', '.stargazers_count'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 10000,
    }).trim());
    if (Number.isInteger(stars)) return stars;
  } catch {}
  try {
    const response = await fetch(`https://api.github.com/repos/${repository}`, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'usevolant.com build' },
      signal: AbortSignal.timeout(10000),
    });
    const body = response.ok ? await response.json() : null;
    if (Number.isInteger(body?.stargazers_count)) return body.stargazers_count;
  } catch {}
  return null;
}

writeFileSync(new URL('../lib/github-stars.json', import.meta.url), `${JSON.stringify({ stars: await starCount() })}\n`);
