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
