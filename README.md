# claude-autoruner

A tiny launcher for spinning up preconfigured Claude Code sessions and driving them remotely from the iPhone Claude app.

Every session it launches comes with:

- **Auto mode** (`--permission-mode auto`) — Claude auto-accepts safe edits.
- **Remote control** (`--rc`) — the session shows up in the iPhone Claude app and is drivable from there.
- A **named** session (`--name <name>`) — the name appears in the prompt box, the iPhone session list, and `tmux` session list.
- A **specific working directory** — referenced by alias or path.
- Wrapped in a detached **tmux** session so it survives terminal closes and can be attached locally any time.

## How the pieces fit

```
┌──────────────────────┐
│ orchestrator session │   long-lived Claude in this folder, paired to iPhone
│ (tmux: orchestrator) │   you tell it from the phone: "launch Octo as review-mr"
└──────────┬───────────┘
           │ runs ./claude-autorun.sh Octo review-mr
           ▼
┌──────────────────────┐
│ child session        │   appears in iPhone session list as "review-mr"
│ (tmux: review-mr)    │   you tap it and start working
└──────────────────────┘
```

The orchestrator is just another Claude Code session — there's no special server. Its only job is to translate your phone messages into `claude-autorun.sh` invocations.

## Files

| File | Purpose |
|---|---|
| `claude-autorun.sh` | The launcher. All commands go through this script. |
| `folders.json` | Alias → absolute-path map. Edited via `--add` / `--remove`. |
| `CLAUDE.md` | Instructions the orchestrator session reads on startup. |
| `README.md` | This file. |

The script is invoked as `./claude-autorun.sh` from this folder. It is **not** symlinked onto `$PATH` by design.

## One-time setup

1. Install Homebrew tmux if you haven't (you already have `tmux 3.6a`):
   ```bash
   brew install tmux
   ```
2. Make sure `claude` is on your `$PATH`:
   ```bash
   command -v claude
   ```

## Usage

All commands run from the `claude-autoruner` directory (wherever you cloned it).

### Manage folder aliases

```bash
./claude-autorun.sh --list
./claude-autorun.sh --add <alias> <absolute-path>
./claude-autorun.sh --remove <alias>
```

Alias names must match `[A-Za-z0-9_.-]+`.

### Launch a child session

```bash
./claude-autorun.sh <alias-or-path> [session-name]
```

- `<alias-or-path>` may be a registered alias (e.g. `Octo`) or a literal directory path.
- `<session-name>` is optional; defaults to `<alias-or-basename>-<YYYYMMDD-HHMM>`.
- The child runs detached in tmux. You don't need to attach to use it — the iPhone app drives it.

### Launch the orchestrator

The orchestrator is a single, long-lived Claude session paired to your phone. Start it once, leave it running. **Wrap it in tmux** so closing the terminal doesn't kill it:

```bash
tmux new-session -d -s orchestrator './claude-autorun.sh --orchestrator'
tmux attach -t orchestrator      # do the one-time iPhone pairing + workspace-trust
# inside tmux: press Ctrl-B then D to detach (do NOT type 'exit')
```

After pairing, the orchestrator stays running in the background. From your iPhone you can now say things like *"launch Octo as review-mr"* and it'll spawn a new child session you can switch to.

## tmux cheat sheet

All sessions live as named tmux sessions. The default tmux prefix is **`Ctrl-B`**.

### From a regular shell (outside tmux)

```bash
tmux ls                          # list all running sessions
tmux attach -t <name>            # attach to a session  (alias: tmux a -t <name>)
tmux kill-session -t <name>      # kill one session
tmux kill-server                 # kill ALL tmux sessions on this machine (nuclear)
tmux rename-session -t <old> <new>
```

### Inside an attached session

| Keys | Effect |
|---|---|
| `Ctrl-B` then `D` | **Detach** — leaves the session running. This is what you want most of the time. |
| `Ctrl-B` then `[` | Enter scrollback / copy mode. `q` to exit. Arrow keys / Page Up / Page Down to scroll. |
| `Ctrl-B` then `,` | Rename the current window. |
| `Ctrl-B` then `?` | Show all key bindings. |
| `Ctrl-D` or `exit` at the shell | **Kills** the session. Avoid unless you really want to end it. |

### Workflow examples

```bash
# Peek at what review-mr is doing locally:
tmux attach -t review-mr
# (Ctrl-B D to leave it running)

# Stop a child session you no longer need:
tmux kill-session -t review-mr
# Or, equivalently, send /exit from the iPhone.

# Restart the orchestrator after reboot:
tmux new-session -d -s orchestrator './claude-autorun.sh --orchestrator'
tmux attach -t orchestrator      # confirm trust prompt + iPhone pairing if asked
```

## Lifetime & persistence

| Event | What survives |
|---|---|
| Closing the terminal window | All tmux sessions (orchestrator + children) survive. |
| Mac sleep / lid close | Survives. Processes pause and resume. |
| Logout | Sessions are killed. |
| Reboot | Everything is gone. Restart the orchestrator manually. |

tmux is required — if it isn't installed, the script exits with a `brew install tmux` hint.

## Troubleshooting

- **Orchestrator opened in the wrong folder.** Run it as `./claude-autorun.sh --orchestrator` from inside the `claude-autoruner` directory. Don't put the launcher on `$PATH`.
- **`tmux session named 'X' already exists`.** Pick another name, or kill the existing one: `tmux kill-session -t X`.
- **Child doesn't appear in the iPhone app.** Confirm `--rc` works manually first: `cd <folder> && claude --rc --name test`. The phone needs to be paired with this Mac for remote control.
- **Workspace trust prompt blocks the orchestrator.** Attach with `tmux attach -t orchestrator` and confirm "Yes, I trust this folder".

## Out of scope

- Auto-restart of the orchestrator at login (would need a launchd plist — easy add later).
- Cross-host or non-macOS support — script is Bash + macOS conventions.
- Encryption of `folders.json` — it's a plaintext list of paths, no secrets.
