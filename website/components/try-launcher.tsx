'use client';
import Image from 'next/image';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

type Filter = { id: string; title: string };
type Preference = { id: string; type: string; default?: unknown };
type Manifest = {
  id: string;
  name: string;
  version: string;
  module: string;
  abiVersion?: number;
  capabilities: string[];
  hosts?: string[];
  output?: string;
  mode?: string;
  placeholder?: string;
  timeoutSeconds?: number;
  icon?: string;
  filters?: Filter[];
  preferences?: Preference[];
  storage?: boolean;
};
type Badge = { text: string; symbol?: string };
type Row = {
  title: string;
  subtitle?: string;
  url?: string;
  secondaryURL?: string;
  badges?: Badge[];
  copy?: { text?: string };
};
type Samples = { capturedAt: string; now: number; responses: Record<string, { status: number; body: string }> };
type Extension = { folder: string; keywords: string[]; manifest: Manifest };
type Call = { output?: string; error?: string; ms?: number };
type Reply = { items?: unknown; fetch?: string[]; state?: string; storage?: unknown; notice?: string };
type Outcome = { items: Row[]; missed: boolean; notice: string | null; storage?: unknown };
type CalcAnswer = { input: string; inputDetail?: string; result: string; resultDetail?: string; copyText: string };
type FeedName = 'ecb' | 'world' | 'crypto';
type FeedBody = { body: string; fetchedAt: number };
type CalcState = 'idle' | 'loading' | 'preparing' | 'ready' | 'error';
type CalcProgress = { received: number; total: number };
type CalcMessage = Call & {
  id?: number;
  progress?: CalcProgress;
  preparing?: boolean;
  loaded?: boolean;
  loadError?: boolean;
  cached?: boolean;
  downloadedMs?: number;
  compiledMs?: number;
};

/** The calculator's load status in words: "Loading Volant's calculator… 42%", "Preparing…". */
function loadLabel(state: CalcState, progress: CalcProgress | null, short = false) {
  const percent = progress && progress.total ? Math.min(100, Math.floor((progress.received / progress.total) * 100)) : null;
  if (state === 'preparing') return short ? 'Calculator preparing…' : 'Preparing Volant’s calculator…';
  const prefix = short ? 'Calculator loading…' : 'Loading Volant’s calculator…';
  return percent === null ? prefix : `${prefix} ${percent}%`;
}

/** The visitor's IANA zone and locale, so answers read as the app's would on their Mac. */
function visitorContext() {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  const locale = (typeof navigator !== 'undefined' ? navigator.language : 'en-US').replace('-', '_');
  return { zone, locale };
}

/** The required attribution for each rates feed, as the app's currency cards and About give it. */
const feedCredits: Record<FeedName, { text: string; href: string }> = {
  ecb: { text: 'European Central Bank reference rates', href: 'https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html' },
  world: { text: 'Rates By Exchange Rate API', href: 'https://www.exchangerate-api.com' },
  crypto: { text: 'Data provided by CoinGecko', href: 'https://www.coingecko.com' },
};

/** The extensions the demo ships, by folder, with the words that find their command row. */
const shipped: { folder: string; keywords: string[] }[] = [
  { folder: 'hackernews', keywords: ['hn', 'hacker news', 'news'] },
  { folder: 'lobsters', keywords: ['lobsters', 'lobste.rs', 'news'] },
  { folder: 'wikipedia', keywords: ['wiki', 'wikipedia'] },
  { folder: 'case', keywords: ['case', 'camel', 'snake', 'kebab'] },
  { folder: 'encode', keywords: ['encode', 'base64', 'url'] },
  { folder: 'fancytext', keywords: ['fancy', 'unicode', 'bold'] },
  { folder: 'characters', keywords: ['characters', 'chars', 'symbol', 'unicode'] },
  { folder: 'wordcount', keywords: ['count', 'words', 'wordcount'] },
  { folder: 'hello', keywords: ['hello', 'hi'] },
];

const wikiSamples = ['WebAssembly', 'Swift (programming language)', 'macOS', 'Raycast'];
const maximumRounds = 3;

