#!/bin/bash
# bootstrap.sh — the public "paste once" command for a new Maison node.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/bootstrap.sh)"
#
# Old form, still accepted (the token is stored for the setup page and never printed):
#   curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/bootstrap.sh | bash -s -- mb_<token>
#
# Lives in maison-simple (installer/bootstrap.sh) and is PUBLISHED, unchanged, to the public
# peterstwin-dev/maison-installer repo, because maison-simple is private and a fresh Mac cannot read
# it until GitHub sign-in. It holds no secrets.
#
# What it does, and only this:
#   1. checks this is a Mac;
#   2. asks for the Mac password once (the sudo session is reused by install.sh for Homebrew, the
#      Tailscale app and the never-sleep setting);
#   3. installs Apple's command line tools, Homebrew, git and gh if missing;
#   4. signs in to GitHub in the browser (`gh auth login --web`) and accepts the repo invitation;
#   5. downloads Maison to ~/Workspace/maison-simple (or updates it);
#   6. runs install.sh from the download, which builds and starts the app and opens the setup page.
#
# Re-running it is safe.

set -eo pipefail

UPSTREAM_REPO="peterstwin-dev/maison-simple"
UPSTREAM_HTTPS="https://github.com/${UPSTREAM_REPO}.git"
WORKSPACE="${MAISON_WORKSPACE:-$HOME/Workspace/maison-simple}"
RESUME='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/bootstrap.sh)"'

if [ -t 1 ]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m' RESET=$'\033[0m'
  # Maison violet (#6A5CFF): exact on 24-bit terminals, else the nearest 256-color (Terminal.app).
  case "${COLORTERM:-}" in
    truecolor|24bit) VIOLET=$'\033[38;2;106;92;255m' ;;
    *)               VIOLET=$'\033[38;5;98m' ;;
  esac
else
  BOLD='' DIM='' GREEN='' YELLOW='' RED='' RESET='' VIOLET=''
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s⚠%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; }
fail() { err "$@"; err "When that is fixed, run the same command again:"; err "  $RESUME"; exit 2; }

# Opening the device is the only honest "is there a terminal" test (see install.sh have_tty).
have_tty() { { exec 9<>/dev/tty; } 2>/dev/null && { exec 9<&-; return 0; }; return 1; }

# ─── Arguments: an optional old-style token, plus flags passed through to install.sh ──
TOKEN="${MAISON_BOOTSTRAP_TOKEN:-}"
PASS_ARGS=()
for a in "$@"; do
  case "$a" in
    mb_*) TOKEN="$a" ;;
    *)    PASS_ARGS+=("$a") ;;
  esac
done
if [ -n "$TOKEN" ] && [[ ! "$TOKEN" =~ ^mb_[A-Za-z0-9_-]+$ ]]; then
  warn "Ignoring a malformed invite token. You will paste your invite in the setup page."
  TOKEN=""
fi
unset MAISON_BOOTSTRAP_TOKEN

cleanup() { if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; fi; }
trap cleanup EXIT

# ─── 1. A Mac ───────────────────────────────────────────────────────────────
if [ "$(uname -s)" != "Darwin" ]; then
  err "Maison installs on a Mac. This computer is running $(uname -s)."
  exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  warn "This Mac has an Intel processor. Maison's local models need Apple Silicon (M1 or later);"
  warn "setup will continue, but voice and memory will be slow or unavailable."
fi

cat <<INTRO

${BOLD}${VIOLET}◆ Maison${RESET} ${DIM}Initiative${RESET}
${BOLD}Setting up this Mac${RESET}

This Terminal window does the part that has to happen before Maison can run:
  1. Asks for your Mac password once, to install Apple's developer tools and
     Homebrew and to keep this Mac from sleeping
  2. Signs you in to GitHub and downloads Maison
  3. Installs what Maison needs and builds the app
  4. Opens a setup page in your web browser

This part takes about 20 to 40 minutes, mostly downloading and building. You
can leave it running.

