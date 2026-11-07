// Exchange rates for the /try demo, mirroring Volant's VolantRatesHost: three fixed upstream URLs
// (the same ones the app uses), no redirects, a size cap and a shape check before anything is kept.
// Only the scheduled refresh (Cron Trigger) fetches them, and it writes them to KV; visitor requests
// read KV and never reach the providers. Nothing here sees a visitor's query, and nothing is logged.

export type FeedName = 'ecb' | 'world' | 'crypto';
export type StoredFeed = { body: string; fetchedAt: number };

type Feed = {
  url: string;
  maximumBytes: number;
  /** How old a stored copy may be before /try treats the feed as unavailable, in seconds. */
  staleAfter: number;
  valid: (text: string) => boolean;
};

/** Parses JSON into an object, or returns null, for the shape checks. */
function json(text: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(text);
    return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const coins = ['bitcoin', 'ethereum', 'solana', 'ripple', 'binancecoin', 'cardano', 'dogecoin', 'tether', 'usd-coin', 'litecoin', 'polkadot', 'tron'];

export const feeds: Record<FeedName, Feed> = {
  ecb: {
    url: 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
    maximumBytes: 65536,
    // ECB publishes on business days; a Friday copy must last a long weekend.
    staleAfter: 4 * 86400,
    valid: (text) => /<Cube\s+time=['"]\d{4}-\d{2}-\d{2}['"]/.test(text) && (text.match(/currency=['"][A-Z]{3}['"]/g) ?? []).length >= 5,
  },
  world: {
    url: 'https://open.er-api.com/v6/latest/EUR',
    maximumBytes: 32768,
    staleAfter: 2 * 86400,
    valid: (text) => {
      const body = json(text);
      return body?.result === 'success' && body.base_code === 'EUR' && typeof body.rates === 'object';
    },
  },
  crypto: {
    url: `https://api.coingecko.com/api/v3/simple/price?ids=${coins.join(',')}&vs_currencies=eur`,
    maximumBytes: 16384,
    staleAfter: 30 * 60,
    valid: (text) => {
      const body = json(text);
      return !!body && coins.filter((id) => typeof (body[id] as { eur?: unknown } | undefined)?.eur === 'number').length * 2 >= coins.length;
    },
  },
};

/** The Cron schedules and the feeds each refreshes: ECB and ExchangeRate-API every 6 hours,
 * CoinGecko every 5 minutes. */
export const schedules: Record<string, FeedName[]> = {
  '0 */6 * * *': ['ecb', 'world'],
  '*/5 * * * *': ['crypto'],
};

export const isFeedName = (name: string): name is FeedName => Object.hasOwn(feeds, name);
const key = (name: FeedName) => `rates:${name}`;

/** Fetches one fixed feed without following redirects, capped in size and checked for shape. */
export async function fetchFeed(name: FeedName): Promise<StoredFeed | null> {
  const feed = feeds[name];
  const response = await fetch(feed.url, {
    redirect: 'manual',
    headers: { Accept: name === 'ecb' ? 'application/xml' : 'application/json', 'User-Agent': 'usevolant.com try demo' },
  });
  if (response.status !== 200) return null;
  const declared = Number(response.headers.get('content-length') ?? '0');
  if (declared > feed.maximumBytes) return null;
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > feed.maximumBytes) return null;
  const body = new TextDecoder().decode(bytes);
  return feed.valid(body) ? { body, fetchedAt: Math.floor(Date.now() / 1000) } : null;
}

/** Refreshes the feeds a Cron schedule covers, keeping the stored copy when a fetch fails. */
export async function refreshFeeds(kv: KVNamespace, names: FeedName[]): Promise<Record<string, boolean>> {
  const outcome: Record<string, boolean> = {};
  for (const name of names) {
    let fresh: StoredFeed | null = null;
    try {
      fresh = await fetchFeed(name);
    } catch {
      fresh = null;
    }
    if (fresh) await kv.put(key(name), JSON.stringify(fresh));
    outcome[name] = !!fresh;
  }
  return outcome;
}

/** Reads a stored feed, or null when it's missing, malformed or older than its stale threshold. */
export async function readFeed(kv: KVNamespace, name: FeedName, now = Math.floor(Date.now() / 1000)): Promise<StoredFeed | null> {
  const stored = await kv.get<StoredFeed>(key(name), 'json');
  if (!stored || typeof stored.body !== 'string' || typeof stored.fetchedAt !== 'number') return null;
  return now - stored.fetchedAt <= feeds[name].staleAfter ? stored : null;
}
