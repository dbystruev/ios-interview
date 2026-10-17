# iOS Interview Helper

SwiftUI iOS app with two modes for iOS interview prep and live assistance.

## Modes

### 1. Listening Mode (live assist)
- Continuously listens to the interview in parallel (mic, on-device Speech).
- Keeps a rolling transcript window (last ~30–60s) of what is being said **right now**; nothing is stored.
- Shows answers from the local Q&A DB as large full-screen cards below the live line — updated continuously while you talk.
- If no local match after ~5s, optionally asks the LLM and shows the response, marked as `AI-generated`.
- Never auto-plays audio; silent on-screen cards only.
- Keeps the screen on while listening; Stop appears only after ~2s of silence and hides again instantly when you speak.

### 2. Preparation Mode (study)
- Imports pre-loaded `.md` Q&A files (see `~/Desktop/book/*.md` and `~/Downloads/GitHub/Human-Rated-AI/interview/server/seed/fixtures/*.md`).
- Converts raw Markdown to a normalized internal Q&A DB via parser + LLM cleanup.
- **Merges** each new file into the existing DB: exact/near-duplicate questions are enriched (answers merged, keywords/topics unioned), never duplicated.
- Lets you browse/search the DB by topic, keyword, question text.

## Requirements

- iOS 18.0+, Xcode 16+, Swift 6, SwiftUI + SwiftData.
- Device with microphone. Simulator works for Preparation Mode; Listening Mode needs a real device.

## LLM

- **Default (free, on-device, private):** Apple Foundation Models via `FoundationModels` framework on iOS 26+ with Apple Intelligence. Used for import cleanup, unknown-format extraction, answer merging, and live fallback. No key, no network.
- **Optional — OpenRouter (bring your own key):** Settings → LLM lets you paste an OpenRouter API key (`https://openrouter.ai/api/v1`, OpenAI-compatible) and pick a model. The picker shows **free models only** (`:free` suffix, fetched live via OpenRouter `GET /models`, refreshable) and defaults to a free model (e.g. the `openrouter/free` router). Paid models require typing the ID manually. To see the current free list during development: `~/bin/llm.sh model list`. The key is stored in Keychain, never in the repo, and is only used when you select the OpenRouter provider. Remote calls are off by default and require explicit opt-in per use (import extraction / AI fallback).
- **No Apple Intelligence / no key:** the app still works fully offline — deterministic parsing, local matching, and stored answers. Only AI features are disabled, with a clear banner.

## Permissions

- `NSMicrophoneUsageDescription` — live transcription.
- `NSSpeechRecognitionUsageDescription` — `SFSpeechRecognizer`.
- All transcription stays on-device by default. Remote LLM is off by default and requires explicit opt-in per session.

## Supported Markdown formats

Importer accepts all three styles:

Style A (`~/Desktop/book/ios-interview.md`) — topic heading + numbered bold questions:
```markdown
## Swift Programming (8 Questions)

1. **What's the difference between weak and unowned references?**
   - `weak`: ...
   - `unowned`: ...
```

Style B (`~/Desktop/book/ios-interview20.md`) — `Question N` / `Answer:` blocks:
```markdown
## Question 1: What's the difference between MVC and MVVM?

**Answer:**
...
```

Style C (`Human-Rated-AI/.../seed/fixtures/interview-*.md`) — podcast parts + blockquote answers:
```markdown
## Part 2. Swift Language Core

### Question 3. How do value types and reference types differ...?

> Value types copy their data when assigned...
> ...multi-paragraph answer...

*Follow-up question: Can you explain how copy‑on‑write works...?*

> Copy‑on‑write means the collection shares a buffer...
```

Rules:
- Style A/B: `##` headings become topics (unless they match `Question \d+`, in which case the previous `##`/`#` is the topic).
- Style C: `## Part N. <Topic>` becomes the topic; `## Welcome` intro is skipped (metadata only); `### Question N. <text>` starts an entry with `>` blockquote lines as the answer.
- Style C follow-ups (`*Follow-up question: ...*` + `>` answer) are stored as separate entries in the same topic, flagged `isFollowUp = true` and linked to the parent question.
- **Unknown format:** if the deterministic parsers recognize ~nothing (fewer than 3 entries or <20% of non-blank lines consumed), the import is offered to **LLM extraction**: the raw Markdown is sent to the selected LLM with a strict-JSON prompt (`[{question, answer|null, topicHint, keywords[]}]`) and the result flows through the same normalize → merge pipeline. Requires an available LLM (on-device or OpenRouter); without one the file is kept as raw entries with `needsReview = true`.
- **Questions without answers:** supported as first-class entries (`hasAnswer = false`). They appear in Library with an "Answer missing" state and a "Generate with AI" button, and can still surface in Listening Mode as question cards.
- Anything unparseable is kept as a raw `QAEntry` with `needsReview = true` for LLM cleanup.

