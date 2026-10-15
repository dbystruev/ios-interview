# PLAN — iOS Interview Helper

Target: Swift 6, SwiftUI, SwiftData, iOS 18.0+ (deploy), iOS 26 SDK features gated with `@available` / `#if canImport(FoundationModels)`).

Source of truth for behavior: `app/README.md`. This file is the build order.

## 1. Architecture

```text
Mic (AVAudioEngine) → Transcriber (SFSpeechRecognizer, on-device)
  → TranscriptBuffer (rolling ~60s window)
  → TopicMatcher (local DB: BM25 + keyword overlap [+ NLEmbedding if available])
  → ListeningViewModel → QACardView (top-3 matches + confidence)
  → on miss: LLMService.answer(transcript) → card marked AI-generated

.md file → MarkdownImporter (deterministic parser, styles A/B/C)
  → if unrecognized: LLMExtractor (strict-JSON Q&A extraction, answers may be null)
  → raw QAEntry[] → LLMNormalizer (topic, keywords, clean Q/A)
  → MergeService (exact + near-dedup, enrich answers, union keywords/sources)
  → SwiftData store → Library/Search UI

Answer citations: QAEntry.citations[] → SourceRegistry (allowlist:
  developer.apple.com, avanderlee.com, hackingwithswift.com,
  swiftbysundell.com + user-added hosts) → source chips in UI
```

Key decisions:
- **Offline-first.** Local match never needs network. LLM is fallback/enrichment only.
- **Protocol behind LLM:** `LLMService` with three providers: `FoundationModelsProvider` (**default** — on-device, iOS 26+, no key), `OpenRouterProvider` (opt-in — user pastes key in Settings → LLM, stored in Keychain; OpenAI-compatible `https://openrouter.ai/api/v1`; model picker lists free `:free` models fetched live via `GET /models` and defaults to one, e.g. `openrouter/free`), `MockProvider` (tests/previews). Provider is chosen in Settings; remote is off by default.
- **No server component.** Remote LLM calls go straight from device; key stored in Keychain, never in repo.
- **Concurrency:** Swift 6 strict concurrency. `Transcriber` and `TopicMatcher` are actors; ViewModels are `@Observable @MainActor`.

## 2. Data model (SwiftData)

```swift
@Model final class Topic { var name: String; @Relationship var entries: [QAEntry] }
@Model final class QAEntry {
  var question: String; var answer: String
  var hasAnswer: Bool          // false for question-only entries (answer == "")
  var normalizedKey: String      // canonical dedup key, see §4
  var topic: Topic?
  var keywords: [String]      // lowercased, normalized
  var citations: [SourceCitation]  // curated-source links, see §4b
  var sourceFiles: [String]; var sourceIndexes: [Int]  // all files merged into this entry
  var isFollowUp: Bool; var parentQuestion: QAEntry?  // Style C follow-ups
  var needsReview: Bool       // parser unsure, merge candidate, or LLM cleanup pending
  var isAIGenerated: Bool     // true only for live LLM fallback answers
  var createdAt: Date; var updatedAt: Date
}

/// Embedded value type (Codable, not a separate @Model).
struct SourceCitation: Codable, Hashable {
  var sourceId: String   // e.g. "apple-docs", "swiftlee"
  var title: String; var url: URL
}
```

- No vector column in v1. Embeddings (if used) live in a sidecar file/cache keyed by `QAEntry.id`; BM25 + keyword scoring is the v1 matcher.
- Full-text search via `NSPredicate` / SwiftData `#Predicate` on `question`, `answer`, `keywords`.

## 3. MarkdownImporter (deterministic, no LLM)

Must handle all three real formats (A/B from `~/Desktop/book/`, C from `Human-Rated-AI/.../seed/fixtures/`):

