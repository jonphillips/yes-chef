#!/usr/bin/env bash
set -euo pipefail

# Run xcodebuild but surface only a summary to the terminal/chat.
#
# The summarizing now lives once, in jon-platform's scripts/quiet-run (shared by
# every app; see its docs/agent-workflow.md § Token discipline): full log to a
# file, errors/warnings/verdicts plus exit code and log path to the terminal,
# xcodebuild's exit status returned unchanged. This wrapper keeps the name the
# docs and habits already use, and the toolchain selection below.
#
# Usage: scripts/xcodebuild-summary.sh <xcodebuild args...>
# Example:
#   scripts/xcodebuild-summary.sh \
#     -scheme YesChef \
#     -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5) (16GB)' \
#     -skipMacroValidation \
#     build

# Mirror check-drift.sh's toolchain selection so both paths build the same way.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

qr="${JON_PLATFORM:-$HOME/code/jon-platform}/scripts/quiet-run"
if [[ ! -x "$qr" ]]; then
  echo "xcodebuild-summary.sh: $qr not found — Yes Chef needs ~/code/jon-platform (see AGENTS.md)." >&2
  exit 1
fi
exec "$qr" --label yeschef-xcodebuild xcodebuild "$@"
