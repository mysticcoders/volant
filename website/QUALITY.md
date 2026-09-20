# Volant website decisions and release notes

The website uses the existing coral wing brand, graphite surfaces, semantic shared color variables, and a real fictional Live Notes fixture. This is deliberately a dark website (`color-scheme: dark`), including native controls. Product imagery is labeled as a development preview. Do not advertise a public download until a packaged release exists.

## Validation — September 13, 2026
- Production build and TypeScript check passed; lint passed for app, used Accordion, and utility files.
- Full scaffold lint reports pre-existing issues in unused generated UI components (roles, carousel effects, and chart template expressions). These are not used by this page.
- Browser: inspected full desktop and 390px mobile render. No horizontal overflow at 390px. FAQ expands by click and collapses by Enter; Live Notes anchor navigates correctly. Fixed offscreen skip-link styling after mobile full-page capture exposed it: use clipping while unfocused, not negative positioning alone.
- OS appearance switching, enlarged accessibility text, and physical mobile devices have not been verified. CSS explicitly fixes the website and native controls to dark.

## Next concrete work
1. Review copy and visual direction with owner.
2. Create a signed/notarized public app release before adding Download for Mac.
3. Choose and register a Volant domain, publish publicly, and connect DNS. Existing Vey domains may redirect after the canonical domain is chosen.
4. Add canonical metadata once the public domain is connected.

No forms, trackers, account collection, or DNS changes are included.

## Rename — September 13, 2026
Owner selected Volant. Product copy and metadata use Volant; the existing Sites project is retained; GitHub repository is now mysticcoders/volant. No claim to volant.com or new domain ownership is made.

Repository audit: mysticcoders/volant is private. Removed public-source claims and inaccessible source CTAs. Public deployment and canonical domain remain pending owner Cloudflare setup.

## Agent workflows feature order
Agent workflows now lead the feature sections and navigation; ACP and provider integrations are explicitly in development. Desktop 1440 and mobile 390 Chrome captures were inspected. Existing layout tokens reused. Privacy FAQ distinguishes the sandboxed app from the optional local helper. Full keyboard/browser theme checks were not repeated.

## Native product captures — September 14, 2026
Replaced the illustrative HTML hero launcher with the actual native SwiftUI view and release assets, using fictional Herdr panes. Added a full-size image link for small screens. The product uses coral accents and an optional expanded project/provider/status overview. Native light/dark captures were visually inspected; the website keeps its intentional dark theme. Desktop and 390px mobile renders inspected, with production build and TypeScript validation passing. Deployment is pending; download and notarization claims remain unchanged until the release is public. See `../docs/release-quality.md`.

Publication completed September 14, 2026 with owner approval on the existing Cloudflare setup. Live primary page content and the native screenshot were verified; screenshot SHA-256 matches the inspected local asset. The website update is now live at https://usevolant.com/. Release download and update feed remain unpublished.


## Packaged download — September 14, 2026
Published Volant 0.1.0 (build 2), notarized and stapled DMG, signed Sparkle appcast, and checksums under `/updates/`. Download for Mac buttons now link directly to `/updates/Volant-0.1.0.dmg`; FAQ includes drag-to-Applications instructions. Worker version `cd45f136-3ef1-4483-b70b-dbd65a5a74b5`. Live DMG and feed returned HTTP 200 and matched the validated artifacts. Downloaded DMG passed stapler and Gatekeeper verification. Desktop/mobile CTA renders inspected. See `docs/release-quality.md` in the repository for remaining installed-upgrade and hardware verification.

## Public source and hover contrast — September 14, 2026
Repository visibility is public with the existing MIT license. Added GitHub and X icons/links, source/license links in the FAQ, and footer links. Mystic Coders’ own website confirms the @mysticcoders Twitter account. Icons come from Simple Icons.

Hover defect: `.button.small` kept a transparent background while `.button:hover` supplied dark text. The small-button hover/focus styles now set a matching light-coral background and dark foreground explicitly, using semantic tokens. Actual pointer hover was inspected: background rgb(255,172,157), text rgb(32,21,19). Desktop/mobile links and expanded MIT FAQ were visually inspected; page lint and TypeScript passed.

## Open-source launch and 0.1.1

Published Cloudflare version `edc2b78b-084f-4a71-91cc-9e6ead8895ee`. Reviewed the open-source hero label and “Move faster with Volant” footer at desktop and 390px widths. Public accessibility tree confirms GitHub links, MIT copy and 0.1.1 download destinations. Production build, TypeScript and page lint pass. Downloaded public DMG checksum and signed appcast match the release; Gatekeeper and stapler accept the DMG.


## 0.1.3 download — September 15, 2026

