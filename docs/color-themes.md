# Color themes

Settings → Appearance has two choices:

- **Appearance**: System, Light or Dark, as before.
- **Color Theme**: what Volant paints its own surfaces with.

Both are stored in the `appearance` block of config.json (`theme` and `colorTheme`) and sync with iCloud as part of that block.

## Themes

| Theme | Light or dark | Surfaces | Accent |
| --- | --- | --- | --- |
| System (default) | follows the Appearance setting | macOS materials and semantic colors | the macOS accent color from System Settings |
| Volant | follows the Appearance setting | macOS materials and semantic colors | coral, `#c73c2a` light and `#ff7a5f` dark |
| Catppuccin Latte | light | palette | Mauve |
| Catppuccin Frappé, Macchiato, Mocha | dark | palette | Mauve |
| Nord | dark | palette | Frost `#88c0d0` |
| Dracula | dark | palette | Purple |
| Gruvbox Dark | dark | palette | Yellow |
| Gruvbox Light | light | palette | Orange |
| Solarized Dark, Solarized Light | dark, light | palette | Blue |
| Tokyo Night | dark | palette | Blue |
| Rosé Pine | dark | palette | Iris |
| Rosé Pine Dawn | light | palette | Iris |
| One Dark | dark | palette | Blue |

A palette theme decides light or dark itself. While one is selected, the Appearance setting is kept but has no effect, and the Appearance footer says so. System and Volant follow the Appearance setting. An unknown `colorTheme` value loads as System.

Before color themes, the whole app used the coral AccentColor asset as its global accent. Now the app has no global accent: the System theme shows the owner's macOS accent color, and coral is the Volant theme. The AccentColor asset remains for marketing renders.

## What a theme changes

Each palette has a background, a secondary background, text, secondary text, selection, accent, separator, and red, orange, yellow, green, blue and purple, stored as hex in `Core/Sources/VolantCore/Settings/ColorThemes.swift`. `Volant/Appearance/ThemeStore.swift` resolves them to SwiftUI and AppKit colors, and `ThemedRoot` supplies them to every hosted surface:

- **Launcher**: the panel background (the opacity slider still applies), the selected row, calculator cards and swatch outlines, the actions popover, emoji selection, the wing and other accent marks, the snap guides, and the AI Chat insertion point. Text uses the palette's text and secondary text.
- **Notes**: the window surface, the browse overlay and its selected row, and accents.
- **Settings**: the accent tint and the light or dark appearance only. Settings keeps system backgrounds and semantic text, because palette text on system-drawn form backgrounds would mix two color systems.

Under System and Volant, every surface keeps the macOS materials it had before.

## Contrast

`ColorThemeTests.testPaletteContrast` requires WCAG 2 AA for each palette:

- 4.5:1 for text on the background, the secondary background and the selection
- 4.5:1 for secondary text on the background
- 3:1 for secondary text on the selection, and for the accent on the background

Values are each project's published palette, with these choices of role:

- **Dracula**: secondary text is `#bfbfbf`; the official comment color is too dim for text.
- **Solarized**: text is base1 on dark and base02 on light; the usual base0 and base00 fall short of 4.5:1.
- **Tokyo Night**: secondary text is `fg_dark`, not the comment color.
- **One Dark**: secondary text is `#9da5b4`.
- **Rosé Pine Dawn**: secondary text uses Muted from the main Rosé Pine palette (`#6e6a86`), because Dawn's Subtle (`#797593`) reaches only 4.0:1 on its base.

## Sources and licenses

The license texts ship with Volant in `Volant/Resources/Licenses/ColorThemes-LICENSES.txt`, and Settings → Data & Configuration → Acknowledgements credits the projects.

| Palette | Source | License |
| --- | --- | --- |
| Catppuccin | github.com/catppuccin/catppuccin | MIT |
| Nord | github.com/nordtheme/nord | MIT |
| Dracula | github.com/dracula/dracula-theme | MIT |
| Gruvbox | github.com/morhetz/gruvbox | MIT/X11 (README) |
| Solarized | github.com/altercation/solarized | MIT |
| Tokyo Night | github.com/enkia/tokyo-night-vscode-theme | MIT |
| Rosé Pine | github.com/rose-pine/rose-pine-theme | MIT |
| One Dark | github.com/atom/one-dark-syntax | MIT |

## Verification and limitations

- **Render fixture:** `tools/themes/render.swift` renders the launcher rows, the actions popover, a calculator card and the notes window in every theme with fictional data. System and Volant are rendered in light and dark. It runs from `tools/render-vm.py` in the headless Tart guest.
- **Settings preview:** the preview also renders the Appearance section, with the theme grid scrolled to the bottom, and in three themes.
- **Notes editor text:** the editor's text is still `labelColor` (black or white for the appearance), not the palette's text color. Recoloring the live Markdown text view is separate work.
- **Settings sidebar:** in the VM renders, the selected sidebar row is black with unreadable text in light appearance. This happens without color themes too.
- **Installed app:** switching themes in the installed app and the iCloud round trip are separate evidence from the fixtures.
