# Vey monochrome wing

A simplified vector trace of the selected pointed coral wing, without the ivory tile or fold shading. Black fill on a transparent canvas. PDF and SVG at 16 and 32 points; the shape scales without rasterization. `template-proof.png` shows white-on-dark and black-on-light at 16, 32, 64, and 96 pixels from left to right. This proof was visually inspected; actual menu-bar and launcher integration has not been performed or verified.

## Integration handoff
Copy `VeyWing.imageset` into `Vey/Resources/Assets.xcassets/`. The image set requests preserved vector representation and template rendering.

In `Vey/App/AppDelegate.swift`, replace the status item's old SF Symbol with NSImage(named: "VeyWing"), set its size to 16 by 16 points and isTemplate to true, and set the status button's accessibility label to "Vey". Do not use the full-color app icon as a template.

In `Vey/Panel/LauncherView.swift`, use Image("VeyWing").renderingMode(.template).resizable().scaledToFit() in the existing icon frame; retain the existing semantic foreground style. If it merely decorates the search field, use accessibilityHidden(true) to avoid duplicate announcements.

Verify the real menu bar and open launcher under OS light and dark appearances, including menu selection and search focus, after integration. No app source, signing settings, installed app, or release scripts were changed by this handoff.

Regenerate PDFs/proof with: `swift docs/branding/vey-icon-a/template/generate.swift docs/branding/vey-icon-a/template`