The setup page then takes you through the rest, about 30 to 60 minutes. Have
these ready:
  • Your invite code
  • Your Claude account (claude.ai, Pro or Max plan)
  • A Supabase account (free): https://supabase.com
  • A Groq API key (free): https://console.groq.com/keys
  • A Gmail address just for this Mac's Maison, with an app password
    (2-Step Verification on, then https://myaccount.google.com/apppasswords)
  • A Tailscale account (free): https://tailscale.com

INTRO

# ─── 2. The Mac password, once ──────────────────────────────────────────────
if ! sudo -n true 2>/dev/null; then
  have_tty || fail "This needs your Mac password, and there is no Terminal window to ask in. Open the Terminal app and paste the command there."
  say "Enter your Mac password when asked (the one you use to log in to this Mac)."
  say "${DIM}Nothing appears on screen while you type. That is normal.${RESET}"
  sudo -v < /dev/tty || fail "The password was not accepted. Your Mac account must be an administrator."
fi
ok "Administrator access ready"
( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || true; sleep 45; done ) >/dev/null 2>&1 &
SUDO_KEEPALIVE_PID=$!
export SUDO_KEEPALIVE_PID   # install.sh adopts it (and stops it when it exits)

# ─── 3. Apple tools, Homebrew, git, gh ──────────────────────────────────────
if ! xcode-select -p >/dev/null 2>&1; then
  say "Installing Apple's command line tools (5 to 15 minutes)…"
  flag=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$flag" 2>/dev/null || true
  label=$(softwareupdate -l 2>/dev/null | sed -n 's/^[[:space:]]*\* Label: \(Command Line Tools.*\)$/\1/p' | tail -1 || true)
  [ -n "$label" ] && { sudo -n softwareupdate -i "$label" --verbose || true; }
  rm -f "$flag" 2>/dev/null || true
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    fail "Apple's command line tools are not installed yet. If a window opened asking to install them, click Install and wait for it to finish."
  fi
fi
ok "Apple command line tools ready"

if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew (about 5 minutes)…"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || fail "Homebrew did not install. Check your internet connection."
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; break; fi
  done
  command -v brew >/dev/null 2>&1 || fail "Homebrew installed but is not on PATH. Open a NEW Terminal window."
  for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    grep -qsF 'brew shellenv' "$rc" 2>/dev/null || printf '\neval "$(%s shellenv)"\n' "$(command -v brew)" >> "$rc"
  done
fi
ok "Homebrew ready"

missing=()
command -v git >/dev/null 2>&1 || missing+=(git)
command -v gh  >/dev/null 2>&1 || missing+=(gh)
if [ ${#missing[@]} -gt 0 ]; then
  say "Installing ${missing[*]}…"
  brew install "${missing[@]}" || fail "brew install ${missing[*]} failed (see above)."
fi
ok "git and gh ready"

# ─── 4. GitHub sign-in ──────────────────────────────────────────────────────
if gh auth status >/dev/null 2>&1; then
  ok "Signed in to GitHub"
else
  have_tty || fail "GitHub sign-in needs this Terminal window."
  say "Signing in to GitHub. You will see a one-time code:"
  say "  press Enter, paste the code into the page that opens in your browser, and approve."
  gh auth login --hostname github.com --git-protocol https --web < /dev/tty || fail "GitHub sign-in did not finish."
  ok "Signed in to GitHub"
fi
gh auth setup-git >/dev/null 2>&1 || true
for id in $(gh api user/repository_invitations --jq ".[] | select(.repository.full_name == \"$UPSTREAM_REPO\") | .id" 2>/dev/null || true); do
  gh api -X PATCH "user/repository_invitations/$id" >/dev/null 2>&1 && ok "Accepted your invitation to $UPSTREAM_REPO"
done

# ─── 5. Download ────────────────────────────────────────────────────────────
if [ -d "$WORKSPACE/.git" ]; then
  # 🩸 Put back the files a build stamps and `pnpm install` rewrites (scripts/collective/build-artifacts.ts
  # REVERT_BEFORE_PULL, the same list the nightly updater reverts). Upstream changes them on every ship, so a
  # second run of this command after a first build could not fast-forward and silently kept the old code.
  ok "Maison is already downloaded at $WORKSPACE"
  (cd "$WORKSPACE" && for f in app/pnpm-lock.yaml app/package-lock.json scripts/package-lock.json app/src/lib/version.ts app/public/sw.js; do git checkout -- "$f" >/dev/null 2>&1 || true; done; git pull --ff-only >/dev/null 2>&1) \
    || warn "Could not update the download (offline, or local changes). Continuing with it as it is."
else
  mkdir -p "$(dirname "$WORKSPACE")"
  say "Downloading Maison to $WORKSPACE…"
  git clone "$UPSTREAM_HTTPS" "$WORKSPACE" \
    || fail "Could not download Maison. If you just accepted your GitHub invitation, wait a minute. Otherwise ask whoever invited you to check that your GitHub account was invited."
fi
[ -f "$WORKSPACE/install.sh" ] || fail "The download at $WORKSPACE has no install.sh."

# ─── 6. Hand over to install.sh ─────────────────────────────────────────────
# The token travels in the environment (never argv, never printed); install.sh stores it 0600.
export MAISON_BOOTSTRAPPED=1
if [ -n "$TOKEN" ]; then export MAISON_BOOTSTRAP_TOKEN="$TOKEN"; fi
cd "$WORKSPACE"
trap - EXIT
exec bash "$WORKSPACE/install.sh" ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