Published the notarized 0.1.3 build-5 DMG and updated download URLs/version label through Cloudflare `bdb53f1a-09b7-41b8-a2ee-94f584b23bf6`. Production build, TypeScript and page lint passed. Public HTML links point to 0.1.3; a fresh DMG download exactly matches the local notarized bytes and passes Gatekeeper/stapler. Existing assets remain available. No layout or screenshot changes were made, so no additional visual review was claimed. Sparkle feed is updated only after this public-DMG verification.

## Documentation section and navigation — September 15, 2026
Added `/docs`: an index plus eleven pages (getting started, configuration, launcher, notes, clipboard and snippets, system control, Apple Shortcuts, agents, importing from Raycast, extensions, privacy and security), written against version 0.1.3 and sourced from the repository README and `docs/*.md`. Those source files are engineering validation reports; their evidence, "next work", and unverified-caveat sections are deliberately not published. Claims that are not established are labeled in place rather than smoothed over: Cursor ACP is marked unverified, and extensions are marked a spike with an unstable API.

Navigation: the header download button is now a compact coral `Download`, with the GitHub mark beside it in white, hovering to coral like the adjacent nav links. The mark is a `mask-image` over `/icons/github.svg` so its color is a single token rather than a `filter` chain. A `Docs` link replaces the old text `GitHub` nav item. `SiteHeader`/`SiteFooter` were extracted to `components/site-chrome.tsx` so the home page and docs cannot drift apart.

Internal navigation initially used `next/link`, which shipped broken navigation and was reverted to plain anchors the same day — see the next entry. The DMG was always a plain `<a download>` because it is an asset, not a route, and client-side navigation would break the download. Lint confirmed that distinction independently: the DMG link was never flagged by `no-html-link-for-pages`.

Validation: production build passed with all 13 routes; `oxlint` clean on authored files; `tsc --noEmit` clean. All routes returned HTTP 200 from the dev server. Desktop 1440 and mobile 390 renders of the home page and docs were inspected, and the masked icon was confirmed by computed style (white `rgb(255, 255, 255)` at 20x20 with the mask URL resolved) rather than by stylesheet inspection alone. Pre-existing lint issues in unused generated `components/ui` files are unchanged.

Defect found and fixed during validation: re-enabling `.nav .button` below 700px reintroduced horizontal overflow at 390px (`scrollWidth` 413 against a 390 viewport, offenders `.nav-actions` and `.button.small`). The original stylesheet hid that button on phones deliberately, and adding a fourth nav item made the row wider still. Phones now keep a text-only nav; the hero carries the download and the footer carries the source link. Re-measured at 390: no overflow on either page.

Second defect found by inspecting the render rather than the stylesheet: the prose rule `.docs-main a:not(.button)` also matched the index cards, underlining each card's title and summary. Whole-surface cards are now excluded, and a computed-style check confirms cards resolve to `none` while inline prose links still underline. Recurring lesson, consistent with the earlier transparent-background findings: a passing build and a correct-looking stylesheet are not evidence; look at the rendered page.

No performance or speed claims were added to the site; the matched Raycast comparison does not currently support one. No changes to `public/updates/`, the DMG, or the appcast.

## Broken internal navigation from next/link — September 15, 2026
The first documentation deploy (Worker version `667592bd-18ed-4f8b-9fb2-9019dfc54130`) published `/docs` but shipped **dead internal navigation**. Adopting `next/link` satisfied `no-html-link-for-pages` and added prefetching, but this site had never used `next/link` before: all internal links were plain anchors, so the framework's link path had never run here.

Symptoms in the production build only: 18-24 console errors per page, all `[vinext] RSC prefetch setup error: TypeError: d is not a function`, plus `TypeError: e is not a function` thrown from the click handler inside `startTransition`, both inside vinext's own `link-*.js` chunk. Because the handler calls `preventDefault` and then throws, neither client-side navigation nor the native anchor fallback ran, so clicking any internal link did nothing. Direct URLs were never affected; every route returned 200 throughout.

The dev server did not reproduce this. It was only visible against a production build, which is how it reached production. **Check the browser console against a production build (`wrangler dev --config dist/server/wrangler.json`), not just `vinext dev`, before deploying.** A clean dev console is not evidence.

Fix: reverted all 32 `Link` call sites to plain anchors, with a file-level `oxlint-disable next/no-html-link-for-pages` carrying the reason. Full page loads are appropriate for a static marketing and documentation site. Verified by trusted browser clicks on both a local production build and the live site: navigation succeeds, the sidebar current item updates, and console errors went from 22 to 0. Deployed as version `7565499b-d43a-47f7-86c5-4574fe167638`.

Not attempted: vinext `latest` is `1.0.0-beta.10` while this project pins `1.0.0-beta.5`, so the upstream defect may already be fixed. That is a five-release jump on a beta framework affecting every page, and it warrants its own deliberate upgrade and re-verification rather than being bundled into a hotfix.
