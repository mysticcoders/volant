# ADR 0014: Releases ship through one script, approved by one merge

- **Status:** Accepted
- **Date:** 2026-10-09
- **Enforced by:** `Scripts/ship.sh` and its preflight (`tools/check-release-copy.py`)

## Context

A release touches signing, notarization, the Sparkle feed, the website and its download, and marketing copy. Done by hand or by an agent improvising steps, it is easy to publish a website that claims features the downloadable app lacks, ship an unsigned helper, or deploy before checks pass. Agents need a clear line between work they may do and publication, which only the owner approves.

## Decision

Releases ship only with `Scripts/ship.sh <version>` from a `release/<version>` branch holding the release notes and copy. The script opens one release PR and never merges it itself. **Merging the release PR is the publication approval**; the script then deploys, verifies and publishes. The website is never deployed outside this script. The owner asking for a release authorizes merging its release PR once every check on its latest commit has passed.

## Consequences

- Publication has one gate, a merge the owner can see, and one repeatable path.
- A failed step mid-release needs the script, not a manual fix, to finish correctly.
- Marketing claims, feature badges and download copy must be updated on the release branch together.
- See docs/release-quality.md.
