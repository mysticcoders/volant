# Vey coral-wing A — macOS icon handoff

Selected artwork is preserved; only deterministic size exports were made with macOS sips. Source was generated with the built-in image-generation tool. Original prompt direction: pointed orange/coral folded wing, subtle V, warm ivory rounded-square tile, restrained satin relief.

## Deliverables
- `vey-mac-1024.png`: 1024 × 1024 Mac icon export.
- `VeyIcons.xcassets/AppIcon.appiconset`: ten macOS slots (16, 32, 128, 256, 512 points at 1x and 2x). The 512@2x image supplies 1024 pixels.
- `AppIcon.icns`: compiled by Xcode actool for macOS 15.0. The generated Assets.car is omitted from this source handoff.
- `render-proof.png`: AppKit-rendered 16/32/64/128/256-point proof on white and dark backgrounds, inspected visually. The fold loses detail at 16 pixels; the silhouette remains visible. Clear at 32 and above.
- `preview.html`: local browser preview, not an App Store Connect screenshot.

## Integration
The repository is now /Users/kinabalu/workspace/mystic/vey. No app source or build settings were changed in this icon preparation.
Copy the AppIcon.appiconset into the app asset catalog and set ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon on the Vey target. If no catalog exists, copy VeyIcons.xcassets under Vey/Resources and ensure the project includes it. Build the actual Release archive and verify the generated CFBundleIconName/CFBundleIconFile and bundled asset resources.
Apple obtains the listing icon from the uploaded build: https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon

## Evidence and limitations
PNG header checks passed for all ten declared dimensions. actool exited 0 and produced the ICNS, CAR, and icon-info plist. The tool emitted sandbox-related CoreSimulator service diagnostics; this was a macOS asset compilation and did produce its expected outputs. A complete app archive and App Store Connect upload/processing have not been verified.
The transparent outer margin is intentional for this conventional macOS asset-catalog icon. Do not treat it as a full-bleed iOS marketing icon or import the already rounded tile as a foreground layer into Icon Composer: those workflows need separate preparation. No Liquid Glass/dark/tinted variants are claimed.

Next concrete check: integrate, archive, upload when authorized, and inspect the processed icon in App Store Connect/TestFlight. No upload or publication was performed.

## Repository handoff
Stored in `docs/branding/vey-icon-a/`. The catalog has not yet been integrated into `Vey/Resources` or project.yml. Existing menu-bar and search-field SF Symbols are unchanged; this full-color Dock icon is not a monochrome menu-bar template.
