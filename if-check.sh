#!/bin/bash
#
# appsvelte setup check — reports diagnostic info to the instructor
# https://truffledog.au/if-check.sh
#
# Usage:
#   curl -fsSL https://truffledog.au/if-check.sh | bash
#
# CLAUDE EDIT NOTICE: When editing this file, bump ZSHRC_VERSION in
# zshrc-remote by 1. Shows in user's prompt as [v38] etc. — their signal
# that the push went live.
#
set -e

# --- Load shared helpers ---
eval "$(curl -fsSL https://truffledog.au/if-lib.sh)"

# --- Config ---
NTFY_TOPIC="if-ntfy-setup-check"

cat <<BANNER

  ┌─────────────────────────────────┐
  │     appsvelte setup check       │
  └─────────────────────────────────┘

This will check what's installed on your machine and send a diagnostic
report to your instructor so they can help you with any setup issues.

BANNER

# --- Build and display report ---
build_diagnostic_report
echo ""
echo "$DIAG_REPORT"
echo ""

# --- Send to ntfy ---
printf "Sending report to your instructor... "
if post_diagnostic_to_ntfy "$NTFY_TOPIC" "Setup Check"; then
  printf "$(tick) sent\n"
else
  printf "failed to send — your instructor won't see this report\n"
fi

echo ""
echo "Done."
echo ""
