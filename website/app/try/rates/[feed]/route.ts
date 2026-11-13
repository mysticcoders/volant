// Exchange rates for the /try demo, read from KV only. The scheduled refresh in worker/index.ts is
// the only code that contacts the providers, so a visitor request never reaches them. Requests are
// rate limited per client by the TRY_RATES_LIMIT binding; the client address is used only as the
// limiter's key and is never stored or logged.
import { env } from 'cloudflare:workers';
import { isFeedName, readFeed } from '@/lib/try-rates';

type Bindings = {
  TRY_RATES?: KVNamespace;
  TRY_RATES_LIMIT?: { limit: (options: { key: string }) => Promise<{ success: boolean }> };
};

/** Answers GET /try/rates/{ecb|world|crypto} from KV, or 503 when the stored copy is missing or stale. */
export async function GET(request: Request, context: { params: Promise<{ feed: string }> }) {
  const { feed: name } = await context.params;
  if (!isFeedName(name)) return new Response('Unknown feed', { status: 404 });
  const bindings = env as unknown as Bindings;
  const client = request.headers.get('cf-connecting-ip') ?? 'local';
  if (bindings.TRY_RATES_LIMIT && !(await bindings.TRY_RATES_LIMIT.limit({ key: client })).success) {
    return new Response('Too many requests', { status: 429, headers: { 'Retry-After': '60' } });
  }
  const stored = bindings.TRY_RATES ? await readFeed(bindings.TRY_RATES, name) : null;
  if (!stored) return new Response('Rates unavailable', { status: 503 });
  return new Response(stored.body, {
    headers: {
      'Content-Type': name === 'ecb' ? 'application/xml; charset=utf-8' : 'application/json; charset=utf-8',
      'X-Volant-Fetched-At': String(stored.fetchedAt),
    },
  });
}
