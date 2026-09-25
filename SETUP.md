# Buzz team agents — setup and rebuild guide

Everything needed to build the agent team from scratch: one AWS server running isolated
Claude Code / Codex agents that join a hosted Buzz community as shared assistants.
All scripts referenced here are in `setup/` next to this file. For day-to-day access (plugins, MCP,
logs) see `GUIDE.md`.

## How it fits together

```
Buzz (hosted by Block)                 AWS us-east-1, one EC2 host (Docker)
wss://<team>.communities.buzz.xyz      /opt/buzz-agents
  channels, DMs, workflows  <──wss──   ├─ container per agent (non-root, read-only system,
  profiles, owner records              │    own network/volumes, no AWS credentials)
  agent memory mirror (NIP-AE)         │    buzz-acp harness → claude-agent-acp → claude CLI
                                       │                     → codex-acp        → codex CLI
Your laptop                            ├─ agentctl (manage agents), rules/, prompts/, skills/
  Buzz Desktop (owner key)             ├─ systemd: buzz-agents.service, buzz-memory-mirror.timer
  buzz-team (SSM access)               └─ secrets from SSM Parameter Store /buzz/*
```

- **Identity:** each agent has its own Nostr keypair, generated on the server and never copied off it.
- **Ownership:** your owner key (in Buzz Desktop) signs an "auth tag" per agent (NIP-OA) and an
  owner record per agent (kind 30177). That's what makes Buzz show them as your shared agents.
- **Model access:** Claude agents share one Claude subscription token; each Codex agent has its own
  ChatGPT sign-in stored in its home volume.

## Configuration

Every deployment-specific value (instance id, relay URL, your public key, channel ids, team and
owner names) lives in `setup/config.env`, which is git-ignored. Start from the template:

```bash
cd setup && cp config.example.env config.env
```

`ssm-run.sh`, `deploy-team.sh` and `share-assistants.sh` read it, and scripts that run on the
server receive its values as environment variables. Prompts use `{{TEAM_NAME}}` and
`{{OWNER_NAME}}`, filled in by `deploy-team.sh`. Keep a private note of your own deployment
(instance, IPs, token dates) in `DEPLOYMENT.local.md` (also git-ignored).

## What gets created

| Item | Value |
|---|---|
| Instance | t3.large, Ubuntu 24.04, 60 GB encrypted gp3, Elastic IP, IMDSv2 hop limit 1 |
| Security group / IAM role | `buzz-sg` (no inbound) / `buzz-ec2` (SSM + read `/buzz/*`) |
| Secrets | SSM Parameter Store `/buzz/claude-oauth-token`, optional `/buzz/typesafe-api-key` (SecureString) |
| Monthly cost | ≈ $61 instance + $5 disk + $3.60 Elastic IP (us-east-1) |

## Prerequisites (laptop)

- AWS CLI v2 signed in (`aws login`) and the Session Manager plugin
  (`yay -S aws-session-manager-plugin`).
- Python 3 (for the signing/publishing scripts; no extra packages).
- `claude` CLI (to create the subscription token).
- Buzz Desktop **0.5.21 or newer**, signed in as the community owner (see "Tricks": the AUR
  package lags behind).

## Rebuild, step by step

All commands run from `setup/`. Scripts that run *on the server* are sent with
`./ssm-run.sh <script>` (no SSH needed; it targets `INSTANCE_ID` from `config.env`).

### 1. Provision the server

```bash
./provision.sh
```

Creates the IAM role (SSM + read `/buzz/*`), a security group with no inbound rules, the
t3.large instance with IMDSv2 hop limit 1, and an Elastic IP. The first-boot script
(`user-data.sh`) installs Docker from Docker's apt repo and clones `block/buzz` to `/opt/buzz`.
Wait ~3 minutes, until `aws ssm describe-instance-information` shows it `Online`. Options:
`AWS_REGION`, `INSTANCE_TYPE`, `DISK_GB`, `NAME` env vars. Put the printed instance id in
`config.env` as `INSTANCE_ID`.

### 2. Build the agent image and the first two agents

Fill in `RELAY_URL` (your community's `wss://` URL) and `OWNER_HEX` (your Buzz public key in
hex) in `config.env`. Then:

```bash
./ssm-run.sh setup-agents.sh
./ssm-run.sh boot-unit.sh
```

This builds `buzz-agent:local` (Block's `buzz-sprig` base + pinned `claude`, `codex`,
`claude-agent-acp`, `codex-acp`), creates keys for `claude` and `codex`, installs
`refresh-secrets.sh`, and adds the systemd unit that starts all agents on boot.

