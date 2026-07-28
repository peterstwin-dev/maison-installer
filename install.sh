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
say()  { printf '%s\n' "$*"; }
phase() { CURRENT_PHASE="$*"; printf '\n%s═══ %s ═══%s\n' "$BOLD" "$*" "$RESET"; }
ask()  {
  local prompt="$1" default="${2:-}" ans
  # Read from the controlling terminal, not stdin — so prompts still work when
  # this runs as `curl … | bash` (stdin is the pipe, already at EOF). With no
  # tty (truly headless), fall back to the default.
  if [ -r /dev/tty ]; then
    if [ -n "$default" ]; then read -r -p "$prompt [$default]: " ans < /dev/tty; echo "${ans:-$default}"
    else read -r -p "$prompt: " ans < /dev/tty; echo "$ans"; fi
  else
    echo "$default"
  fi
}

# ─── Safety net: always leave a way back on track ───────────────────────────
#
# With `set -eo pipefail`, any unexpected failure (network blip, a brew step,
# a prompt with no input) aborts at a cryptic last line with no map back. This
# EXIT trap fires on every exit and, on a non-zero code, names the phase that
# failed and the exact command to resume. Intentional exits that already
# printed tailored guidance set GUIDED_EXIT=1 to suppress the generic line but
# still get the resume pointer. The whole wrapper resumes from one command —
# re-running it is idempotent (it just syncs the clone and re-execs).
CURRENT_PHASE="startup"
GUIDED_EXIT=0
resume_cmd() {
  printf 'curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/install.sh | bash -s -- %s' "${TOKEN:-mb_<your-token>}"
}
on_exit() {
  local code=$?
  [ "$code" -eq 0 ] && return 0
  if [ "$GUIDED_EXIT" != "1" ]; then
    err ""
    err "${BOLD}Bootstrap stopped during: ${CURRENT_PHASE} (exit $code).${RESET}"
    err "This is usually transient. Re-running is safe — it picks up where it left off."
  fi
  printf '%s\n%s→ To get back on track, re-run:%s\n  %s%s%s\n\n' \
    "$YELLOW" "$BOLD" "$RESET" "$BOLD" "$(resume_cmd)" "$RESET" >&2
}
trap on_exit EXIT

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

phase "Token"
TOKEN="${1:-${MAISON_BOOTSTRAP_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  err "Missing bootstrap token. Usage:"
  err "  curl -fsSL ... | bash -s -- mb_<your-token>"
  GUIDED_EXIT=1; exit 2
fi
if [[ ! "$TOKEN" =~ ^mb_[A-Za-z0-9_-]+$ ]]; then
  err "Bootstrap token looks malformed — expected mb_<base64url>."
  err "Get a fresh one from the collective operator if yours expired."
  GUIDED_EXIT=1; exit 2
fi
ok "Bootstrap token captured"

# ─── Phase 1: Homebrew ──────────────────────────────────────────────────────