- **Style A:** `## <Topic>` then `N. **<Question>**` followed by `-` bullets (multi-line answer).
- **Style B:** `## Question N: <Question>` + `**Answer:**` + free-form body until next `##`.
- **Style C:** `## Part N. <Topic>` sections containing `### Question N. <Question>` entries whose answers are `>` blockquote lines (joined across consecutive `>` lines into multi-paragraph Markdown). `## Welcome` is metadata and skipped. `*Follow-up question: <text>*` + `>` answer blocks become child entries (`isFollowUp = true`, `parentQuestion` set) under the same topic.
- Topic resolution for Style B: nearest preceding non-question `##`/`#`; default `"General"`.
- Output: `[RawQA(question, answer, topicHint, sourceFile, sourceIndex, isFollowUp, parentQuestionText)]` where `answer` may be empty (question-only). Unparseable blocks → single entry with `needsReview = true`, never dropped.
- **Unknown-format fallback:** if the deterministic pass yields <3 entries or consumes <20% of non-blank lines, `ImportView` offers "Parse with AI" (auto-offered when an LLM is available). `LLMExtractor` sends the raw Markdown (chunked at ~8k chars with heading-overlap) with a strict-JSON prompt → `[RawQA]` with `answer` possibly null → same normalize → merge pipeline. Question-only results are stored with `hasAnswer = false`. If no LLM is available, the file is kept as raw entries with `needsReview = true`.
- Unit tests (v1 gate): fixtures copied from the heads of all three real sources (both book files + one `interview-*.md` fixture incl. a follow-up) + edge cases (empty answer, code fences, inline `**`, multi-paragraph answers, `Welcome` skip) + one unknown-format fixture for `LLMExtractor` (via `MockProvider`, incl. a question with null answer).

## 4. LLMNormalizer (Preparation Mode import pipeline)

Runs after deterministic parse, only on demand (per-file "Clean with AI" button + per-entry retry):

- Input: `RawQA`. Output: `{ cleanQuestion, cleanAnswerMarkdown, topic, keywords[≤8] }`.
- Prompt constrains output to strict JSON; parser validates and falls back to raw on failure.
- Sets `needsReview = false` on success; keeps original text in `sourceExcerpt` for audit (add field if needed).
- Works offline-degraded: if no LLM available, import still succeeds with raw entries + `needsReview = true`.

### Merge / dedup on import (`MergeService`, runs after normalize, before save)

Every import merges into the existing DB — re-importing the same file is idempotent, importing a new file enriches overlaps:

- **Key:** `normalizedKey(question)` = lowercase → strip `Question N:` / `Part N` / numbering prefixes → strip punctuation → collapse whitespace. Stored per entry; indexed for lookup.
- **Exact match** (key equality): enrich in place — (a) answer: LLM merge prompt ("preserve all existing points, append only novel sentences from the new answer, keep Markdown, no deletion") or plain append of new paragraphs when no LLM; (b) `keywords` = union, `sourceFiles`/`sourceIndexes` += new origin, keep the longer/cleaner question wording; (c) `updatedAt = now`, `needsReview` unchanged.
- **Near-duplicate** (token Jaccard ≥ 0.8 or embedding cosine ≥ threshold when available, same-topic preferred): auto-merge as above but set `needsReview = true` with a "Merged — confirm" affordance in Library (user can split back).
- **New question:** insert fresh `QAEntry`; follow-ups merge against follow-ups first, then against parents. A question-only entry merged with an answered variant gains the answer (`hasAnswer` flips, `isAIGenerated` per origin).
- **Concurrency:** `MergeService` is an actor; import runs off-main with batched SwiftData saves and a per-file progress report (`inserted / enriched / flagged` counts in `ImportView`).
- Unit tests: same question from Style A + Style C fixtures merges to one entry with unioned keywords and both sources; re-import yields zero new rows.

### Answer generation for question-only entries

- `QADetailView` shows "Answer missing" + "Generate with AI" (uses the selected LLM provider; saved with `isAIGenerated = true` + citations, `hasAnswer = true`).
- In Listening Mode, question-only entries still match (scored on question + keywords) and display as question cards with the same generate action.

### Curated answer sources (`SourceRegistry`, §2 model)