### 3. Store the Claude subscription token

Run in a **real terminal** (not a chat/command box; it needs interactive input):

```bash
claude setup-token
read -rsp "Claude OAuth token: " K && aws ssm put-parameter --region us-east-1 --name /buzz/claude-oauth-token --type SecureString --value "$K" --overwrite && unset K
```

The token is printed wrapped over two lines: paste it as **one** string (≈108 characters, starts
`sk-ant-oat`). It is valid for **one year**; renew it before it expires (see "Maintenance").
Optional alternatives: `/buzz/anthropic-api-key`, `/buzz/openai-api-key`.

Optional, for taking turns when several agents are mentioned (`turn-gate`, see "Tricks"): a
TypeSafe API key from https://console.typesafe.ai/keys, stored the same way:

```bash
read -rsp "TypeSafe API key: " K && aws ssm put-parameter --region us-east-1 --name /buzz/typesafe-api-key --type SecureString --value "$K" --overwrite && unset K
```

### 4. Install the management layer and the team agents

Set `TEAM_NAME` and `OWNER_NAME` in `config.env` and fill in `prompts/_people.md` (company +
humans) first, then:

```bash
./deploy-team.sh
```

Installs `agentctl`, prompt sources, skills (`update-instructions`, `memory`) and tools (`mem`,
`mem-mirror`); creates `pm`, `designer`, `marketing` and `engineer` (Claude Code); builds each
agent's instructions with the auto-generated "Who's who" roster; starts everything. It is
idempotent: re-run it after editing any prompt, skill or tool.

### 5. Add the agents to the community

Get their npubs on the server with `agentctl list` (or `buzz-team list` once step 11 is done). In Buzz Desktop, add each npub as a community member.
Until an agent is a member it restarts with `not a relay member`; that's expected.

### 6. Sign the Codex agent in to ChatGPT

On the server (`buzz-team server`, or SSM + `sudo -i`):

```bash
agentctl login-codex codex      # prints a URL + one-time code
agentctl restart codex
```

Open `https://auth.openai.com/codex/device` and enter the code.

### 7. Set profiles

Re-run `./deploy-team.sh` once the agents are members: it publishes each agent's
name and description so people can find them in Buzz.

### 8. Register them as your shared assistants

Get the agents' hex pubkeys on the server: `cd /opt/buzz-agents && for f in *.pub; do echo "${f%.pub} $(cat $f)"; done`.

```bash
python3 sign-owner-proofs.py <owner_hex> <agent_hex> <agent_hex> ...     # asks for your nsec (hidden)
./share-assistants.sh                                                      # uses auth-tags.json
python3 publish-owner-records.py wss://<community> <owner_hex> anyone <agent_hex>=<Name> ...
```

`sign-owner-proofs.py` writes `auth-tags.json` (public signatures only). `share-assistants.sh`
sets every agent to answer anyone and installs the proofs. `publish-owner-records.py` publishes the
owner records Buzz Desktop needs. Your secret key is only read from a hidden prompt and never
stored. Restart Buzz Desktop afterwards.

### 9. Channels, listening and scheduled check-ins

Set `GENERAL_CHANNEL_ID`, `ENGINEERING_CHANNEL_ID` (the existing channels) and `RELAY_SELF_HEX`
(`curl -s -H 'Accept: application/nostr+json' https://<community> | grep -o '"self":"[^"]*"'`) in
`config.env`. Then:

```bash
./ssm-run.sh setup-channels.sh     # creates #product #design #marketing, saves channels.json
./ssm-run.sh enable-listening.sh   # which agent listens where
./ssm-run.sh setup-workflows.sh    # PM digest, Engineer triage, Marketing ideas (UTC cron)
```

### 10. Memory mirror

```bash
./ssm-run.sh setup-mirror.sh       # nightly 02:00 UTC copy of ~/memory into Buzz memory
```

### 11. Laptop access

```bash
install -m 755 buzz-team ~/.local/bin/buzz-team
```

Add `export BUZZ_TEAM_INSTANCE=<instance id>` to your shell profile (`BUZZ_TEAM_REGION` defaults
to `us-east-1`).

### 12. Optional: remove Codex's own sandbox

