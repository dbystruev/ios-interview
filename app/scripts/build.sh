#!/bin/bash
set -euo pipefail

# UTF-8 locale: without it xcpretty and fastlane's own error reporting crash
# with "invalid byte sequence in US-ASCII" on non-ASCII build log content,
# masking a successful archive.
export LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Interview Helper build.sh
# Usage: ./scripts/build.sh beta   (builds com.hurated.interview → TestFlight)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
cd "$APP_DIR"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $(basename "$0") beta"
  echo "  beta — build com.hurated.interview, upload to TestFlight (via fastlane) and"
  echo "         give it to the External Testers group (SKIP_EXTERNAL=1 to skip)"
  exit 0
fi

TARGET="${1:-beta}"
if [[ "$TARGET" != "beta" && "$TARGET" != "all" ]]; then
  echo "Unknown target: $TARGET (only 'beta' supported)" >&2
  exit 1
fi

echo "Interview Helper → com.hurated.interview (team 8J39KF9DMS, key CDCJAGN567)"
echo "Project: $APP_DIR"

# Prefer brew fastlane to avoid rbenv digest-crc issue
if [[ -x "/opt/homebrew/bin/fastlane" ]]; then
  FASTLANE_BIN="/opt/homebrew/bin/fastlane"
elif command -v fastlane >/dev/null 2>&1; then
  FASTLANE_BIN="$(command -v fastlane)"
else
  echo "fastlane not found" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found (brew install xcodegen)" >&2
  exit 1
fi

# Set the build number to the next sequential TestFlight build.
# Take max(ASC latest + 1, local + 1) so we never go backwards while a just-uploaded
# build is still processing on ASC (get_builds only shows processed builds).
# Source of truth is CURRENT_PROJECT_VERSION in project.yml — the .xcodeproj
# and Info.plist are regenerated from it by xcodegen.
echo "Resolving next TestFlight build number..."
NEXT_BUILD="$("$FASTLANE_BIN" next_build_number 2>/dev/null | sed -n 's/^NEXT_BUILD=//p' || true)"
local_num="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' project.yml | head -1 | grep -oE '[0-9]+' || echo 0)"
local_num="${local_num:-0}"
if [[ -z "$NEXT_BUILD" || "$NEXT_BUILD" == "0" ]]; then
  NEXT_BUILD=$(( local_num + 1 ))
elif (( NEXT_BUILD <= local_num )); then
  # ASC hasn't caught up yet (uploaded build still processing) — keep moving forward
  NEXT_BUILD=$(( local_num + 1 ))
fi
echo "Setting CURRENT_PROJECT_VERSION → $NEXT_BUILD"
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:).*/\1 \"$NEXT_BUILD\"/" project.yml
xcodegen generate >/dev/null

# --- TestFlight release notes --------------------------------------------
# fastlane's `beta` lane reads fastlane/changelog.txt as the "What to Test"
# notes at upload time. Keep it honest automatically: only regenerate when
# it doesn't already target THIS build number (so notes someone wrote by
# hand for this specific build are never clobbered), and summarize what
# actually shipped since the last TestFlight release commit using the free
# OpenRouter router (~/bin/llm.sh). Never blocks the build — falls back to
# a plain commit-subject list (no LLM) on any failure, so notes are always
# at least accurate, even if less polished.
CHANGELOG="fastlane/changelog.txt"
CURRENT_HEADER="$(head -1 "$CHANGELOG" 2>/dev/null || true)"
if [[ "$CURRENT_HEADER" == *"($NEXT_BUILD)"* ]]; then
  echo "Release notes already target build $NEXT_BUILD — keeping as written."
else
  echo "Generating TestFlight release notes for build $NEXT_BUILD..."
  LAST_RELEASE_COMMIT="$(git log --grep='^chore: TestFlight build' --format=%H -1 2>/dev/null || true)"
  if [[ -n "$LAST_RELEASE_COMMIT" ]]; then
    RANGE=("$LAST_RELEASE_COMMIT..HEAD")
  else
    RANGE=(-20)
  fi
  # Every change's subject first (newest first), then as much of the commit
  # bodies as fits, newest first.
  SUBJECTS="$(git log --no-merges --format='- %s' "${RANGE[@]}" 2>/dev/null || true)"
  DETAILS="$(git log --no-merges --format='%s%n%b' "${RANGE[@]}" 2>/dev/null \
    | grep -vE '^(Co-Authored-By|Claude-Session|Signed-off-by):|Generated with \[Claude Code\]|^https://claude\.ai/' \
    | sed '/^$/d' | head -c 6000 || true)"
  COMMIT_LOG=""
  if [[ -n "$SUBJECTS" ]]; then
    COMMIT_LOG="Changes (newest first):
$SUBJECTS

Details:
$DETAILS"
  fi

  GENERATED=""
  if [[ -n "$COMMIT_LOG" && -f "$HOME/bin/llm.sh" ]]; then
    PREV_NOTES="$(cat "$CHANGELOG" 2>/dev/null || true)"
    PROMPT="Write TestFlight \"What to Test\" release notes for the iOS app Interview Helper, build $NEXT_BUILD (version 1.0).

Base the notes ONLY on what actually changed since the last TestFlight release — cover EVERY change in this list that a tester could notice:
---
$COMMIT_LOG
---