/** Picks the units Volant would send: US customary for a US locale, otherwise metric. */
function units() {
  return typeof navigator !== 'undefined' && /-US$/i.test(navigator.language) ? 'us' : 'metric';
}

/** Keeps only http and https links, the schemes a demo row may open. */
function safeLink(value?: unknown) {
  if (typeof value !== 'string') return undefined;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : undefined;
  } catch {
    return undefined;
  }
}

/** Collapses text to one line of at most `max` characters, or undefined when it isn't text. */
function line(text: unknown, max = 200) {
  return typeof text === 'string' ? text.replace(/\s+/g, ' ').slice(0, max) : undefined;
}

/** Trims a module's rows to what Volant would show: at most 100, one line each, safe links only. */
function sanitize(items: unknown): Row[] {
  if (!Array.isArray(items)) throw new Error('Extension returned malformed rows');
  return items.slice(0, 100).flatMap((item) => {
    if (!item || typeof item.title !== 'string' || !item.title.trim()) return [];
    const badges = Array.isArray(item.badges)
      ? item.badges.slice(0, 3).flatMap((b: Badge) => (b && typeof b.text === 'string' && b.text.trim() ? [{ text: b.text.slice(0, 32) }] : []))
      : undefined;
    return [{
      title: line(item.title)!,
      subtitle: line(item.subtitle),
      url: safeLink(item.url),
      secondaryURL: safeLink(item.secondaryURL),
      badges,
      copy: item.copy && typeof item.copy.text === 'string' ? { text: item.copy.text.slice(0, 65536) } : undefined,
    }];
  });
}

/** Runs a list extension the way Volant does: render directly when it declares no hosts, otherwise
 * plan, replay the recorded responses for exactly the planned URLs, and render, at most three rounds. */
async function runList(ext: Extension, base: Record<string, unknown>, samples: Samples | null, call: (request: string) => Promise<Call>): Promise<Outcome> {
  const parse = (result: Call): Reply => {
    if (result.error) throw new Error(result.error);
    return JSON.parse(result.output ?? '') as Reply;
  };
  const hosts = ext.manifest.hosts ?? [];
  let missed = false;
  let reply = parse(await call(JSON.stringify({ phase: hosts.length ? 'plan' : 'render', ...base })));
  let round = 0;
  while (hosts.length && !reply.items && reply.fetch) {
    round += 1;
    if (round > maximumRounds) throw new Error('Extension kept asking for more pages');
    const responses = reply.fetch.slice(0, 4).map((url) => {
      if (!hosts.includes(new URL(url).hostname)) throw new Error('Extension planned a host it doesn’t declare');
      const recorded = samples?.responses[url];
      if (!recorded) missed = true;
      return { url, status: recorded?.status ?? 0, body: recorded?.body ?? '' };
    });
    reply = parse(await call(JSON.stringify({ phase: 'render', ...base, responses, ...(reply.state ? { state: reply.state } : {}) })));
  }
  return { items: sanitize(reply.items), missed, notice: reply.notice ? String(reply.notice).slice(0, 120) : null, storage: reply.storage };
}

/** An extension's icon from its own folder. */
function Icon({ ext, size }: { ext: Extension; size: number }) {
  return ext.manifest.icon
    ? <Image unoptimized src={`/try/extensions/${ext.folder}/${ext.manifest.icon}`} alt="" width={size} height={size} />
    : <span className="try-icon-blank" aria-hidden />;
}

/** The interactive demo: a launcher-like field that finds extension commands and runs real
 * extension modules in a Worker, replaying recorded responses for network extensions. */
/** The interactive demo. `initialQuery` comes from the homepage hero (/try?q=…): the field starts
 * with it, keeps focus, and the calculator starts loading at once rather than when the page is idle. */