- Seed from `Resources/Sources.json`: Apple Developer Documentation (`developer.apple.com`), SwiftLee (`avanderlee.com`), Hacking with Swift (`hackingwithswift.com`), Swift by Sundell (`swiftbysundell.com`) — `{id, name, baseURL, notes}`.
- `SourceRegistry` actor loads seed + user-added sources (Settings → Sources); exposes the host **allowlist** for citation validation.
- LLM prompts (extraction, normalization, fallback answers) instruct: cite only allowlisted hosts as `[{sourceId, title, url}]`. `MergeService`/save path validates every URL's host against the allowlist — off-list URLs are dropped, answer kept, entry flagged `needsReview`.
- UI: `QACardView` / `QADetailView` render `citations[]` as source chips opening in `SFSafariViewController`. No live web fetching in v1 (offline-first); web search/fetch is v2.
- Unit tests: off-list URL dropped + flagged; user-added host accepted after adding.

## 5. TopicMatcher (Listening Mode retrieval)

- **Input:** `TranscriptBuffer` — rolling window (last ~40 utterances / ~60s, deduped partials).
- **Pipeline per evaluation tick** (every 2–3s or on final transcription):
  1. Normalize (lowercase, strip punctuation, stopwords).
  2. Extract content terms (last sentence weighted ×2).
  3. Score all `QAEntry` with `0.6 * BM25(question+keywords) + 0.3 * BM25(answer) + 0.1 * topicBoost`.
  4. Return top-3 above `threshold` (default 0.35, tunable in Settings) with per-card confidence.
- **Debounce/hysteresis:** only swap the displayed card if new winner beats current by `> 0.1` or current goes stale (>15s). Prevents flicker.
- **v2 (optional):** `NLEmbedding` cosine re-rank of top-20; keep behind feature flag.

## 6. Speech pipeline

- `Transcriber` actor: `AVAudioEngine` + `SFSpeechRecognizer`, `requiresOnDeviceRecognition = true` when available.
- Handles: `requestAuthorization` (mic + speech), tap on input node, partial vs final results, auto-restart on interruption, silence indicator.
- `TranscriptBuffer` keeps timestamped segments; exposes `currentWindowText()` for matcher + LLM fallback.
- Simulator/dev fallback: "Paste/Type transcript" field driving the same matcher path (critical for testing without mic).

## 7. LLM fallback (Listening Mode miss path)

- Trigger: no candidate above threshold for ~5s **and** user enabled "AI fallback" for the session. Uses the provider selected in Settings (Foundation Models by default; OpenRouter when chosen + key present).
- Request includes: window text + top-1 near-miss Q&A (if any) + "answer concisely, iOS interview context" system prompt + citation instruction (allowlisted hosts only, §4).
- Response card shows: `AI-generated • verify` badge, source chips (if cited), collapsible transcript used, "Save to Library" button (saves as `isAIGenerated = true` entry under detected topic).
- Rate-limit: one in-flight request, 10s cooldown, cancel on new strong local match.

## 8. UI (SwiftUI, minimal v1)

- `ContentView`: TabView — **Listen** | **Library** | **Settings**.
- Listen: big status (Listening/Paused), live transcript (collapsible), top-3 `QACardView`s (question, topic chip, confidence, source chips, expandable answer), pause/mute, AI-fallback toggle.
- Library (`Preparation Mode`): `ImportView` (file picker `.md` + bundled samples + per-file progress + "Parse with AI" for unknown formats) → `TopicListView` → `QAListView` → `QADetailView` (Markdown-rendered, source chips, "Generate with AI" for answer-less entries); global `SearchView` (text + topic filter + `needsReview` filter).
- Settings: LLM provider picker (On-device / OpenRouter), OpenRouter API key entry (Keychain) + model picker (free `:free` models fetched live, refreshable; paid IDs manual entry), Sources list (add/remove custom hosts), threshold slider, window-size stepper, "clear AI answers", privacy notice.
- Accessibility: Dynamic Type, VoiceOver labels on cards, minimum 44pt targets.

