# Volant icon — full canvas

The previous raster baked an inset ivory tile, grey bevel and exterior margin into the icon. The replacement fills the canvas with warm ivory and enlarges the existing orange/coral folded wing. The OS can supply its own icon treatment without a second tile border in the source image.

Source: built-in imagegen edit of the existing icon, then deterministic `sips` exports into every declared AppIcon asset slot. Master: `icon-master.png` (1024×1024). Original artwork remains in the historical vey-icon-a folder.

Prompt: “Preserve the existing recognizable wing silhouette, folds, orange-to-coral colors and satin rendering. Remove the inset rounded-square tile border, grey bevel, outer white margin and tile drop shadow. The warm ivory background must fill the entire square image edge to edge, flat and borderless, with no pre-rendered rounded corners. Enlarge the wing proportionally so it occupies about 88% of the canvas width, centered optically, with only enough margin to avoid clipping. Output one 1024×1024 production app-icon bitmap, no mockup, no text, no new symbols. Keep the same design; change only sizing and background/border.”

Validation: all ten PNG dimensions match the asset catalog. The Release build and signature verification passed. AppKit rendered the built application icon at 16/32/64/128/256 pixels on light/dark backgrounds; see `render-proof.jpg`. The same icon resources are installed in `/Applications/Volant.app`. Actual Dock screenshot capture remains unavailable.