phase "Phase 1: Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  # Fresh Macs have no Homebrew. Rather than dead-end here (the wall a new
  # friend hits first), offer to install it and continue in the same run.
  # NONINTERACTIVE=1 skips Homebrew's RETURN prompt; sudo still asks for the
  # Mac password (that's the "log in" — unavoidable).
  warn "Homebrew isn't installed — it's the foundation everything else needs."
  ans=$(ask "Install Homebrew now? (Y/n)" "Y")
  if [[ "$ans" == [Yy]* ]]; then
    say "Installing Homebrew (it will ask for your Mac password)…"
    if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      err "Homebrew install failed. Install it by hand, then re-run this script:"
      err "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      GUIDED_EXIT=1; exit 2
    fi
    # Homebrew doesn't put itself on PATH in the current shell — do it now, and
    # persist for future shells so the inner installer + the user both see it.
    if [ -x /opt/homebrew/bin/brew ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! command -v brew >/dev/null 2>&1; then
      err "Homebrew installed but 'brew' isn't on PATH yet. Open a NEW terminal and re-run:"
      err "  $(resume_cmd)"
      GUIDED_EXIT=1; exit 2
    fi
    BREW_BIN="$(command -v brew)"
    for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
      grep -qsF 'brew shellenv' "$rc" 2>/dev/null || printf '\neval "$(%s shellenv)"\n' "$BREW_BIN" >> "$rc"
    done
    ok "Homebrew installed and added to PATH"
  else
    err "Homebrew is required. Install it, then re-run:"
    err "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    err "  then: $(resume_cmd)"
    GUIDED_EXIT=1; exit 2
  fi
else
  ok "Homebrew present"
fi

# ─── Phase 2: GitHub CLI ────────────────────────────────────────────────────

phase "Phase 2: GitHub CLI"
if ! command -v gh >/dev/null 2>&1; then
  warn "GitHub CLI not installed."
  ans=$(ask "Install via brew now? (Y/n)" "Y")
  # Apple's bash 3.2 has no ${var,,} lowercase expansion — use a glob match.
  if [[ "$ans" == [Yy]* ]]; then
    brew install gh
  else
    err "Cannot proceed without gh CLI."
    GUIDED_EXIT=1; exit 2
  fi
fi
ok "GitHub CLI present"

# ─── Phase 3: GitHub auth ───────────────────────────────────────────────────

phase "Phase 3: GitHub auth"
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
  GUIDED_EXIT=1; exit 2
fi
GH_LOGIN=$(gh api user -q .login 2>/dev/null)
ok "GitHub CLI authenticated as ${BOLD}${GH_LOGIN}${RESET}"

# ─── Phase 4: Auto-accept any pending invitations ───────────────────────────

phase "Phase 4: Accepting invitation"
# Use gh's built-in jq (--jq) instead of shelling out to python3 — a fresh Mac
# may not have python3 on PATH, and invoking it can pop the Xcode CLT installer.
PENDING=$(gh api /user/repository_invitations \
  --jq ".[] | select(.repository.full_name == \"$UPSTREAM_REPO\") | .id" 2>/dev/null | head -1 || true)
if [ -n "$PENDING" ]; then
  gh api -X PATCH "/user/repository_invitations/$PENDING" >/dev/null 2>&1 && \
    ok "Accepted pending invitation to $UPSTREAM_REPO" || \
    warn "Tried to accept invitation $PENDING but got an error; check manually"
else
  ok "No pending invitation to accept (already a collaborator, or invite already used)"
fi

# ─── Phase 5: Fork + clone ──────────────────────────────────────────────────

phase "Phase 5: Fork + clone"
if [ -d "$WORKSPACE_DIR/.git" ]; then
  echo "Repo at $WORKSPACE_DIR — syncing fork + hard-resetting to upstream main"
  # Sync the user's fork with upstream. No-op if already in sync.
  gh repo sync "${GH_LOGIN}/maison-simple" --source "$UPSTREAM_REPO" >/dev/null 2>&1 || true
  (
    cd "$WORKSPACE_DIR" || exit 4
    # Ensure upstream remote exists (older clones may have only origin).
    git remote get-url upstream >/dev/null 2>&1 || \
      git remote add upstream "https://github.com/${UPSTREAM_REPO}.git"
    git fetch upstream main || { err "git fetch upstream failed — check network"; exit 4; }
    # Hard-reset to upstream/main. Discards any local changes from prior
    # partial install attempts (node_modules side effects, half-built artifacts,
    # etc.). This is a clean-install context — the friend hasn't authored
    # any local commits worth preserving, and silent fast-forward pulls were
    # leaving stale code in place when the working tree wasn't clean.
    git reset --hard upstream/main || { err "git reset --hard failed"; exit 4; }
  ) || { GUIDED_EXIT=1; exit 4; }
  ok "Local clone hard-reset to upstream/main"
else
  mkdir -p "$(dirname "$WORKSPACE_DIR")"
  cd "$(dirname "$WORKSPACE_DIR")"
  echo "Setting up your copy of $UPSTREAM_REPO…"

  # A personal fork is nice-to-have (it lets you push your own changes), but
  # forking a PRIVATE repo is flaky and eventually-consistent: the fork can
  # take several seconds to appear, or fail outright right after collaborator
  # access is granted. The old code created the fork with all output/errors
  # suppressed, then immediately cloned it — so a fork that hadn't been created
  # produced a baffling "Repository not found" on the clone (exit 128).
  #
  # New approach: attempt the fork, POLL for it to actually exist, and if it
  # never shows up, fall back to cloning upstream directly. You're a
  # collaborator, so you have read access either way and your node works the
  # same. All clones use HTTPS (gh-cli credential helper) to avoid SSH host-key
  # prompts that can't be answered under `curl | bash` (stdin is the closed pipe).
  FORK="${GH_LOGIN}/maison-simple"
  HTTPS_FORK_URL="https://github.com/${FORK}.git"
  HTTPS_UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}.git"

  # 1) Best-effort fork creation. Errors are shown (not swallowed) but never fatal.
  gh repo fork "$UPSTREAM_REPO" --clone=false --remote=false 2>&1 | grep -vE '^!' || true

  # 2) Poll up to ~30s for the fork to actually exist (creation is async).
  FORK_READY=0
  for _ in $(seq 1 15); do
    if gh repo view "$FORK" >/dev/null 2>&1; then FORK_READY=1; break; fi
    sleep 2
  done

  # 3) Clone the fork if it materialized; otherwise clone upstream directly.
  if [ "$FORK_READY" = "1" ]; then
    gh repo sync "$FORK" --source "$UPSTREAM_REPO" >/dev/null 2>&1 || true
    echo "Cloning your fork…"
    if git clone "$HTTPS_FORK_URL" "$WORKSPACE_DIR"; then
      cd "$WORKSPACE_DIR"
      git remote add upstream "$HTTPS_UPSTREAM_URL" 2>/dev/null || true
      ok "Cloned your fork to $WORKSPACE_DIR"
    else
      warn "Fork clone failed — falling back to a direct upstream clone."
      FORK_READY=0
    fi
  fi

  if [ "$FORK_READY" != "1" ]; then
    warn "No personal fork available (private-repo forks are flaky) — cloning upstream directly. Your node works the same; you can fork later to contribute changes."
    rm -rf "$WORKSPACE_DIR"   # clear any partial dir from a failed fork clone
    echo "Cloning $UPSTREAM_REPO…"
    git clone "$HTTPS_UPSTREAM_URL" "$WORKSPACE_DIR"
    cd "$WORKSPACE_DIR"
    git remote add upstream "$HTTPS_UPSTREAM_URL" 2>/dev/null || true
    ok "Cloned upstream to $WORKSPACE_DIR"
  fi
fi

# ─── Phase 6: Hand off to the inner installer ───────────────────────────────

phase "Phase 6: Hand off"
INNER="$WORKSPACE_DIR/install.sh"
if [ ! -f "$INNER" ]; then
  err "Inner installer not found at $INNER"
  err "Your fork may be out of date. Try:"
  err "  cd $WORKSPACE_DIR && git pull upstream main"
  GUIDED_EXIT=1; exit 3
fi

printf '\n%s═══ Handing off to the full installer ═══%s\n\n' "$BOLD" "$RESET"
cd "$WORKSPACE_DIR"
exec bash install.sh "$TOKEN"