export function TryLauncher({ initialQuery = '' }: { initialQuery?: string }) {
  const [extensions, setExtensions] = useState<Extension[]>([]);
  const [samples, setSamples] = useState<Samples | null>(null);
  const [query, setQuery] = useState(initialQuery.slice(0, 200));
  const handedOff = useRef(initialQuery.trim().length > 0);
  const [scope, setScope] = useState<Extension | null>(null);
  const [filter, setFilter] = useState<string | undefined>();
  const [rows, setRows] = useState<Row[]>([]);
  const [text, setText] = useState<string | null>(null);
  const [selected, setSelected] = useState(0);
  const [status, setStatus] = useState<'idle' | 'running' | 'error'>('idle');
  const [message, setMessage] = useState<string | null>(null);
  const [sampleMiss, setSampleMiss] = useState(false);
  const [timing, setTiming] = useState<number | null>(null);
  const worker = useRef<Worker | null>(null);
  const pending = useRef(new Map<number, (call: Call) => void>());
  const nextCall = useRef(0);
  const generation = useRef(0);
  const storage = useRef(new Map<string, unknown>());
  const input = useRef<HTMLInputElement>(null);
  const [calcAnswers, setCalcAnswers] = useState<CalcAnswer[]>([]);
  const [calcQuery, setCalcQuery] = useState('');
  const [calcState, setCalcState] = useState<CalcState>('idle');
  const [calcLoad, setCalcLoad] = useState<string | null>(null);
  const [calcProgress, setCalcProgress] = useState<CalcProgress | null>(null);
  const [readyFlash, setReadyFlash] = useState(false);
  const [barVisible, setBarVisible] = useState(false);
  const barShown = useRef(false);
  const barTimer = useRef<number | undefined>(undefined);
  const [credits, setCredits] = useState<FeedName[]>([]);
  const [ratesNote, setRatesNote] = useState<string | null>(null);
  const [fetchingRates, setFetchingRates] = useState(false);
  const calcWorker = useRef<Worker | null>(null);
  const calcPending = useRef(new Map<number, (call: Call) => void>());
  const calcGeneration = useRef(0);
  const feedBodies = useRef(new Map<FeedName, FeedBody>());

  /** Starts the calculator worker and asks it to load in the background; waiting calls on an old
   * one fail. Progress, preparing, ready and failure arrive as messages. */
  const startCalculator = useCallback(() => {
    calcWorker.current?.terminate();
    for (const resolve of calcPending.current.values()) resolve({ error: 'Calculator stopped' });
    calcPending.current.clear();
    const created = new Worker('/try/calculator-worker.js', { type: 'module' });
    created.onmessage = (event: MessageEvent<CalcMessage>) => {
      const data = event.data;
      if (data.progress) { setCalcState('loading'); setCalcProgress(data.progress); return; }
      if (data.preparing) { setCalcState('preparing'); return; }
      if (data.loadError) { setCalcState('error'); return; }
      if (data.loaded) {
        window.clearTimeout(barTimer.current);
        setCalcState('ready');
        setCalcLoad(`Calculator loaded${data.cached ? ' from cache' : ''} in ${Math.round((data.downloadedMs ?? 0) + (data.compiledMs ?? 0))} ms`);
        if (barShown.current) {
          setReadyFlash(true);
          window.setTimeout(() => { setReadyFlash(false); setBarVisible(false); barShown.current = false; }, 1600);
        }
        return;
      }
      const resolve = calcPending.current.get(event.data.id ?? -1);
      calcPending.current.delete(event.data.id ?? -1);
      resolve?.(event.data);
    };
    calcWorker.current = created;
    setCalcState('loading');
    setCalcProgress(null);
    // The bar appears only if loading takes a while, so a cached module never flashes it.
    window.clearTimeout(barTimer.current);
    barTimer.current = window.setTimeout(() => { barShown.current = true; setBarVisible(true); }, 400);
    created.postMessage({ preload: true });
  }, []);

  /** Sends one request to the calculator; one sent while it loads waits up to five minutes for
   * the download, later ones get 3 s. */
  const callCalculator = useCallback((request: Record<string, unknown>, loading: boolean) => new Promise<Call>((resolve) => {
    if (!calcWorker.current) startCalculator();
    const id = ++nextCall.current;
    const timer = setTimeout(() => {
      calcPending.current.delete(id);
      startCalculator();
      resolve({ error: 'The calculator took too long and was stopped' });
    }, loading ? 300_000 : 3000);
    calcPending.current.set(id, (result) => { clearTimeout(timer); resolve(result); });
    calcWorker.current?.postMessage({ id, request: JSON.stringify(request) });
  }), [startCalculator]);

  /** Fetches one rates feed from the site's own route, once per visit. */
  const feed = useCallback(async (name: FeedName): Promise<FeedBody | null> => {
    const known = feedBodies.current.get(name);
    if (known) return known;
    try {
      const response = await fetch(`/try/rates/${name}`);
      if (!response.ok) return null;
      const body = { body: await response.text(), fetchedAt: Number(response.headers.get('x-volant-fetched-at')) || Math.floor(Date.now() / 1000) };
      feedBodies.current.set(name, body);
      return body;
    } catch {
      return null;
    }
  }, []);

  /** Answers a top-level query with VolantCore's calculator: asks which rate feeds it needs,
   * fetches only those, then asks for the answers with the feeds attached. */
  const calculate = useCallback(async (typed: string) => {
    const mine = ++calcGeneration.current;
    if (calcState === 'error') return;
    const loading = calcState !== 'ready';
    const context = { ...visitorContext(), now: Math.floor(Date.now() / 1000) };
    const needs = await callCalculator({ ...context, mode: 'feeds', query: typed }, loading);
    if (mine !== calcGeneration.current) return;
    if (needs.error) { setCalcAnswers([]); return; }
    const wanted = JSON.parse(needs.output ?? '{}') as { rates?: boolean; world?: boolean; crypto?: boolean };
    const names: FeedName[] = [...(wanted.rates ? ['ecb' as const] : []), ...(wanted.world ? ['world' as const] : []), ...(wanted.crypto ? ['crypto' as const] : [])];
    const fresh = names.some((name) => !feedBodies.current.has(name));
    if (fresh) setFetchingRates(true);
    const bodies = await Promise.all(names.map(async (name) => [name, await feed(name)] as const));
    if (fresh) setFetchingRates(false);
    if (mine !== calcGeneration.current) return;
    const request: Record<string, unknown> = { ...context, query: typed };
    for (const [name, body] of bodies) {
      if (!body) continue;
      request[name] = body.body;
      if (name === 'crypto') request.cryptoFetchedAt = body.fetchedAt;
    }
    const result = await callCalculator(request, false);
    if (mine !== calcGeneration.current) return;
    if (result.error) { setCalcAnswers([]); setRatesNote(null); return; }
    const answers = (JSON.parse(result.output ?? '[]') as CalcAnswer[]).slice(0, 5);
    setCalcAnswers(answers);
    setCalcQuery(typed);
    const missing = bodies.some(([, body]) => !body);
    setRatesNote(names.length && missing ? 'Live rates aren’t available here right now; Volant fetches them in the app.' : null);
    // Credit only the feed an answer's own tag names: one conversion never mixes ECB and
    // ExchangeRate-API, and a coin's price comes from CoinGecko.
    const tags = answers.map((a) => a.resultDetail ?? '').join(' ');
    const used: FeedName[] = [];
    if (/CoinGecko/.test(tags)) used.push('crypto');
    else if (/Exchange Rate API/.test(tags)) used.push('world');
    else if (/ECB/.test(tags)) used.push('ecb');
    setCredits(used);
  }, [calcState, callCalculator, feed]);

  /** Starts a fresh worker; any calls still waiting on the old one fail. */
  const startWorker = useCallback(() => {
    worker.current?.terminate();
    for (const resolve of pending.current.values()) resolve({ error: 'Extension stopped' });
    pending.current.clear();
    const created = new Worker('/try/worker.js', { type: 'module' });
    created.onmessage = (event: MessageEvent<Call & { id: number }>) => {
      const resolve = pending.current.get(event.data.id);
      pending.current.delete(event.data.id);
      resolve?.(event.data);
    };
    worker.current = created;
  }, []);

  useEffect(() => {
    startWorker();
    const field = input.current;
    field?.focus();
    if (field) field.setSelectionRange(field.value.length, field.value.length);
    // The calculator downloads in the background once the page is idle; typing never waits for it.
    // Text handed over from the homepage hero starts it at once.
    const idle = handedOff.current
      ? window.setTimeout(() => startCalculator(), 0)
      : typeof window.requestIdleCallback === 'function'
        ? window.requestIdleCallback(() => startCalculator(), { timeout: 2000 })
        : window.setTimeout(() => startCalculator(), 300);
    Promise.all(shipped.map(async ({ folder, keywords }) => {
      const manifest = (await (await fetch(`/try/extensions/${folder}/manifest.json`)).json()) as Manifest;
      return { folder, keywords, manifest };
    })).then(setExtensions, () => setMessage('Couldn’t load the demo extensions.'));
    fetch('/try/samples.json').then((r) => r.json() as Promise<Samples>).then(setSamples, () => setSamples(null));
    return () => {
      if (typeof window.cancelIdleCallback === 'function') window.cancelIdleCallback(idle);
      window.clearTimeout(idle);
      worker.current?.terminate();
      calcWorker.current?.terminate();
    };
  }, [startWorker, startCalculator]);

  useEffect(() => {
    const typed = query.trim();
    if (scope || !typed) return;
    const timer = setTimeout(() => void calculate(typed), 150);
    return () => clearTimeout(timer);
  }, [scope, query, calculate]);

  /** Runs one module call with the extension's time limit, terminating the worker if it overruns. */
  const call = useCallback((ext: Extension, request: string) => new Promise<Call>((resolve) => {
    const id = ++nextCall.current;
    const limit = Math.min(10, Math.max(0.5, ext.manifest.timeoutSeconds ?? 2)) * 1000;
    const timer = setTimeout(() => {
      pending.current.delete(id);
      startWorker();
      resolve({ error: 'Extension took too long and was stopped' });
    }, limit);
    pending.current.set(id, (result) => { clearTimeout(timer); resolve(result); });
    worker.current?.postMessage({
      id, name: ext.folder, file: ext.manifest.module, abi: ext.manifest.abiVersion ?? 1,
      capabilities: ext.manifest.capabilities, input: request,
    });
  }), [startWorker]);

  /** Runs the scoped extension for the typed text, dropping the reply if a newer run started. */
  const run = useCallback(async (ext: Extension, typed: string, chosenFilter?: string) => {
    const mine = ++generation.current;
    const started = performance.now();
    setStatus('running');
    setMessage(null);
    const current = () => mine === generation.current;
    try {
      if (ext.manifest.output !== 'items') {
        const result = await call(ext, typed);
        if (!current()) return;
        if (result.error) throw new Error(result.error);
        setRows([]); setText(result.output ?? ''); setSampleMiss(false);
      } else {
        const network = (ext.manifest.hosts ?? []).length > 0;
        const preferences = Object.fromEntries((ext.manifest.preferences ?? []).filter((p) => p.default !== undefined).map((p) => [p.id, p.default]));
        const base = {
          query: typed, now: network && samples ? samples.now : Math.floor(Date.now() / 1000), units: units(),
          ...(chosenFilter ? { filter: chosenFilter } : {}),
          ...(Object.keys(preferences).length ? { preferences } : {}),
          ...(ext.manifest.storage && storage.current.has(ext.folder) ? { storage: storage.current.get(ext.folder) } : {}),
        };
        const outcome = await runList(ext, base, samples, (request) => call(ext, request));
        if (!current()) return;
        if (outcome.storage !== undefined) storage.current.set(ext.folder, outcome.storage);
        setText(null); setRows(outcome.items); setSelected(0); setSampleMiss(outcome.missed); setMessage(outcome.notice);
      }
      setStatus('idle');
      setTiming(performance.now() - started);
    } catch (error) {
      if (!current()) return;
      setStatus('error'); setRows([]); setText(null); setTiming(null);
      setMessage(error instanceof Error ? error.message : String(error));
    }
  }, [call, samples]);

  useEffect(() => {
    if (!scope) return;
    const typed = query.trim();
    if ((scope.manifest.mode === 'search' || scope.manifest.output !== 'items') && !typed) return;
    const timer = setTimeout(() => void run(scope, typed, filter), 150);
    return () => clearTimeout(timer);
  }, [scope, query, filter, run]);

  const commands = useMemo(() => {
    const words = query.trim().toLowerCase();
    if (scope) return [];
    if (!words) return extensions;
    return extensions.filter((e) => e.manifest.name.toLowerCase().includes(words) || e.keywords.some((k) => k.startsWith(words) || words.startsWith(k + ' ')));
  }, [extensions, query, scope]);

  /** Changes the typed text; inside a search extension an emptied field clears its rows at once. */
  const type = (value: string) => {
    setQuery(value);
    setSelected(0);
    if (!scope && !value.trim()) {
      calcGeneration.current++;
      setCalcAnswers([]); setCredits([]); setRatesNote(null);
    }
    if (scope && !value.trim() && (scope.manifest.mode === 'search' || scope.manifest.output !== 'items')) {
      generation.current++;
      setRows([]); setText(null); setStatus('idle'); setMessage(null); setTiming(null);
    }
  };

  /** Enters an extension's scope, carrying any words typed after its keyword. */
  const enter = (ext: Extension) => {
    const words = query.trim();
    const keyword = ext.keywords.find((k) => words.toLowerCase().startsWith(k + ' '));
    calcGeneration.current++;
    setCalcAnswers([]); setCredits([]); setRatesNote(null);
    setScope(ext);
    setFilter(ext.manifest.filters?.[0]?.id);
    setQuery(keyword ? words.slice(keyword.length).trim() : '');
    setRows([]); setText(null); setSelected(0); setMessage(null); setTiming(null); setSampleMiss(false);
    input.current?.focus();
  };

  /** Leaves the scope for the demo's own search with an empty field. */
  const leave = () => {
    generation.current++;
    setScope(null); setQuery(''); setRows([]); setText(null); setMessage(null); setStatus('idle'); setSampleMiss(false); setTiming(null); setSelected(0);
    input.current?.focus();
  };

  /** Opens a row's link, or copies its text when it has none. */
  const activate = async (row: Row | undefined, secondary = false) => {
    if (!row) return;
    const link = secondary ? row.secondaryURL ?? row.url : row.url;
    if (link) { window.open(link, '_blank', 'noopener,noreferrer'); return; }
    try { await navigator.clipboard.writeText(row.copy?.text ?? row.title); setMessage('Copied'); } catch { setMessage('Couldn’t copy in this browser'); }
  };

  // Answers show only for the text they were computed from, never a previous query's.
  const answersShown = scope || !query.trim() || calcQuery !== query.trim() ? [] : calcAnswers;
  const count = scope ? (text !== null ? 1 : rows.length) : answersShown.length + commands.length;

  /** Keyboard navigation in the launcher's own terms: arrows move, Return runs, Command-Return
   * opens a second link, Tab enters a command, Escape clears then leaves, Delete on empty leaves. */
  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowDown') { event.preventDefault(); setSelected((s) => Math.min(count - 1, s + 1)); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); setSelected((s) => Math.max(0, s - 1)); }
    else if (event.key === 'Enter') {
      event.preventDefault();
      if (!scope && selected < answersShown.length) void activate({ title: answersShown[selected].copyText });
      else if (!scope) { const ext = commands[selected - answersShown.length]; if (ext) enter(ext); }
      else if (text !== null) void activate({ title: text });
      else void activate(rows[selected], event.metaKey || event.ctrlKey);
    } else if (event.key === 'Tab' && !scope && commands[selected - answersShown.length]) { event.preventDefault(); enter(commands[selected - answersShown.length]); }
    else if (event.key === 'Escape') { event.preventDefault(); if (query) type(''); else if (scope) leave(); }
    else if (event.key === 'Backspace' && !query && scope) { event.preventDefault(); leave(); }
  };

  const placeholder = scope ? scope.manifest.placeholder ?? `Search ${scope.manifest.name}…` : 'Calculate, convert, or type an extension such as hn…';
  const network = !!scope && (scope.manifest.hosts ?? []).length > 0;
  const capturedOn = samples ? new Date(samples.capturedAt).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' }) : null;
  const waiting = !!scope && (scope.manifest.mode === 'search' || scope.manifest.output !== 'items') && !query.trim();
  let note = 'Real Volant extensions, running in your browser';
  if (network && capturedOn) note = sampleMiss ? `Sample data from ${capturedOn} doesn’t cover this search.` : `Sample data recorded ${capturedOn}. In the app, Volant fetches it live.`;
  else if (scope) note = `${scope.manifest.name} ${scope.manifest.version} · running in your browser`;
  else if (answersShown.length && calcLoad) note = `Volant’s own calculator, compiled to WebAssembly · ${calcLoad}`;

  return (
    <section className="try-launcher" aria-label="Volant demo running in your browser">
      <div className="try-bar">
        {scope ? (
          <button type="button" className="try-chip" onClick={leave} aria-label={`Leave ${scope.manifest.name}`}>
            <span aria-hidden>‹</span>
            <Icon ext={scope} size={16} />
            {scope.manifest.name}
          </button>
        ) : null}
        <input
          ref={input}
          value={query}
          onChange={(e) => type(e.target.value)}
          onKeyDown={onKeyDown}
          placeholder={placeholder}
          aria-label="Search"
          spellCheck={false}
          autoComplete="off"
        />
        {scope?.manifest.filters?.length ? (
          <select className="try-filter" value={filter} onChange={(e) => setFilter(e.target.value)} aria-label={`${scope.manifest.name} filter`}>
            {scope.manifest.filters.map((f) => <option key={f.id} value={f.id}>{f.title}</option>)}
          </select>
        ) : null}
      </div>
      {calcState === 'error' || (barVisible && (calcState === 'loading' || calcState === 'preparing' || readyFlash)) ? (
        <div className="try-progress" data-state={calcState}>
          {calcState === 'error' ? (
            <span className="try-progress-label">
              Couldn’t load the calculator.
              <button type="button" className="try-suggestion" onClick={() => startCalculator()}>Retry</button>
            </span>
          ) : (
            <>
              <span className="try-progress-label" aria-live="polite">{calcState === 'ready' ? 'Calculator ready' : loadLabel(calcState, calcProgress)}</span>
              <progress
                className="try-visually-hidden"
                aria-label="Loading Volant’s calculator"
                max={100}
                value={calcState === 'loading' && calcProgress?.total ? Math.floor((calcProgress.received / calcProgress.total) * 100) : calcState === 'ready' ? 100 : undefined}
              />
              <span className="try-progress-track" aria-hidden>
                <span
                  className={`try-progress-fill${calcState === 'preparing' || !calcProgress?.total ? ' indeterminate' : ''}`}
                  style={calcState === 'loading' && calcProgress?.total ? { width: `${Math.min(100, (calcProgress.received / calcProgress.total) * 100)}%` } : calcState === 'ready' ? { width: '100%' } : undefined}
                />
              </span>
            </>
          )}
        </div>
      ) : null}
      <ul className="try-results" aria-label="Results">
        {answersShown.map((answer, i) => (
          <li key={`calc-${i}-${answer.result}`}>
            <button type="button" aria-current={i === selected} className="try-row try-answer" onMouseEnter={() => setSelected(i)} onClick={() => void activate({ title: answer.copyText })}>
              <span className="try-row-text">
                <span className="try-answer-result">{answer.result}</span>
                <span className="try-subtitle">{answer.input}{answer.inputDetail ? ` · ${answer.inputDetail}` : ''}</span>
              </span>
              {answer.resultDetail ? <span className="try-kind">{answer.resultDetail}</span> : null}
            </button>
          </li>
        ))}
        {!scope && commands.map((ext, j) => {
          const i = j + answersShown.length;
          return (
          <li key={ext.folder}>
            <button type="button" aria-current={i === selected} className="try-row" onMouseEnter={() => setSelected(i)} onClick={() => enter(ext)}>
              <Icon ext={ext} size={22} />
              <span className="try-row-text">
                <span className="try-title">{ext.manifest.name}</span>
                <span className="try-subtitle">{ext.manifest.placeholder ?? 'Extension'}</span>
              </span>
              <span className="try-kind">{(ext.manifest.hosts ?? []).length ? 'Extension · sample data' : 'Extension'}</span>
            </button>
          </li>
          );
        })}
        {scope && text !== null ? (
          <li>
            <button type="button" aria-current className="try-row" onClick={() => void activate({ title: text })}>
              <Icon ext={scope} size={22} />
              <span className="try-row-text"><span className="try-title">{text}</span></span>
              <span className="try-kind">Return copies</span>
            </button>
          </li>
        ) : null}
        {scope && rows.map((row, i) => (
          <li key={`${i}-${row.title}`}>
            <button type="button" aria-current={i === selected} className="try-row" onMouseEnter={() => setSelected(i)} onClick={(e) => void activate(row, e.metaKey || e.ctrlKey)}>
              <Icon ext={scope} size={22} />
              <span className="try-row-text">
                <span className="try-title">{row.title}</span>
                {row.subtitle ? <span className="try-subtitle">{row.subtitle}</span> : null}
              </span>
              {row.badges?.length ? <span className="try-badges">{row.badges.map((b, j) => <span key={j} className="try-badge">{b.text}</span>)}</span> : null}
            </button>
          </li>
        ))}
      </ul>
      {!scope && query.trim() && (calcState === 'loading' || calcState === 'preparing' || calcState === 'idle') ? (
        <p className="try-empty" aria-live="polite">{loadLabel(calcState, calcProgress, true)} Answers appear when it’s ready.</p>
      ) : null}
      {!scope && query.trim() && fetchingRates ? <p className="try-empty">Fetching exchange rates…</p> : null}
      {!scope && extensions.length > 0 && commands.length === 0 && answersShown.length === 0 && calcState === 'ready' && calcQuery === query.trim() && !fetchingRates ? (
        <p className="try-empty">Nothing matches “{query.trim()}”. Files, contacts, clipboard and AI run only in the app.</p>
      ) : null}
      {!scope && ratesNote && calcQuery === query.trim() ? <p className="try-empty">{ratesNote}</p> : null}
      {!scope && credits.length && answersShown.length ? (
        <p className="try-hint">
          {credits.map((name, i) => (
            <span key={name}>{i ? ' · ' : ''}<a href={feedCredits[name].href} target="_blank" rel="noopener noreferrer">{feedCredits[name].text}</a></span>
          ))}
        </p>
      ) : null}
      {scope && status === 'running' && rows.length === 0 && text === null ? <p className="try-empty">Running {scope.manifest.name}…</p> : null}
      {waiting ? <p className="try-empty">{scope?.manifest.output === 'items' ? scope?.manifest.placeholder ?? 'Type to search' : 'Type a name'}.</p> : null}
      {status === 'error' && message ? <p className="try-error">{message}</p> : null}
      {scope?.folder === 'wikipedia' && samples ? (
        <p className="try-hint">
          Sample searches:
          {wikiSamples.map((term) => <button type="button" key={term} className="try-suggestion" onClick={() => type(term)}>{term}</button>)}
        </p>
      ) : null}
      <div className="try-footer">
        <span className="try-footer-note">{note}{timing !== null && scope ? ` · ${Math.round(timing)} ms` : ''}</span>
        {status !== 'error' && message ? <span className="try-notice">{message}</span> : null}
        <span className="try-keys"><kbd>↩</kbd> {scope ? 'Open or copy' : selected < answersShown.length ? 'Copy' : 'Open'} <kbd>esc</kbd> {scope ? 'Back' : 'Clear'}</span>
      </div>
    </section>
  );
}
