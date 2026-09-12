# Guitar Tuner — Codex Guide

## Efficient Start

- Use supplied context once. Before code edits, inspect `git status --short --branch`,
  `git diff --stat`, and `git diff --cached --stat`, then relevant hunks. Preserve
  unrelated work and stage only the requested scope when committing.
- Start with the paths below and narrow `rg` searches. Batch independent reads;
  reuse installed dependencies and build caches unless a change invalidates them.
- Make routine reversible decisions and complete the authorized outcome. Avoid
  speculative cleanup, repeated permission questions, and unrelated work.
- Run meaningful checks for the changed surface once after edits settle, including
  the repository's required gates. Repeat only when new evidence invalidates them.
  Documentation-only edits need diff, link/path, and whitespace review.
- For requested releases, follow the current workflow and verify the final pushed
  SHA and applicable live results. Keep build, deployment, TestFlight upload, and
  physical-device evidence distinct. Report the outcome and actual verification.

## Local Pointers

- Native app and detector: `Tuner/`; regression tests: `TunerTests/`.
- Xcode project/configuration: `Tuner.xcodeproj`, `project.yml`; current product
  behavior and test invocation: `README.md`.
- Validate Swift changes with the relevant Tuner scheme build/tests on an
  available simulator. Inspect the actual screen for visible changes.
- Recorded-audio validation: `Scripts/validate-recordings.py` and
  `docs/validation.md`. Use it when detector changes warrant it; the external
  sample download is substantial and unnecessary for text/layout edits.
- Preserve distinctions between synthetic/recorded audio checks and real iPhone
  microphone behavior. This repository has no checked-in release workflow;
  establish the requested delivery target before making a release claim.
