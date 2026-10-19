# Dictation vocabulary

## Behavior

Settings → Dictation → Vocabulary lists words the owner wants written a particular way, each with
optional mishearings ("Also heard as"). Add Word… and Edit… open a small sheet; Remove deletes a
word; Import… reads a UTF-8 text file of at most 1 MB with one word per line, or two columns
(`heard,written`, comma or tab separated, quotes allowed) as replacement exports have them. Imported
words are merged: new terms are appended and known terms gain new mishearings.

Every finished and in-progress phrase is corrected after filler removal
(`DictationVocabulary.applying`): each mishearing, and the term itself in any capitalization, becomes
the term as written. Matches are whole words, ignore case, treat any run of whitespace as one space and
prefer the longest. A mishearing the recognizer splits across two phrases is not caught.

The list is `dictationVocabulary` in config.json, at most 500 terms of at most 64 characters with up
to 8 mishearings each. Edits replace the whole list against the one on screen and are refused when
it changed meanwhile; other fields are kept. It is in `SettingsSync.keys`, so it follows the owner
between Macs when iCloud settings sync is on. It is never logged.

## Recognizer hints

The first 100 terms are also passed to `SpeechAnalyzer.setContext` as `.general` contextual strings.
Measured on macOS 27.0.1 (October 19, 2026) with five sentences synthesized by `say` in two voices,
transcribed from files with and without the hints:

- `SpeechTranscriber` (what Volant uses): all 10 transcripts identical with and without hints, e.g.
  "Kubernitz", "post-Ger SQL", "tail scale", "herder".
- `DictationTranscriber`: hints fixed capitalization and one split word ("Tailscale", "Sparkle",
  "Homebrew") but not Kubernetes or PostgreSQL, and its base transcripts were much worse ("Cuban
  needs", "villain repo", "big joint").

So the corrections are the feature; hints stay because they cost nothing and a later system may honor
them. Synthesized speech is not the owner's voice or microphone, and these were the en-US models only.

## Evidence

- `DictationVocabularyTests` (Core): corrections, longest match, literal special characters,
  normalization and limits, import parsing and merging, the config patch keeping unknown fields and
  refusing a stale list, sync membership, and the exact transcripts above corrected.
- The native Actions fixture renders the Vocabulary section and the word editor in light and dark.
- Not yet verified: live dictation in the installed app with a vocabulary, and import from a real
  SuperWhisper export (its format is assumed to be heard/written pairs).
