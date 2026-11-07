// Serves the /try calculator module from the private R2 bucket bound as TRY_CALCULATOR. The bucket
// holds a brotli and a gzip copy of each module; the response carries the one the client accepts
// with Content-Encoding and encodeBody: 'manual', so the runtime passes the stored bytes through and
// the browser decodes them natively. It runs in worker/index.ts ahead of vinext, which rebuilds
// route-handler responses and would drop encodeBody (the runtime then compressed the bytes again).
// The file name carries the module's content hash, so a response can be cached for a year.

/** Answers GET /try/calculator/VolantAnswers-<hash>.wasm with its brotli or gzip copy, or 404/406. */
export async function serveCalculator(request: Request, bucket: R2Bucket | undefined, file: string): Promise<Response> {
  if (!/^VolantAnswers-[0-9a-f]{16}\.wasm$/.test(file) || request.method !== 'GET') return new Response('Not found', { status: 404 });
  // Cloudflare rewrites Accept-Encoding before the worker sees it; the client's own header is
  // request.cf.clientAcceptEncoding, so a client without brotli (or plain HTTP) gets gzip.
  const cf = (request as Request & { cf?: { clientAcceptEncoding?: string } }).cf;
  const accepted = (cf?.clientAcceptEncoding ?? request.headers.get('accept-encoding') ?? '').toLowerCase();
  const encoding = /\bbr\b/.test(accepted) ? 'br' : /\bgzip\b/.test(accepted) ? 'gzip' : null;
  if (!encoding) return new Response('Needs brotli or gzip', { status: 406, headers: { Vary: 'Accept-Encoding' } });
  const object = bucket ? await bucket.get(`${file}.${encoding === 'br' ? 'br' : 'gz'}`) : null;
  if (!object) return new Response('Not found', { status: 404 });
  return new Response(object.body, {
    encodeBody: 'manual',
    headers: {
      'Content-Type': 'application/wasm',
      'Content-Encoding': encoding,
      'Content-Length': String(object.size),
      'Cache-Control': 'public, max-age=31536000, immutable',
      Vary: 'Accept-Encoding',
      ETag: object.httpEtag,
      'X-Content-Type-Options': 'nosniff',
    },
  } as ResponseInit);
}