Match the tone and structure of these previous release notes (do not just copy them — describe what's NEW in this build):
---
$PREV_NOTES
---

Rules:
- Plain text only, no markdown (no asterisks, no # headers).
- Start with the line: Interview Helper 1.0 ($NEXT_BUILD) — What to Test
- Then a short section describing what changed, in tester-facing language (not commit-message jargon).
- Then a numbered \"What to verify\" checklist a tester can actually follow.
- End with: Report crashes / issues to TestFlight feedback. Thanks!
- Output ONLY the release notes text, nothing else — no preamble, no explanation, no code fences."

    GENERATED="$(timeout 90 bash "$HOME/bin/llm.sh" prompt "$PROMPT" 2>/tmp/llm_changelog.err || true)"
    GENERATED="$(printf '%s\n' "$GENERATED" | sed -e '/^```/d')"
  fi

  if [[ -n "$GENERATED" && ${#GENERATED} -ge 80 && "$GENERATED" == *"($NEXT_BUILD)"* ]]; then
    printf '%s\n' "$GENERATED" > "$CHANGELOG"
    echo "Release notes generated via OpenRouter free model."
  else
    echo "Warning: could not generate notes via OpenRouter — falling back to a plain commit list." >&2
    [[ -s /tmp/llm_changelog.err ]] && cat /tmp/llm_changelog.err >&2 || true
    {
      echo "Interview Helper 1.0 ($NEXT_BUILD) — What to Test"
      echo ""
      if [[ -n "$COMMIT_LOG" ]]; then
        echo "Changes in this build:"
        echo "$SUBJECTS"
      else
        echo "No commit history available to summarize — please test broadly."
      fi
      echo ""
      echo "Report crashes / issues to TestFlight feedback. Thanks!"
    } > "$CHANGELOG"
  fi
fi
# --------------------------------------------------------------------------

echo "Running $FASTLANE_BIN beta..."
BETA_LOG="$(mktemp -t interview-beta)"
BETA_STATUS=0
"$FASTLANE_BIN" beta 2>&1 | tee "$BETA_LOG" || BETA_STATUS=$?
if [[ $BETA_STATUS -ne 0 ]]; then
  # fastlane can fail AFTER the binary already reached App Store Connect —
  # e.g. while waiting for the new build to show up so it can attach the
  # "What to Test" notes. Exiting here used to skip the notes, the expiry AND
  # the version-bump commit, and a re-run would upload a new build number. If
  # the upload itself succeeded, finish the remaining steps instead.
  if grep -q "Successfully uploaded the new binary" "$BETA_LOG"; then
    echo "fastlane beta failed ($BETA_STATUS) after build $NEXT_BUILD was uploaded — finishing notes/expire/commit." >&2
    NOTES_SET=0
    for attempt in 1 2 3 4; do
      if "$FASTLANE_BIN" set_testflight_notes "build:$NEXT_BUILD"; then
        NOTES_SET=1
        break
      fi
      echo "Release notes attempt $attempt failed (build may still be processing) — retrying in 60s..." >&2
      sleep 60
    done
    if [[ $NOTES_SET -ne 1 ]]; then
      echo "Warning: could not set release notes — later run: fastlane set_testflight_notes build:$NEXT_BUILD" >&2
    fi
  else
    echo "fastlane beta failed with status $BETA_STATUS before the upload finished — skipping expire/commit" >&2
    exit $BETA_STATUS
  fi
fi

# External testers ("External Testers" group, public link): submit the build
# for Beta App Review and add it to the group, so every upload reaches them
# without a manual step in App Store Connect. Waits for processing (~5-15 min).
# Non-fatal: the build is already on TestFlight for internal testers.
# SKIP_EXTERNAL=1 ./scripts/build.sh beta keeps a build internal-only.
if [[ "${SKIP_EXTERNAL:-0}" == "1" ]]; then
  echo "SKIP_EXTERNAL=1 — build $NEXT_BUILD stays internal-only."
else
  echo "Giving build $NEXT_BUILD to External Testers (Beta App Review)..."
  "$FASTLANE_BIN" distribute_external "build:$NEXT_BUILD" \
    || echo "Warning: external distribution failed — later run: fastlane distribute_external build:$NEXT_BUILD" >&2
fi

# Keep the external group(s) lean: the newest approved build + the newest one
# still awaiting review (when newer). Builds taken out of the group are then
# expired by expire_old_builds below. Non-fatal.
echo "Pruning external TestFlight groups..."
"$FASTLANE_BIN" prune_external_groups || echo "Warning: prune_external_groups failed — check the group manually" >&2

# Expire old TestFlight builds, keeping latest + externally approved / public link.
# Non-fatal: build is already uploaded, expire failure should not fail the script.
echo "Expiring old TestFlight builds (keeping latest + external)..."
"$FASTLANE_BIN" expire_old_builds || echo "Warning: expire_old_builds failed — check manually" >&2

# Stage/commit/push code changes (never secrets/logs/working files).
# .gitignore already covers: *.ipa, *.dSYM.zip, fastlane/report.xml.
# Explicitly exclude just in case.
echo "Staging code changes (excluding secrets/logs)..."
cd "$PROJECT_ROOT"
git add -A -- ':!*.ipa' ':!*.dSYM.zip' ':!*.log' ':!fastlane/report.xml' ':!DerivedData' || true
if git diff --cached --quiet; then
  echo "Nothing to commit."
else
  BUILD_NUM="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' app/project.yml | head -1 | grep -oE '[0-9]+' || echo "unknown")"
  git commit -m "chore: TestFlight build 1.0 ($BUILD_NUM) — expire old, push after upload" || echo "Commit failed" >&2
  git push || echo "Push failed — push manually" >&2
fi

echo "Done — check https://appstoreconnect.apple.com/apps"
