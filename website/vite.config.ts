import tailwindcss from '@tailwindcss/postcss';
import vinext from 'vinext';
import { defineConfig } from 'vite';

// macOS Seatbelt blocks FSEvents, so Codex previews need polling for HMR.
const isCodexSeatbeltSandbox = process.env.CODEX_SANDBOX === 'seatbelt';

const localBindingConfig = {
  name: 'volant-marketing',
  workers_dev: true,
  account_id: '55b50ebf1d3295768fc53dd77cb0e2e6',
  routes: [{ pattern: 'usevolant.com', custom_domain: true }],
  // vinext's handler plus the Cron Trigger that refreshes the /try demo's exchange rates.
  main: './worker/index.ts',
  compatibility_date: '2026-05-15',
  compatibility_flags: ['nodejs_compat'],
  // The /try calculator module, in a private bucket served only through /try/calculator/.
  r2_buckets: [{ binding: 'TRY_CALCULATOR', bucket_name: 'volant-try' }],
  // /try exchange rates written by the Cron Trigger and read by /try/rates/*.
  kv_namespaces: [{ binding: 'TRY_RATES', id: 'd2bbde17df6242c39627641c6d0ad41f' }],
  // ECB and ExchangeRate-API every 6 hours, CoinGecko every 5 minutes (lib/try-rates.ts).
  triggers: { crons: ['0 */6 * * *', '*/5 * * * *'] },
  // 60 /try/rates requests a minute per client address.
  ratelimits: [{ name: 'TRY_RATES_LIMIT', namespace_id: '1001', simple: { limit: 60, period: 60 as const } }],
};

export default defineConfig(async () => {
  // Keep Wrangler and Miniflare state project-local. These are non-secret tool
  // settings; application environment belongs in ignored `.env*` files.
  process.env.WRANGLER_WRITE_LOGS ??= 'false';
  process.env.WRANGLER_LOG_PATH ??= '.wrangler/logs';
  process.env.MINIFLARE_REGISTRY_PATH ??= '.wrangler/registry';

  // Wrangler snapshots its log path while the Cloudflare plugin is imported.
  const { cloudflare } = await import('@cloudflare/vite-plugin');

  return {
    css: { postcss: { plugins: [tailwindcss()] } },
    server: isCodexSeatbeltSandbox
      ? { watch: { useFsEvents: false, usePolling: true } }
      : undefined,
    plugins: [
      vinext(),
      cloudflare({
        viteEnvironment: { name: 'rsc', childEnvironments: ['ssr'] },
        config: localBindingConfig,
      }),
    ],
  };
});
