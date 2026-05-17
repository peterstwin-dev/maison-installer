#!/usr/bin/env bash
# install.sh — Maison Collective public installer (bootstrap wrapper).
#
# This is the *outer* installer for a new collective node. It assumes you
# have a bootstrap token (mb_…) given to you by the Maison Collective
# operator. The script will:
#
#   1. Verify Homebrew + GitHub CLI are installed (offers to brew install).
#   2. Make sure your GitHub CLI is authenticated as your AI's GitHub
#      account (refuses to proceed otherwise — the operator's collab
#      invite was sent to that account, not your personal one).
#   3. Auto-accept any pending invitation from peterstwin-dev/maison-simple.
#   4. Fork peterstwin-dev/maison-simple into your AI's GitHub account
#      and clone it to ~/Workspace/maison-simple.
#   5. Hand off to the inner install.sh from inside that repo, which
#      handles all the actual Maison setup (deps, wizard, gateway, voice
#      app, Tailscale).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/install.sh \
#     | bash -s -- mb_<your-bootstrap-token>
#
# Idempotent: re-running on a populated workspace just pulls the latest
# inner install.sh and re-executes it.

# Drop `set -u` deliberately. Apple's bundled bash 3.2 has known quirks with
# `set -u` interacting with parameter expansions inside heredocs ($UPSTREAM_REPO
# expansion inside the python -c heredoc trips it on some Macs). The `-u`
# safety isn't worth the portability cost for a curl|bash installer.
set -eo pipefail

UPSTREAM_REPO="peterstwin-dev/maison-simple"
WORKSPACE_DIR="${MAISON_WORKSPACE:-$HOME/Workspace/maison-simple}"

# ─── Colors ─────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi
ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s⚠%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; }

# ─── Banner ─────────────────────────────────────────────────────────────────

cat <<'BANNER'

╔══════════════════════════════════════════════════════════════╗
║              Maison Collective — Bootstrap                   ║
║                                                              ║
║  This wrapper checks your tools + GitHub access, then hands  ║
║  off to the real installer inside the cloned repo.           ║
╚══════════════════════════════════════════════════════════════╝

BANNER

# ─── Token capture ──────────────────────────────────────────────────────────

TOKEN="${1:-${MAISON_BOOTSTRAP_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  err "Missing bootstrap token. Usage:"
  err "  curl -fsSL ... | bash -s -- mb_<your-token>"
  exit 2
fi
if [[ ! "$TOKEN" =~ ^mb_[A-Za-z0-9_-]+$ ]]; then
  err "Bootstrap token looks malformed — expected mb_<base64url>."
  err "Get a fresh one from the collective operator if yours expired."
  exit 2
fi
ok "Bootstrap token captured"

# ─── Phase 1: Homebrew ──────────────────────────────────────────────────────

if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew is required and not installed. Install with:"
  err "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  err "Then re-run this script."
  exit 2
fi
ok "Homebrew present"

# ─── Phase 2: GitHub CLI ────────────────────────────────────────────────────

if ! command -v gh >/dev/null 2>&1; then
  warn "GitHub CLI not installed."
  read -r -p "Install via brew now? (Y/n) [Y]: " ans
  ans="${ans:-Y}"
  if [[ "${ans,,}" =~ ^(y|yes)$ ]]; then
    brew install gh
  else
    err "Cannot proceed without gh CLI."
    exit 2
  fi
fi
ok "GitHub CLI present"

# ─── Phase 3: GitHub auth ───────────────────────────────────────────────────

if ! gh auth status >/dev/null 2>&1; then
  err "GitHub CLI not authenticated."
  err ""
  err "Open a fresh Terminal window and run:"
  err "  ${BOLD}gh auth login${RESET}"
  err ""
  err "Choose:"
  err "  • GitHub.com → HTTPS → Authenticate Git with credentials"
  err "  • Login with web browser"
  err "  • Sign in as your AI's GitHub account (NOT your personal one)"
  err ""
  err "Then re-run this script."
  exit 2
fi
GH_LOGIN=$(gh api user -q .login 2>/dev/null)
ok "GitHub CLI authenticated as ${BOLD}${GH_LOGIN}${RESET}"

# ─── Phase 4: Auto-accept any pending invitations ───────────────────────────

PENDING=$(gh api /user/repository_invitations 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for inv in data:
    full = inv.get('repository', {}).get('full_name', '')
    if full == '$UPSTREAM_REPO':
        print(inv['id'])
        break
" 2>/dev/null || true)
if [ -n "$PENDING" ]; then
  gh api -X PATCH "/user/repository_invitations/$PENDING" >/dev/null 2>&1 && \
    ok "Accepted pending invitation to $UPSTREAM_REPO" || \
    warn "Tried to accept invitation $PENDING but got an error; check manually"
fi

# ─── Phase 5: Fork + clone ──────────────────────────────────────────────────

if [ -d "$WORKSPACE_DIR/.git" ]; then
  ok "Repo already cloned at $WORKSPACE_DIR — pulling latest"
  (cd "$WORKSPACE_DIR" && git pull --ff-only 2>/dev/null || true)
else
  mkdir -p "$(dirname "$WORKSPACE_DIR")"
  cd "$(dirname "$WORKSPACE_DIR")"
  echo "Forking and cloning $UPSTREAM_REPO…"
  gh repo fork "$UPSTREAM_REPO" --clone --remote 2>&1 | grep -vE '^!' || true
  # Fallback if `gh repo fork` clone target naming differs
  if [ ! -d "$WORKSPACE_DIR/.git" ]; then
    git clone "git@github.com:${GH_LOGIN}/maison-simple" "$WORKSPACE_DIR"
  fi
  ok "Cloned to $WORKSPACE_DIR"
fi

# ─── Phase 6: Hand off to the inner installer ───────────────────────────────

INNER="$WORKSPACE_DIR/install.sh"
if [ ! -f "$INNER" ]; then
  err "Inner installer not found at $INNER"
  err "Your fork may be out of date. Try:"
  err "  cd $WORKSPACE_DIR && git pull upstream main"
  exit 3
fi

printf '\n%s═══ Handing off to the full installer ═══%s\n\n' "$BOLD" "$RESET"
cd "$WORKSPACE_DIR"
exec bash install.sh "$TOKEN"
