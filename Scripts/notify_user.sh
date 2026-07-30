#!/usr/bin/env bash
set -euo pipefail

# Sends a short alert through the macOS Messages app.
# Configure the recipient locally in Scripts/.notify_user.env:
#   MATHBOARD_NOTIFY_TO="+15551234567"
# or export MATHBOARD_NOTIFY_TO in your shell.
#
# Usage:
#   Scripts/notify_user.sh "MathBoard build finished."

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$script_dir/.notify_user.env"

if [[ -f "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
fi

recipient="${MATHBOARD_NOTIFY_TO:-}"
message="${1:-Codex has a MathBoard update ready.}"

if [[ -z "$recipient" ]]; then
    echo "MATHBOARD_NOTIFY_TO is not set. Example:" >&2
    echo '  echo '\''MATHBOARD_NOTIFY_TO="+15551234567"'\'' > Scripts/.notify_user.env' >&2
    exit 2
fi

osascript <<APPLESCRIPT
set targetRecipient to "$recipient"
set targetMessage to "$message"

tell application "Messages"
    set targetService to 1st service whose service type is iMessage
    set targetBuddy to buddy targetRecipient of targetService
    send targetMessage to targetBuddy
end tell
APPLESCRIPT
