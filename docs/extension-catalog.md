# Extension catalog roadmap

## Current behavior

Installed commands appear by name in the launcher, with optional trailing text input. Return invokes the selected command. Approval remains opt-in: a master community switch plus an independent, hash-bound approval for every extension. Bundled commands have independent switches. Search caches metadata only and never executes a module.

The Base64 example adapts one unchanged Raycast TypeScript command to Volant's text input/output contract. This is not general Raycast, Node or React compatibility. There is no catalog service, downloader, automatic installer or extension updater yet.

## Next deliverable: a small curated catalog

Start with reviewed, user-invoked text utilities: Base64 encode/decode, URL encode/decode, UUID generation and JSON formatting. These are candidate categories, not claims that specific third-party plugins are compatible or approved for redistribution. Select actual upstream projects after reviewing source, dependencies, license/notices and maintainership. Credit upstream authors and publish the adapter changes and unsupported features.

Each listing should carry a stable Volant ID, publisher/source repository, pinned upstream revision, license and notices, supported platforms/ABI, command names, version, artifact hash, requested capabilities, maintenance status and compatibility notes. Rank usefulness and maintained quality rather than importing popularity rankings unquestioningly. Native Volant extensions and adapted upstream extensions should be clearly identified.

## Delivery sequence

1. Define a versioned catalog index and extension package format. Keep display metadata separate from executable artifacts and approval state. Establish publisher/reviewer identities and an authenticated release-signing policy.
2. Add download, verification and atomic installation with path/size validation, rollback and preserved user choices. Installation must not imply enablement or execution. Exercise malicious archives and mismatched hashes with isolated fixtures.
3. Add Settings catalog browsing and install/remove actions. Installed commands continue using launcher discovery and Enable and Run. Master-off behavior must remain explicit.
4. Add update discovery and review. The current policy requires fresh approval for changed bytes or permissions; a catalog must not silently relax it. Provide an explicit removal/revocation mechanism.
5. Curate a small initial set. For every adapter, test functionality, bounds, repeated-run footprint and supported macOS versions. Describe unavailable upstream UI, background behavior or APIs accurately.

## Separate runtime follow-up

Measure fresh helper footprint, repeated execution peaks and settled memory across mixed modules using fictional inputs. Then decide whether an idle shutdown/recycle policy improves memory without unacceptable cold-start delay. Disabling community code must not interrupt a bundled command. This lifecycle change is not implemented by direct-name discovery.

## Discovery quality decision

Symptom: installed extensions required a separate `ext` namespace despite being commands. Cause: only the explicit-prefix branch searched extension metadata. Change: merge direct metadata matches into ordinary launcher results, retain explicit-prefix compatibility and current activation gates. Avoid per-keystroke filesystem reads through metadata caching; invalidate on Settings/config refresh. Regression checks cover argument boundaries, Unicode/case preservation, discovery without executable bytes, explicit approval, app-name collisions and first-use navigation. Native fixtures render the affected launcher/Settings surfaces in light/dark appearances; signed installed-app execution remains separate evidence.