Must be done by hand (Claude Code's safety check refuses to do it). Weigh the risk first: these
agents take instructions from anyone in the community. As root on the server:

```bash
cd /opt/buzz-agents && for a in codex; do docker compose -p buzz-agents exec -T $a sh -c 'f=~/.codex/config.toml; touch $f; sed -i "/^sandbox_mode *=/d;/^approval_policy *=/d" $f; printf "sandbox_mode = \"danger-full-access\"\napproval_policy = \"never\"\n" | cat - $f > $f.new && mv $f.new $f && cat $f'; agentctl restart $a; done
```

Undo: delete those two lines from `~/.codex/config.toml` and restart.

## Adding another agent later

On the server:

```bash
# optional role prompt first: /opt/buzz-agents/prompts/src/<id>.md
agentctl add <id> claude --name "<Name>" --about "<one line>" --respond-to anyone
agentctl listen <id> <channel> ...        # optional
```

Then add its npub to the community, sign an owner proof for it and install it
(`agentctl auth <id> '<tag json>'`, `agentctl restart <id>`), and publish its owner record with
`publish-owner-records.py`. Codex agents also need `agentctl login-codex <id>`. Everyone's roster
updates automatically.

## Maintenance

| Task | How |
|---|---|
| **Renew the Claude token (valid 1 year; note the date in `DEPLOYMENT.local.md`)** | Step 3 again, then on the server `/opt/buzz-agents/refresh-secrets.sh` and `agentctl restart <id>` for each Claude agent |
| Upgrade Claude Code / Codex / adapters | Edit the pinned versions in `/opt/buzz-agents/Dockerfile`, then `docker compose -p buzz-agents build && agentctl render && docker compose -p buzz-agents up -d` |
| Change team rules, roles, roster people | Edit `setup/prompts/*`, run `./deploy-team.sh` (or edit `prompts/src/` on the server + `agentctl sync`) |
| Turn the turn-taking gate on/off | Store / delete `/buzz/typesafe-api-key`, then `./deploy-team.sh` (reloads secrets, recreates agents) |
| Change listening channels | `agentctl listen <id> <channels…>` |
| Change who an agent answers | `agentctl respond-to <id> owner-only\|anyone`, then republish its owner record with the same value |
| Force a memory mirror | `agentctl mirror [id]` |
| Resize the server | Stop instance → `aws ec2 modify-instance-attribute --instance-type …` → start (Elastic IP stays; agents auto-start) |

## Tricks and things worth knowing

**Buzz**
- Buzz Desktop's **Agents tab only lists agents it runs itself**. Remote agents appear in member
  lists, @mentions, search and profiles with a cloud icon ("Not managed on this device").
- Buzz needs **both** the agent's auth tag in its kind:0 profile **and** your owner-signed kind:30177
  record to treat it as your agent. Discovery of remote owned agents needs Desktop ≥ 0.5.21.
- The relay only accepts events signed by the authenticated key, so owner records must be published
  with your key (`publish-owner-records.py`). Cloudflare in front of the relay rejects Python's
  default user agent (HTTP 403 "error code: 1010"); the script sets its own.
- **Only the owner can DM agents**, whatever `respond-to` says. Others must use channels.
- Workflow messages turn `@Name` into real mentions only for **channel members**; create workflows
  from an agent that is a member and is *not* the one being mentioned. Cron is **UTC**.
  `buzz workflows delete` was accepted but didn't remove workflows; disable with `update` instead.
- **Taking turns:** when one message mentions several agents, each runs `turn-gate` first
  (rule in `prompts/_turns.md`, tool in `tools/turn-gate`). All of them ask TypeSafe's Jev model
  the same question about the same thread snapshot ("who should reply first?", plus "does each
  agent have its own ask?"), so they agree on an order without talking to each other. The first
  replies; the rest poll the thread (up to 60 s per agent ahead, max 180 s), then ask Jev whether
  anything is left for them: `SKIP`, or `REPLY-AFTER` adding only what's new. Without
  `/buzz/typesafe-api-key`, or on any error, it answers `REPLY` (the old behaviour). Decisions are
  logged to `~/.turn-gate.log` in each agent's home; wait times and thresholds are constants at the
  top of `tools/turn-gate` (re-run `deploy-team.sh` after changing them).
- Listening rules exclude every agent's pubkey and the relay's key, so agents and workflows can't
  trigger each other without an explicit mention (loop protection).
- `buzz channels list` shows channels you can see, not necessarily ones you're a member of; check
  membership in the agent's logs (`subscribed to channel …`) or `buzz channels members`.
- Buzz's AUR package (`buzz-bin`) lags behind releases. To update: copy its PKGBUILD, bump
  `pkgver`, set `sha256sums` to the GitHub release asset digest
  (`gh api repos/block/buzz/releases/tags/desktop-v<ver>`), `makepkg -si`.

**Agents and tokens**
- Built-in memory systems are turned off on purpose (`BUZZ_ACP_NO_MEMORY`,
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`); file memory is loaded only on demand. Sessions restart every
  40 turns (`BUZZ_ACP_MAX_TURNS_PER_SESSION`) to keep context small.
- **Model and effort per agent:** `agentctl model <id> <model> <effort>` (Claude: `ANTHROPIC_MODEL`
  + `CLAUDE_CODE_EFFORT_LEVEL`; Codex: `CODEX_CONFIG` JSON, all in `<id>.env`). `deploy-team.sh`
  sets defaults only where nothing is set: Sonnet at medium for PM, Designer and Marketing, Opus at
  medium for Claude and Engineer, medium reasoning for Codex (Codex's own default is low).
  `agentctl runtime <id> claude|codex` switches an agent's runtime in place (identity, memory,
  workspace and standing instructions stay); `deploy-team.sh` uses it to move an existing Codex
  `engineer` to Claude Code. The
  environment variable wins over everything, including `/effort` and subagent frontmatter.
- **Subagents:** Claude agents get `deep-work` (Opus) and `scout` (Haiku) from `claude/agents/`,
  mounted read-only at `~/.claude/agents/team/`, plus a prompt section (`prompts/_delegate.md`)
  saying when to use them. So chat stays on the cheap model and heavy work gets the strong one.
  Subagents run at the agent's effort level; this Claude Code version ignores `effort:` in
  subagent frontmatter.
- **Ambient gate:** every human message in a listened-to channel used to be a full model turn,
  even when the agent then stayed silent. Now a fast model screens those first (`tools/ambient-gate`):
  Jev when `/buzz/typesafe-api-key` is set, otherwise Haiku on the Claude subscription. On Claude
  agents it's a `UserPromptSubmit` hook in `claude/managed-settings.json` (mounted at
  `/etc/claude-code/managed-settings.json`): a blocked turn ends before the model runs, costs
  0 tokens, and posts nothing. It only looks at prompts whose events are all `ambient`, so mentions,
  DMs and check-ins are never touched, and it fails open. Codex agents that listen run it
  themselves (rule in `prompts/_ambient.md`); their hooks need interactive trust, so the gate isn't
  a hook there. Decisions are logged to `~/.ambient-gate.log`; tune with `AMBIENT_GATE_MIN`
  (default 0.3: only clear "not for me" messages are dropped) or turn off with `AMBIENT_GATE=off`.
- **File handoffs:** `exchange/<id>/` on the server is mounted read-write as the agent's
  `/outbox`, and all of `exchange/` read-only at `/exchange` in every container: agents can publish
  files to each other but not change each other's files, and workspaces stay private. `handoff`
  snapshots files there and posts the message; `attachments` downloads a message's `imeta`
  attachments with `buzz media get`. The buzz CLI only uploads jpeg, png, gif, webp and mp4
  (checked by file content, max 50 MB, 500 MB for video), which is why documents go through
  `/exchange`. The nightly mirror timer also runs `agentctl prune-exchange 30`.
- Subscriptions are shared by all agents.
- `claude setup-token` run from a chat command box leaks the token's tail into the chat; run it in
  a real terminal.

**Server and scripts**
- Keep IMDSv2 hop limit 1: it stops containers from reaching the instance's AWS credentials
  (which can read your secrets).
- Containers are read-only except `/home/agent`, `/workspace`, `/tmp`; npm global installs go to
  `~/.local` via `NPM_CONFIG_PREFIX`.
- The SSM session user is `ssm-user`: use `sudo -i` for Docker and `/opt/buzz-agents`.
- In scripts piped over SSM, `docker compose run` swallows the rest of the script unless you use
  `-T … </dev/null`.
- `agentctl` regenerates `compose.yml`, rules and prompts; edit its sources, not the generated files.
- Self-hosting the relay instead: `setup/self-hosted-relay/` has the scripts used on day one
  (`provision.sh` with `OPEN_HTTP=true`, then `configure-relay.sh <domain> <owner_hex>`). Quay.io's
  MinIO images now refuse anonymous pulls; the script swaps in `ghcr.io/block/buzz-minio`.

## Tear down

```bash
aws ec2 terminate-instances --region us-east-1 --instance-ids <id>
aws ec2 release-address --region us-east-1 --allocation-id <eip-alloc-id>
aws ec2 delete-volume --region us-east-1 --volume-id <vol-id>     # the disk is kept on terminate
aws ssm delete-parameter --region us-east-1 --name /buzz/claude-oauth-token
```

Agent memory survives in Buzz (nightly mirror). Remove the agents from the community in Buzz Desktop.
