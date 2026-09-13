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
