#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW_DIR="$ROOT_DIR/build/appstore/screenshots/raw"
SCREENSHOT_DIR="$ROOT_DIR/fastlane/screenshots/en-US"
BUNDLE_ID="aloes"
EXECUTABLE_NAME="PromptProducer"

cd "$ROOT_DIR"
mkdir -p "$RAW_DIR" "$SCREENSHOT_DIR"

read_default() {
  defaults read "$BUNDLE_ID" "$1" 2>/dev/null || true
}

restore_default() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    defaults delete "$BUNDLE_ID" "$key" >/dev/null 2>&1 || true
  else
    defaults write "$BUNDLE_ID" "$key" "$value"
  fi
}

OLD_HIDE_DOCK="$(read_default hideDockIcon)"
OLD_HIDE_MENU="$(read_default hideMenuBarIcon)"

cleanup() {
  restore_default hideDockIcon "$OLD_HIDE_DOCK"
  restore_default hideMenuBarIcon "$OLD_HIDE_MENU"
}
trap cleanup EXIT

defaults write "$BUNDLE_ID" hideDockIcon -bool false
defaults write "$BUNDLE_ID" hideMenuBarIcon -bool false
pkill -x Cntrl >/dev/null 2>&1 || true

"$ROOT_DIR/script/build_and_run.sh" run >/tmp/prompt-producer-screenshot-build.log
sleep 2

APP_PID="$(pgrep -x "$EXECUTABLE_NAME" | head -n 1)"
if [[ -z "$APP_PID" ]]; then
  echo "PromptProducer is not running after launch" >&2
  exit 1
fi

window_id() {
  local min_width="$1"
  local max_width="$2"
  local min_height="$3"
  local max_height="$4"
  TARGET_PID="$APP_PID" MIN_WIDTH="$min_width" MAX_WIDTH="$max_width" MIN_HEIGHT="$min_height" MAX_HEIGHT="$max_height" swift <<'SWIFT'
import CoreGraphics
import Foundation

let env = ProcessInfo.processInfo.environment
let pid = Int32(env["TARGET_PID"]!)!
let minWidth = Double(env["MIN_WIDTH"]!)!
let maxWidth = Double(env["MAX_WIDTH"]!)!
let minHeight = Double(env["MIN_HEIGHT"]!)!
let maxHeight = Double(env["MAX_HEIGHT"]!)!

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

let candidates = info.compactMap { window -> (id: UInt32, area: Double)? in
    guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
          let id = window[kCGWindowNumber as String] as? UInt32,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double,
          width >= minWidth,
          width <= maxWidth,
          height >= minHeight,
          height <= maxHeight else {
        return nil
    }

    return (id, width * height)
}

guard let match = candidates.sorted(by: { $0.area > $1.area }).first else {
    exit(2)
}

print(match.id)
SWIFT
}

LIBRARY_WINDOW_ID="$(window_id 900 1400 560 900)"
screencapture -x -l "$LIBRARY_WINDOW_ID" "$RAW_DIR/library.png"

osascript <<'APPLESCRIPT'
tell application "Finder" to activate
delay 0.2
tell application "System Events"
    keystroke "u" using {command down, shift down}
end tell
delay 0.8
APPLESCRIPT

COMMAND_WINDOW_ID="$(window_id 700 820 430 530)"
screencapture -x -l "$COMMAND_WINDOW_ID" "$RAW_DIR/command-bar.png"

python3 "$ROOT_DIR/script/render_app_store_screenshot.py" \
  "$RAW_DIR/library.png" \
  "$SCREENSHOT_DIR/01_prompt_library.png" \
  "Prompt library with BlockNote editing"

python3 "$ROOT_DIR/script/render_app_store_screenshot.py" \
  "$RAW_DIR/command-bar.png" \
  "$SCREENSHOT_DIR/02_command_bar.png" \
  "Global command bar for saved prompts"

file "$SCREENSHOT_DIR"/*.png
