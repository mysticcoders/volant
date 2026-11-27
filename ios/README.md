# Volant for iPhone and iPad

Notes, snippets, quicklinks and the calculator from Volant, on iOS 26. Notes are the same plain
Markdown files as on the Mac, in the iCloud Drive container `iCloud.com.mysticcoders.volant`
(Finder: iCloud Drive › Volant › Notes). Snippets and quicklinks travel through the Mac's settings
sync key-value store, so a Mac with "Sync settings and notes with iCloud" on shares them both ways.

## Layout

- `VolantMobile/`: the app (Home, Notes, More, Search tabs; onboarding; Settings; App Intents).
- `VolantWidgets/`: Recent Notes and Quick Actions widgets, and the New Note control.
- `VolantShare/`: the "Save to Volant" share extension.
- `VolantKeyboard/`: the optional dictation keyboard (see below).
- `Shared/`: brand, App Group snapshot, note writer, deep links and the keyboard bridge, compiled
  into the app and every extension (the share extension and keyboard leave out the widget views).
- The app links `../Core` (VolantCore) for themes, the calculator, and the snippet, quicklink and
  settings sync types. Core stays Foundation-only; Mac-only files are wrapped in `#if os(macOS)`.

## Build

```sh
cd ios
xcodegen generate
xcodebuild -project VolantMobile.xcodeproj -scheme VolantMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

Fixture launch arguments for simulator review: `-notesDirectory <path>` (fictional notes folder),
`-onboardingComplete NO` with `-fixtureOnboardingPage <n>`, `-fixtureTab notes|more|search`,
`-fixtureTool snippets|quicklinks|calculator`, `-fixtureSettings YES`, `-fixtureKeyboardSetup YES` (Settings ›
Dictation Keyboard), `-fixtureKeyboardSetupPage 0|1|2` with it (the setup walkthrough at that page),
`-fixtureKeyboardListening YES` (the keyboard preview drawn mid-dictation),
`-fixtureAcknowledgements YES` (Settings › Acknowledgements), and `-fixtureWidgets YES`
(draws the widget views from the App Group snapshot).

### On a device

`Scripts/device.sh <device-udid>` builds with the development profiles and installs it
(`xcrun devicectl list devices` lists UDIDs). It needs, under team REMBT6JY4N:

- App IDs `com.mysticcoders.volant.mobile` (iCloud with `iCloud.com.mysticcoders.volant` and
  CloudKit, Push Notifications for Break Alerts, App Groups), `.mobile.widgets` (App Groups), `.mobile.share` (iCloud with the container, App Groups) and `.mobile.keyboard` (App Groups).
- App Group `group.com.mysticcoders.volant` on all four. The portal adds `group.` itself, so the
  identifier is typed as `com.mysticcoders.volant`.
- iOS App Development profiles "Volant mobile development profile", "Volant mobile widget
  development profile", "Volant mobile share development profile" and "Volant mobile keyboard
  development profile", or other names passed as `VOLANT_APP_PROFILE`, `VOLANT_WIDGETS_PROFILE`,
  `VOLANT_SHARE_PROFILE` and `VOLANT_KEYBOARD_PROFILE`.

## TestFlight

`Scripts/testflight.sh` archives with the Apple Distribution certificate and App Store profiles,
checks that the app and both extensions are signed for the App Group and the Production iCloud
environment, that the app carries production push and CloudKit for Break Alerts, and exports `build/testflight/<build>/export/Volant.ipa`. The build number is the time
(yyyymmddHHMM); the version is `MARKETING_VERSION` in project.yml. With `ASC_KEY_ID` set and the
key at `~/.appstoreconnect/private_keys/AuthKey_<id>.p8` it uploads, taking the issuer from
`ASC_ISSUER_ID` or `~/.appstoreconnect/issuer_id`; otherwise upload the .ipa with Transporter.

Once per app:

- The App Store Connect app record "Volant Mobile" ("Volant" was taken) for
  `com.mysticcoders.volant.mobile`; the Home Screen name stays Volant.
- App Store profiles "Volant mobile production profile", "Volant mobile widget production
  profile", "Volant mobile share production profile" and "Volant mobile keyboard production
  profile", with the Apple Distribution certificate.
- For external testers: a beta description, feedback email and Beta App Review. Internal testers
  need none of these.

The app declares `ITSAppUsesNonExemptEncryption = NO` (it uses only Apple's HTTPS and iCloud) and
ships a privacy manifest: no tracking, no collected data, and UserDefaults (CA92.1) and file
timestamp (C617.1) access for its own and its iCloud container's files.

## App Store listing

`AppStore/` holds the listing for "Volant Mobile" as code:

- `metadata.json`: subtitle, description, keywords, promotional text, URLs, categories, copyright.
- `screenshots.sh [iphone|ipad|all]`: captures seven screens in the iPhone 17 Pro Max and iPad Pro
  13" simulators from the fictional notes and settings in `fixtures/`, with dates set relative to
  now, a 9:41 status bar and dark appearance, then frames each with a headline (`frame.swift`) at
  1320x2868 and 2064x2752 into `build/appstore/`.
- `screenshots.sh duo` captures the iPhone Duo's folded outer screen (1398x2034) in the iOS 27.1
  iPhone Duo simulator; `duo-inner` captures the unfolded inner screen (2007x2853) once it is
  unfolded in DeviceHub. The Duo set uses the inner captures when they exist.
- `creative.swift <build/appstore/iphone/raw> <out>`: the product page Header (21:9, 3840x1646)
  and Search Results (3:2, 3840x2560) creative assets, shown on iOS 27 and later. Upload them in
  App Store Connect under Product Page Information, Header and Search Results.
- `asc.py`: `uv run AppStore/asc.py show`, `push [--screenshots build/appstore] [--skip-text]`,
  `set-version <x.y.z>`, `attach-build [build]`, `age-rating`. It edits the version still being prepared, answers the
  age rating questionnaire with its lowest values (4+), and replaces each screenshot set.

TestFlight: `asc.py beta-internal --email <team member>` creates the "Volant Team" group, which gets
every build without review. `asc.py beta-external --feedback-email ... --contact-... --contact-phone ...`
sets the test information, review contact and What to Test, adds the build to the "Public Beta" group
with a public link, and submits it for Beta App Review.

The API cannot fill in App Privacy (Data Not Collected), price and availability, or App Review
contact details; set those in App Store Connect.

## Privacy

No account and no telemetry, as on the Mac. Widgets read titles and one-line previews from the App
Group snapshot; note text never leaves the notes folder. Snippet and quicklink edits are written only
to the owner's iCloud key-value store, and only lists that decode as the Mac expects are sent.

## Dictation keyboard

An optional keyboard (Settings › Dictation Keyboard in the app has a setup walkthrough) with a
Dictate bar, the Mac's snippets as tiles, and space, delete and return. The bar's style picker lays
out the finished transcript as Plain, Message, Email or Notes (`DictationStyle` in VolantCore, which
only regroups sentences and edge punctuation, never words). `Shared/KeyboardPanel.swift` draws the
keyboard for both the extension and the app's preview. It is not a full
keyboard: people type on the Apple keyboard and switch to Volant's to dictate.

iOS never gives a keyboard the microphone, even with Full Access, so the app listens for it
(`VolantMobile/Dictation`, `Shared/KeyboardBridge.swift`):

1. The keyboard writes a request to the App Group. If the app said its microphone is still open, it
   posts a Darwin notification and the app starts at once; otherwise, or with no answer in 0.8 s, it
   opens `volant://dictate`.
2. The app opens the microphone in the foreground, starts SpeechAnalyzer with the Mac's filler
   removal and the dictation vocabulary from settings sync (`settings.dictationVocabulary`, read
   only), and shows a screen telling the owner to go back with the top-left link. The `audio`
   background mode keeps it listening there.
3. The app writes live and final text to `dictation-state.json` and posts a notification; the
   keyboard types the final text of its own request once, then tells the app to clear it.
4. The microphone stays open for the chosen time (Keep Microphone Open, default 5 minutes, with the
   orange indicator on) so the next dictation skips the app switch; buffers between dictations are
   dropped on the audio thread.

Full Access is required: without it a keyboard cannot reach the App Group or open the app. Snippets
reach the keyboard as `keyboard-snippets.json`, which the app rewrites whenever it reads settings sync.
Real dictation needs a device; in the simulator the keyboard can only be seen, not used.
