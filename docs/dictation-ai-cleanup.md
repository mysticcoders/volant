# Dictation cleanup with Apple Intelligence

An optional pass of Apple's on-device model over a finished dictation, on Mac and iPhone, off by
default (`dictationCleansUpWithAppleIntelligence` on the Mac; Settings › Dictation Keyboard on
iPhone). It runs after filler removal, the vocabulary, spoken numbers and punctuation, and before
spoken lists and the iPhone keyboard's styles. It has two seconds (`DictationAICleanup.timeBudget`);
a slower or rejected answer leaves the transcript as heard. Nothing leaves the device.

## What it may change

The model's answer replaces the transcript only when `DictationEditCheck` can verify every change
against it, with case and punctuation ignored:

- a self-correction: up to ten words removed ending with a cue ("no wait", "I mean", "scratch
  that", "or rather", "make that"; "no", "wait", "actually", "sorry", "rather" or "correction" only
  when a comma or full stop sets them off), staying within one sentence, with words after it;
- fillers, or a word or phrase said twice in a row, removed once;
- words replaced by one of the owner's vocabulary terms.

Anything else rejects the whole answer.

## Measurements

Apple's on-device model on macOS 27 (this Mac, November 27, 2026), temperature 0.2, 24 fictional
dictations each run twice. Hex's guard (`TranscriptCleanupGuard`, ported from
https://github.com/anomalyco/hex) and Hex's instructions were tried first:

| Instructions | Check | Answers taken | Harmful answers taken |
|---|---|---|---|
| Hex's | Hex's guard | 11 of 32 (16 dictations) | 5: "Friday", "March" and "next week" all became "wednesday", the example in Hex's instructions |
| Revised, with vocabulary terms | Hex's guard | 6 of 32 | 2: "the coffee shop, I mean the bakery" cut to "the coffee shop" |
| Revised, with vocabulary terms | Hex's guard and `DictationEditCheck` | 6 of 48 | 0; the model often answered with the term list alone |
| Revised (shipped) | `DictationEditCheck` alone | 14 and 15 of 48 | 0 |

The shipped combination resolved, in both runs, "tuesday, no wait, wednesday", "seven, no, eight
people", "nine, sorry, at ten", "before lunch, no, before end of day", "three, scratch that, four
more chairs", "call mom, actually, call dad" and "I I think we should, we should wait", and once
"the coffee shop, I mean the bakery". Hex's guard was dropped because it rejected valid corrections
("seven, no, eight" lost a "no" it counts as a negation) and `DictationEditCheck` already rejects
every added, dropped or swapped word. Vocabulary terms were left out of the instructions: the model
fixed no misheard term with them and answered with the list instead of the dictation.

Not fixed: misheard terms ("cooper netties" for Kubernetes), corrections the model rephrases
("Acme, actually, send it to Globex" became "Send the invoice to Globex", which the check cannot
verify), and corrections whose cue is not in the list. To repeat the measurement, compile the
instructions, `DictationEditCheck.swift` and a loop over `LanguageModelSession` against a set of
dictations; real voices on a real device are separate evidence.
