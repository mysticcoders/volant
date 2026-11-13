// The website worker: vinext's request handler, the /try calculator module served straight from R2,
// and the Cron Trigger that refreshes the /try demo's exchange rates into KV. Visitor requests never
// fetch rates themselves.
import handler from 'vinext/server/fetch-handler';
import { serveCalculator } from '../lib/try-calculator';
import { refreshFeeds, schedules } from '../lib/try-rates';

type Env = { TRY_RATES?: KVNamespace; TRY_CALCULATOR?: R2Bucket };

const calculatorPath = '/try/calculator/';

const worker = {
  /** Serves the calculator module ahead of vinext (see lib/try-calculator.ts); everything else through vinext. */
  fetch(request: Request, env: Env, context: ExecutionContext) {
    const { pathname } = new URL(request.url);
    if (pathname.startsWith(calculatorPath)) return serveCalculator(request, env.TRY_CALCULATOR, pathname.slice(calculatorPath.length));
    return handler.fetch(request, env, context);
  },

  /** Refreshes the feeds the firing schedule covers; does nothing without the KV binding. */
  scheduled(controller: ScheduledController, env: Env, context: ExecutionContext) {
    const names = schedules[controller.cron] ?? [];
    if (!env.TRY_RATES || names.length === 0) return;
    context.waitUntil(refreshFeeds(env.TRY_RATES, names));
  },
};

export default worker;
