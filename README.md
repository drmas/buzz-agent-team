# Buzz agent team

A small team of AI teammates (PM, Designer, Marketing, Engineer, plus general-purpose Claude and
Codex) that live in a [Buzz](https://github.com/block/buzz) community next to your human team.
Each agent runs Claude Code (all but `codex`) or Codex in its own locked-down Docker container on
one AWS server, with its own Buzz identity, role, model, memory and standing instructions.

This repo is the whole setup: provisioning, the agent image, a management CLI, prompts, skills,
and the docs we use to run it. Fork it, fill in `setup/config.env`, and follow `SETUP.md`.

## What you get

- **Role agents that stay in their lane.** Each has a role prompt (`setup/prompts/`), shared team
  rules, and an auto-generated "Who's who" roster of every human and agent.
- **Channel listening without chaos.** Agents answer @mentions anywhere and can also read every
  human message in their own channels (PM in #product, Designer in #design…), with rules for when
  to stay silent. Agents and workflows can't trigger each other without an explicit mention.
- **Taking turns when several agents are mentioned.** Without it, "@PM @Engineer can we ship
  this?" gets two replies at the same moment, each ignoring the other. Each agent now runs
  `turn-gate` first. It asks [TypeSafe's Jev](https://docs.typesafe.ai) model, a fast model that
  returns calibrated structured answers, who should reply first. Every agent sends the same
  question about the same thread snapshot, so they agree on an order without talking to each
  other. The others wait for those ahead of them, then either add only what's new or stay
  silent. Optional: without a TypeSafe key it answers "reply" and nothing changes.
- **The right model for the job.** Each agent has its own model and effort level: Sonnet for
  PM, Designer and Marketing, Opus for Engineer and the general assistant, all at medium effort and
  changeable with `agentctl model`. Every agent orchestrates a small team of subagents, ported from
  [drmas/codex-agent-team](https://github.com/drmas/codex-agent-team): an explorer and researcher
  for discovery, a planner, a worker that implements and tests, and an independent reviewer
  (plus `deep-work` for non-code work on Claude agents). `agentctl runtime` moves an agent between
  Claude Code and Codex without losing its identity or memory.
- **Stack skills where they help.** Engineering agents get React, composition, Postgres and UI
  guideline skills from Vercel, Supabase and Anthropic, fetched at pinned commits; the Designer gets
  the design ones. `agentctl skills` changes who has what. The image includes headless Chromium for
  e2e tests, plus Playwright and ffmpeg for recording proof.
- **Cheap ambient listening.** Before an agent's main model sees a channel message it wasn't
  mentioned in, `ambient-gate` asks a fast model whether the message is for it. Messages that
  clearly aren't cost nothing.
- **Proof with every delivery.** An agent that reports finished work attaches a screenshot or a
  short captioned video of the test it ran (`proof`: headless Chromium + Playwright + ffmpeg), so
  you can check the work from the chat. No proof, not done.
- **File handoffs between agents.** Workspaces are private, so agents hand files over with
  `handoff`: a read-only snapshot every agent can open at `/exchange/<agent>/…`, plus one Buzz
  message with real mentions and the file list (images also attached in Buzz). `attachments`
  downloads whatever a human attached to a message. Any file type; old handoffs are pruned nightly.
- **Cheap long-term memory.** Plain files in `~/memory` behind a token-frugal `mem` command,
  mirrored nightly into Buzz so you can read them in Buzz Desktop.
- **Team-editable instructions.** Anyone can tell an agent "from now on…" and it updates its own
  standing instructions, with history and undo, without touching the admin-owned base role.
- **Isolation by default.** Non-root, read-only containers, no inbound ports, no AWS credentials
  reachable from containers (IMDSv2 hop limit 1), secrets pulled from SSM Parameter Store.
- **Scheduled check-ins.** Buzz workflows ping agents on a cron (daily PM digest, engineering
  triage).

## How it fits together

```
Buzz community (hosted relay)          AWS, one EC2 host (Docker)
  channels, threads, DMs  <──wss──     container per agent
  workflows, profiles                    buzz-acp harness → claude-agent-acp / codex-acp → CLI
                                         /prompts (role + team rules + roster), skills, tools
                                         /outbox (own handoffs), /exchange (everyone's, read-only)
Your laptop                            agentctl (manage agents), systemd units
  Buzz Desktop (owner key)             secrets from SSM /buzz/*
  buzz-team (SSM access)                       │
                                               └── turn-gate, ambient-gate ──https──> TypeSafe Jev API
```

## Getting started

1. Read `SETUP.md` end to end (≈ an hour the first time).
2. `cd setup && cp config.example.env config.env` and fill it in as you go.
3. Edit `setup/prompts/_people.md` (your company and humans) and any role prompt you want to change.
4. Follow the numbered steps in `SETUP.md`. Day-to-day operations are in `GUIDE.md`.

## Layout

| Path | What it is |
|---|---|
| `SETUP.md` | Build (or rebuild) everything from scratch, plus tricks we learned the hard way |
| `GUIDE.md` | Everyday use: shells into agents, plugins, MCP servers, logs, troubleshooting |
| `setup/config.example.env` | Every deployment-specific value; copy to `config.env` (git-ignored) |
| `setup/provision.sh`, `user-data.sh` | Create the EC2 host, IAM role, security group, Elastic IP |
| `setup/setup-agents.sh`, `boot-unit.sh` | Agent image, first agents, secrets refresh, start on boot |
| `setup/agentctl` | Server-side CLI: add/remove agents, models, memory limits, skills, runtimes, prompts, listening, profiles, memory mirror, handoff cleanup |
| `setup/deploy-team.sh` | Ship agentctl, prompts, skills, tools and Claude settings; create team agents; set default models; restart what changed |
| `setup/prompts/` | Role prompts, team rules (`_team.md`), turn-taking (`_turns.md`), files (`_files.md`), proof of work (`_proof.md`), delegation (`_delegate.md`, `_delegate-codex.md`), people |
| `setup/tools/` | `mem`, `mem-mirror`, `turn-gate`, `ambient-gate`, `handoff`, `attachments`, `proof` (on every agent's PATH) |
| `setup/claude/` | Claude agents' managed settings (ambient-gate hook) and subagents (`explorer`, `researcher`, `planner`, `worker`, `reviewer`, `deep-work`) |
| `setup/codex/` | Codex agents' custom agents (the same roles, from drmas/codex-agent-team) |
| `setup/skills/` | `memory`, `update-instructions` (every agent) |
| `setup/skill-library.txt` | Opt-in third-party skills, pinned by commit; given per agent with `agentctl skills` |
| `setup/sign-owner-proofs.py`, `publish-owner-records.py`, `share-assistants.sh` | Make Buzz show the agents as your shared assistants |
| `setup/setup-channels.sh`, `enable-listening.sh`, `setup-workflows.sh`, `setup-mirror.sh` | Channels, listening rules, scheduled check-ins, nightly memory mirror and handoff cleanup |
| `setup/buzz-team` | Laptop CLI: shell / Claude Code / Codex inside any agent, logs, restarts |
| `setup/self-hosted-relay/` | If you'd rather run your own Buzz relay |

## Before you run it

- These agents take instructions from anyone in your community, and can run code. Keep the
  community membership tight, and read the Codex sandbox note (step 12) before loosening anything.
- Costs: about $70/month for the server, plus your Claude subscription (shared by all Claude
  agents) and one ChatGPT sign-in for `codex`. Every human message in a channel an agent listens to
  goes through `ambient-gate` first, and only messages that may need the agent become a model turn.
  TypeSafe charges per input token, and each gate check is a few hundred tokens. Without a TypeSafe
  key, the ambient gate uses Haiku on the Claude subscription instead.
- Built against Buzz Desktop 0.5.21+ and the `buzz-sprig` image pinned in `setup-agents.sh`.
  Buzz moves fast; check the pins before you build.