### Import merge behavior (dedup + enrich)

Each new `.md` import merges into the existing DB instead of appending blindly:

1. Normalize the question (lowercase, strip punctuation/`Question N:` prefixes, collapse whitespace) into a `normalizedKey`.
2. **Exact match** (`normalizedKey` equal): enrich the existing entry — merge the new answer's novel points into the stored answer (LLM-assisted when available, append-only otherwise), union keywords/topics, append the new file to `sourceFiles`, keep the best question wording.
3. **Near-duplicate** (high token-overlap / embedding similarity, threshold in Settings): same as above but sets `needsReview = true` so the user can confirm the merge in Library.
4. **New question**: insert as a fresh `QAEntry`.
5. Re-importing the same file is idempotent — no duplicates created.

### Answer sources (beyond bundled .md)

Answers can cite curated external sources. v1 registry (bundled, editable in Settings):

| Source | Base URL | Use for |
|---|---|---|
| Apple Developer Documentation | `developer.apple.com/documentation` | Framework APIs, lifecycle, concurrency |
| SwiftLee | `avanderlee.com` | Swift/SwiftUI patterns, concurrency, performance |
| Hacking with Swift | `hackingwithswift.com` | Practical examples, interview-style explainers |
| Swift by Sundell | `swiftbysundell.com` | Architecture, language depth |

Rules:
- Each `QAEntry` holds `citations[]` (`{sourceId, title, url}`). Bundled imports may ship with citations; LLM-generated/enriched answers are instructed to cite only hosts from the allowlist.
- Every LLM-provided URL is validated against the allowlist before saving; off-list hosts are dropped (answer kept, flagged `needsReview`).
- Q&A cards show source chips that open the link in-app (`SFSafariViewController`). v1 performs no live web fetching — all matching stays offline; web search/fetch is a v2 option.
- Users can add/remove custom sources in Settings; custom hosts join the allowlist.

## Project layout (planned)

```text
app/
  README.md                  # this file
  PLAN.md                    # engineering plan
  project.yml                # xcodegen spec (source of truth; InterviewHelper.xcodeproj is generated)
  InterviewHelper/           # app target sources
    InterviewHelperApp.swift
    Models/                  # SwiftData: Topic, QAEntry; SourceCitation
    Import/                  # MarkdownImporter, LLMExtractor, LLMNormalizer, MergeService
    Matching/                # TopicMatcher (BM25) + TextAnalysis
    Speech/                  # Transcriber, TranscriptBuffer
    LLM/                     # LLMService protocol + FoundationModels,
                             # OpenRouter, Mock providers + KeychainStore
    Sources/                 # SourceRegistry (curated list + allowlist)
    UI/
      Listen/                # ListeningView(Model): running transcript line + answer feed
      Prepare/               # LibraryView(Model), QADetailView, Import
      Settings/              # LLM provider + OpenRouter key/model, sources, privacy
  Resources/                 # bundled: SampleQA/*.md, Sources.json
  InterviewHelperTests/      # unit + integration tests
  InterviewHelperUITests/    # UI tests (seeded library, typed-transcript matching)
```

## Setup

1. Install xcodegen (`brew install xcodegen`), then generate the project (the `.xcodeproj` is a build artifact, gitignored):
   ```sh
   cd app && xcodegen generate
   ```
   Then open `app/InterviewHelper.xcodeproj`.
2. Foreground-only audio (no background modes entitlement): Listening Mode pauses when the app backgrounds.
3. Usage-description keys (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) are injected from `project.yml` → `InterviewHelper/Info.plist` at generate time.
4. A bundled sample (`Resources/SampleQA/sample-ios-qa.md`) seeds the library on first launch.
5. Build & run on device for Listening Mode; Simulator covers Preparation Mode and the typed-transcript dev path.

## Privacy / interview-ethics note

Live assistance during a real interview may violate the interviewer's rules or employer policy. Default to using Listening Mode for mock interviews, study sessions, and post-interview review. If you use it in a real interview, disclose it and get consent where required.
