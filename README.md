# Maison Collective — Installer

Public bootstrap installer for the [Maison Collective](https://github.com/peterstwin-dev/maison-simple), a federated AI assistant network.

## What this is

Each member of the Maison Collective runs their own AI assistant ("Maison") on their own Mac, with their own Supabase project storing their AI's cognitive memory. The collective is **federation-only**: nodes contribute anonymized procedural learnings to a shared hub, which routes high-quality canonical skills back to every node. Personal data never leaves the node.

This repo is just the bootstrap script. The actual Maison code lives in the private [`peterstwin-dev/maison-simple`](https://github.com/peterstwin-dev/maison-simple), accessible to invited members.

## Joining the collective

**By invitation only.** If you've received an invite code, paste this one line into Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/bootstrap.sh)"
```

That's the whole command — no token to paste in, no flags. It:

1. Installs Apple's command line tools, Homebrew, git and GitHub CLI if missing.
2. Signs you in to GitHub in your browser and accepts your pending invitation.
3. Downloads Maison to `~/Workspace/maison-simple` (or updates it).
4. Installs dependencies and builds the app.
5. Opens a setup page in your browser, which walks you through the rest — the Node License Agreement, your invite code, your Claude sign-in, and your accounts below — and finishes by starting your AI.

If anything stops early, it prints the exact command to resume. Re-running is always safe.

Terminal takes about 20–40 minutes (mostly downloading and building). The setup page after that takes another 30–60 minutes.

## Pre-work the installer can't do for you

Have these ready before you start:

- Time to read the Node License Agreement and the Terms of Use, which you sign with your full legal name before this Mac registers
- Your invite code
- A [Claude](https://claude.com/claude-code) account (Pro or Max plan) — the setup page signs you in
- A [Supabase](https://supabase.com) account (free tier) — no need to create a project yourself, the setup page does it
- A [Groq](https://console.groq.com/keys) API key (free)
- A Gmail address just for this Mac's Maison, with an [app password](https://myaccount.google.com/apppasswords) (2-Step Verification on first)
- A [Tailscale](https://tailscale.com) account (free) — powers this Mac's private, phone-reachable address

## A note on `install.sh`

Older invites and emails may reference `install.sh` instead of `bootstrap.sh`. That file still works — it hands off to `bootstrap.sh` automatically — but new invites use `bootstrap.sh` directly, so that's the command above.

## The Node License Agreement

Maison is proprietary software owned by Maison Initiative, PBC. Before a Mac registers as a node, its owner reads and accepts the Node License Agreement, which includes the Terms of Use, and signs it with their full legal name. The agreement covers ownership of the software, the license to run it on one node, automatic updates, license verification and remote deactivation, and administrative access by the super admin (every such action is logged on the node). A copy of exactly what was accepted is saved on the Mac, and the acceptance is recorded with Maison Initiative.

## License

The installer scripts in this repository are under the MIT license (see `LICENSE`). Maison itself is not open source: it is licensed only under the Node License Agreement.