## 9. Milestones

- **M0 — Skeleton (0.5d):** Xcode project, tabs, SwiftData container, Info.plist keys, sample `.md`, builds on device.
- **M1 — Preparation Mode (1–2d):** `MarkdownImporter` (styles A/B/C) + tests, `MergeService` dedup/enrich + tests, SwiftData CRUD, Import/Library/Search UI, file-picker import with inserted/enriched/flagged counts.
- **M2 — Listening offline (1–2d):** `Transcriber` + `TranscriptBuffer` + `TopicMatcher`, Listen UI with top-3, manual-transcript dev mode, debounce.
- **M3 — LLM layer (1–2d):** `LLMService` protocol + `FoundationModelsProvider` (default) + `OpenRouterProvider` (key via Settings/Keychain; free-`:free`-model picker via live `GET /models`, default `openrouter/free`) + `MockProvider`; `LLMExtractor` unknown-format parse; normalizer + live fallback with citations; `SourceRegistry` + allowlist validation + source chips; `isAIGenerated`/`hasAnswer` handling; Settings.
- **M4 — Hardening (1d):** interruptions, background policy, performance (matcher <100ms on 2k entries), empty/error states, app icon, privacy strings, TestFlight notes.

## 10. Testing

- Unit: importer fixtures (all three styles incl. follow-ups + `Welcome` skip), `LLMExtractor` unknown-format fixture via `MockProvider` (incl. null-answer question), merge/dedup fixtures (Style A + Style C overlap → single enriched entry; re-import idempotent; question-only + answered merge), citation allowlist tests (off-list URL dropped + flagged; user-added host accepted), matcher ranking fixtures (e.g. "weak vs unowned" transcript → that card wins), debounce logic, JSON validation of normalizer.
- UI tests: import sample → search → open card; listen with typed transcript → card appears.
- Manual: real-device mic test, interruption (call/Siri), airplane-mode (offline match still works, LLM gracefully disabled).

## 11. Risks / mitigations

| Risk | Mitigation |
|---|---|
| `SFSpeechRecognizer` on-device unavailable / needs network | Prefer on-device, degrade to typed-transcript mode with clear banner |
| Foundation Models unavailable (older OS / region) | Gate with `@available`; remote opt-in or pure-offline mode |
| `.md` format drift | Deterministic parser never drops blocks; unknown formats go through `LLMExtractor`; `needsReview` queue + LLM fix |
| LLM hallucinates citation URLs | Host allowlist validation on save; off-list dropped + flagged |
| OpenRouter key exposure | Keychain only, never logged/bundled; calls direct device→OpenRouter, opt-in only |
| Matcher flicker / false positives | Hysteresis + threshold setting + show confidence |
| Mic privacy / App Store review | Foreground-only v1, clear usage strings, no recording stored, no background audio unless justified |
| Cheating/policy concerns | Ethics notice in README + in-app banner suggesting mock/practice use |

## 12. Definition of done (v1)

- [ ] Import both `~/Desktop/book/*.md` files plus all `Human-Rated-AI/.../seed/fixtures/interview-*.md` files with zero dropped questions; questionable ones flagged `needsReview`; overlapping questions merged/enriched, never duplicated; re-import creates zero new rows.
- [ ] Browse/search by topic/keyword works offline.
- [ ] On device, speaking an interview question surfaces the right card within ~3s.
- [ ] With no match and fallback on, an AI answer appears labeled as such; with fallback off, a clean empty state appears.
- [ ] Unknown-format `.md` parses via "Parse with AI" with zero dropped questions; question-only entries stored (`hasAnswer = false`) and answer-generable.
- [ ] Default on-device LLM works with no key; OpenRouter provider works with a user-supplied key from Settings (Keychain-stored).
- [ ] AI answers carry allowlisted source citations shown as chips; off-list URLs never saved.
- [ ] No API key in repo; remote LLM off by default; app works fully offline except AI features.
