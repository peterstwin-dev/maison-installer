# Maison Collective — Installer

Public bootstrap installer for the [Maison Collective](https://github.com/peterstwin-dev/maison-simple), a federated AI assistant network.

## What this is

Each member of the Maison Collective runs their own AI assistant ("Maison") on their own hardware, with their own Supabase project storing their AI's cognitive memory. The collective is **federation-only**: nodes contribute anonymized procedural learnings to a shared mothership, which routes high-quality canonical skills back to every node. Personal data never leaves the node.

This repo is just the bootstrap script. The actual Maison code lives in the private [`peterstwin-dev/maison-simple`](https://github.com/peterstwin-dev/maison-simple), accessible to invited members.

## Joining the collective

**By invitation only.** If you've received a bootstrap token from the operator, follow the email instructions. They will look roughly like:

```bash
curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/install.sh \
  | bash -s -- mb_<your-bootstrap-token>
```

The installer:

1. Verifies Homebrew + GitHub CLI are installed (offers to install if missing).
2. Confirms you're authenticated to GitHub as your AI's account.
3. Auto-accepts your pending collab invitation to the main repo.
4. Forks and clones the main repo into your AI's GitHub account.
5. Hands off to the inner installer (inside the cloned repo), which handles dependencies, runs the setup wizard, signs you into Claude, installs the OpenClaw gateway, and configures the voice app + Tailscale.

End to end: ~10–15 minutes after pre-work. At the end your AI is listening on a Tailscale-served HTTPS URL you can open on your phone.

## Pre-work the installer can't do for you

- Install [Homebrew](https://brew.sh) (if missing).
- Install the [Claude Code CLI](https://claude.com/claude-code) and sign in (`claude auth login`).
- Sign up for [Supabase](https://supabase.com) (free tier) and create a project. The wizard will ask for the project URL, anon key, service-role key, and a personal access token.
- Make sure you've signed into GitHub CLI as your AI's account: `gh auth login`.

## Operator's access

By accepting the terms during the wizard, you consent to the collective operator (Peter) having super-admin read access to your cognitive Supabase project for debugging, trust/safety, and federation health checks. Every operator action is logged in your own `super_admin_access_log` table — auditable any time. Revocable by deleting one Auth user from your Supabase project (`super-admin@maison-collective.internal`).

## License

MIT — see `LICENSE`.
