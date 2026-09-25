# Buzz agent team

A small team of AI teammates (PM, Designer, Marketing, Engineer, plus general-purpose Claude and
Codex) that live in a [Buzz](https://github.com/block/buzz) community next to your human team.
Each agent runs Claude Code or Codex in its own locked-down Docker container on one AWS server,
with its own Buzz identity, role, memory and standing instructions.

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
  conversation-heavy roles, Opus for the general assistant, set with `agentctl model`. Claude agents
  hand heavy work to an Opus `deep-work` subagent and lookups to a Haiku `scout`.
- **Cheap ambient listening.** Before an agent's main model sees a channel message it wasn't
  mentioned in, `ambient-gate` asks a fast model whether the message is for it. Messages that
  clearly aren't cost nothing.
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
Your laptop                            agentctl (manage agents), systemd units
  Buzz Desktop (owner key)             secrets from SSM /buzz/*
  buzz-team (SSM access)                       │
                                               └── turn-gate ──https──> TypeSafe Jev API
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
| `setup/agentctl` | Server-side CLI: add/remove agents, prompts, listening, profiles, memory mirror |
| `setup/deploy-team.sh` | Ship agentctl, prompts, skills and tools; create team agents; restart what changed |
| `setup/prompts/` | Role prompts, team rules (`_team.md`), turn-taking rule (`_turns.md`), people |
| `setup/tools/` | `mem`, `mem-mirror`, `turn-gate`, `ambient-gate` (on every agent's PATH) |
| `setup/claude/` | Claude agents' managed settings (ambient-gate hook) and subagents (`deep-work`, `scout`) |
| `setup/skills/` | `memory`, `update-instructions` |
| `setup/sign-owner-proofs.py`, `publish-owner-records.py`, `share-assistants.sh` | Make Buzz show the agents as your shared assistants |
| `setup/setup-channels.sh`, `enable-listening.sh`, `setup-workflows.sh`, `setup-mirror.sh` | Channels, listening rules, scheduled check-ins, nightly memory mirror |
| `setup/buzz-team` | Laptop CLI: shell / Claude Code / Codex inside any agent, logs, restarts |
| `setup/self-hosted-relay/` | If you'd rather run your own Buzz relay |

## Before you run it

- These agents take instructions from anyone in your community, and can run code. Keep the
  community membership tight, and read the Codex sandbox note (step 12) before loosening anything.
- Costs: about $70/month for the server, plus your Claude subscription and Codex sign-ins. Every
  human message in a channel an agent listens to goes through `ambient-gate` first, and only
  messages that may need the agent become a model turn. TypeSafe charges per input token, and each
  gate check is a few hundred tokens.
- Built against Buzz Desktop 0.5.21+ and the `buzz-sprig` image pinned in `setup-agents.sh`.
  Buzz moves fast; check the pins before you build.
