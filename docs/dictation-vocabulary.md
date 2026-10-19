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

## Close matches

**Also fix close matches** (on by default, `dictationFixesCloseMatches`, per Mac) then catches
mishearings nobody listed (`DictationCloseMatch`). A candidate is one to three adjacent words joined
by spaces or one hyphen, never across punctuation, with at least one word the system spell checker
(`NSSpellChecker`, which includes words the owner taught it) does not know. It must sound like a
vocabulary term of at least five letters: `phoneticKey` merges voiced and unvoiced pairs, resolves c,
ph, ck, q and x, drops h, later vowels and an r not followed by a vowel, and collapses repeats, so
"Kubernetes", "Kubernitz" and "Gubanits" are all `kpnts`. Skeletons shorter than six sounds must be
equal; longer ones may be one sound off ("post-Ger SQL" for PostgreSQL). The spelling must also be at
least 45% alike. Overlaps go to the closest match, then the shortest span. English only.

A mishearing made of real words ("herder" for Herdr, "tail scale" for Tailscale, "Cuban needs") is
never touched and still needs an Also heard as entry.

False positives were measured by running the matcher with the system spell checker and twelve
technical terms over 5,103 lines of this repository's and volant-extensions' Markdown. The first
version, which allowed one sound off at any length, changed "usd in" to Obsidian; requiring short
skeletons to match exactly left only the deliberate "Kubernitz" example in this document changed.

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

- `DictationCloseMatchTests` (Core): the recognizer's actual mishearings corrected without being
  listed, and known words, short terms, unrelated unknown words, punctuation and "usd in" left alone.
- `DictationVocabularyTests` (Core): corrections, longest match, literal special characters,
  normalization and limits, import parsing and merging, the config patch keeping unknown fields and
  refusing a stale list, sync membership, and the exact transcripts above corrected.
- The native Actions fixture renders the Vocabulary section and the word editor in light and dark.
- Not yet verified: close matches against the owner's real speech and vocabulary, live dictation in the installed app with a vocabulary, and import from a real
  SuperWhisper export (its format is assumed to be heard/written pairs).
