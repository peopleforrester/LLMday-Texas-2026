# Examples · Hooks That Sit Alongside the Talk's Demo

This directory holds working hook scripts that complement the live demo in `demo/`. The demo proves the gates fire; the examples here are the actual scripts you'd hand to a team on Monday morning.

Two kinds of hooks live here, mapped to two of the talk's six gates:

| Talk gate | Where it lives | Layer |
|---|---|---|
| Demo 1 — Claude Code PreToolUse | `examples/claude-hooks/` | In-agent (client-side of the agent's tool call) |
| Demo 2 — Git pre-commit / pre-push | `examples/git-hooks/` | Client-side (developer workstation, before code leaves the laptop) |

The demo's live Beat 1 uses one narrowly-scoped PreToolUse hook (`demo/claude-hooks/pretool-use-block-prod.sh`) that catches kubectl writes against the production namespace. That's the on-stage moment. The hooks here are the broader catalog the live one was drawn from. Same shape, more coverage.

These hooks are MIT-licensed and originate from [github.com/peopleforrester/llm-coding-workflow](https://github.com/peopleforrester) (also Michael R Forrester's work). They have been used in production agent setups for over a year. They are not aspirational; they are what is already on the workstation.

## Claude Code hooks (`examples/claude-hooks/`)

Seven shell scripts plus an example `settings.json` that registers them with Claude Code. Each hook handles one of Claude Code's lifecycle events:

| Script | Hook event | What it does | Exit 2 blocks? |
|---|---|---|---|
| `session-start.sh` | `SessionStart` | Detects pending work and uncommitted changes; tells the agent to read `PROJECT_STATE.md` before acting | no (advisory) |
| `check-commit-message.sh` | `PreToolUse: Bash` | Reads the tool-call JSON, extracts the commit message, blocks if it mentions Claude / AI / Anthropic / "Generated with" | yes |
| `block-sensitive-files.sh` | `PreToolUse: Edit|Write` | Blocks Write/Edit against `.env`, `*.pem`, `*.key`, `*_rsa`, `*_ed25519`, anything matching `credentials.*` | yes |
| `validate-file.sh` | `PostToolUse: Edit|Write` | Runs ruff on .py, yamllint on .yaml; warns if the file fails project style | no |
| `check-aboutme.sh` | `PostToolUse: Edit|Write` | Warns when a new .py file is missing the 2-line `ABOUTME:` header | no |
| `auto-reanchor.sh` | `PostCompact` | After Claude's history compaction, re-reads `CLAUDE.md` / `PROJECT_STATE.md` / git state and outputs an orientation block so the agent doesn't drop the rules | no |
| `auto-test-on-stop.sh` | `Stop` | When the agent finishes its turn, runs the project's tests (pytest, npm test, etc.) and reports results | no (never fails) |

**Install:**

```bash
mkdir -p ~/.claude/hooks
cp examples/claude-hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
cp examples/claude-hooks/settings.json ~/.claude/settings.json   # or merge into your existing one
```

Test a single hook against a fixture before trusting it in a live session:

```bash
# Simulate the tool call Claude Code would send
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"co-authored by Claude\""}}' \
  | ~/.claude/hooks/check-commit-message.sh
echo "exit code: $?"   # expect 2 (blocked)
```

## Git hooks (`examples/git-hooks/`)

Three scripts that form a tiered gate before code leaves the developer's machine:

| Script | Tier | When | What it checks |
|---|---|---|---|
| `pre-commit` | Tier 1 | on every `git commit` | fast lint + type check on staged files only (<5 s target); skips when all staged files are docs |
| `pre-push` | Tier 2 + 3 | on every `git push` | Tier 2 always: secret scan + unit tests. Tier 3 on pushes to `main`: end-to-end gate |
| `deploy.sh` | helper | manual / one-time | installs the two hooks into a target repo's `.git/hooks/`, with backup and `--list` support |

**Install into one repo:**

```bash
cd /path/to/your/repo
bash /path/to/this-repo/examples/git-hooks/deploy.sh
# Or copy by hand:
cp examples/git-hooks/pre-commit examples/git-hooks/pre-push .git/hooks/
chmod +x .git/hooks/pre-commit .git/hooks/pre-push
```

**Per-repo opt-outs.** The hooks read two flag files at the repo root:

| File | Effect |
|---|---|
| `.skip-lint` | pre-commit skips the lint step |
| `.skip-typecheck` | pre-commit skips the typecheck step |

If both files exist, pre-commit exits 0. Useful for archived repos.

## How these fit the talk's narrative

The talk's thesis is that MLOps pipelines already implement most of what teams are trying to build for agentic AI. The hooks here are the on-the-workstation expression of two of those layers:

- **In-agent (Demo 1 on stage).** The Claude Code PreToolUse hook is the agent's *own* shell deciding what tool calls to even attempt. The demo's one-script version catches `kubectl set image ... -n production`. The catalog here adds blocks for sensitive files, AI-attribution commit messages, and a post-edit ABOUTME / lint pass.
- **Client-side (Demo 2 on stage).** The git pre-commit hook is the *repo* deciding what commits to accept. The demo's version rejects non-human committer emails and protected paths. The catalog here adds tiered lint, typecheck, secret scan, and an e2e gate on `main`.

Everything past these two layers (Demos 3-5: VAP, Falco + Talon, NetworkPolicy) lives in the cluster, not on the workstation. Those are in `demo/gitops/`.

## What this directory deliberately doesn't have

- **Personal-workflow scripts.** The original repo includes journal-harvesting, custom MCP servers, and Monday.com integrations. Those are personal and not part of the talk; they are not copied here.
- **Cloud / language / framework rule files.** The original repo has a `rules/` tree (per-language style, AWS, Kubernetes, OpenTelemetry, etc.). Those are workflow-wide standards and live in their own repo, not in the LLMday materials.

## License + attribution

These hooks are MIT-licensed, copied from a sibling repo by the same author. Attribution: Michael R Forrester. The LLMday repo as a whole is CC BY 4.0; the hooks under this directory are governed by their original MIT license. The two licenses are compatible.
