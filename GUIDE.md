# Buzz team agents — access, plugins and connectors

How to get into the AI agents running on AWS, install plugins and MCP servers for them,
and keep them working. (Setup from scratch: `SETUP.md`.)

## What's running

Six agents run on one AWS server (EC2 `t3.large`). Each has its own isolated Docker container,
Buzz identity, storage and memory.

| Agent | Runtime | Role | Listens without a mention in |
|---|---|---|---|
| `claude` | Claude Code | General coding and research assistant | mentions only |
| `codex` | Codex | General coding assistant | mentions only |
| `pm` | Claude Code | Product manager | #general, #product |
| `designer` | Claude Code | Product and UX designer | #design |
| `marketing` | Claude Code | Marketing | #marketing |
| `engineer` | Claude Code | Software engineer | #engineering |

Default models: Sonnet (medium effort) for PM, Designer and Marketing; Opus (medium) for `claude`
and `engineer`; Codex's default model at medium reasoning for `codex`. See "Models and effort" below.

All of them answer anyone in the community when mentioned. Only the owner can DM them.
When one message mentions several of them, they take turns (see "Taking turns" below). They pass
files to each other with `handoff` (see "Files between agents").

## Prerequisites (on your laptop)

- AWS CLI, signed in: `aws login` (sessions expire after a while; `buzz-team` signs you in
  automatically when needed)
- AWS Session Manager plugin: `yay -S aws-session-manager-plugin`
- `buzz-team` in `~/.local/bin` (`install -m 755 setup/buzz-team ~/.local/bin/`) and
  `export BUZZ_TEAM_INSTANCE=<instance id>` in your shell profile

## The `buzz-team` command

| Command | What it does |
|---|---|
| `buzz-team list` | All agents with runtime and status |
| `buzz-team claude <agent>` | Opens Claude Code inside that agent's container |
| `buzz-team codex <agent>` | Opens Codex inside that agent's container |
| `buzz-team shell <agent>` | Opens a bash shell inside that agent's container |
| `buzz-team restart <agent>` | Restarts the agent (needed after installing anything) |
| `buzz-team logs <agent> [n]` | Shows the last `n` log lines (default 60) |
| `buzz-team server` | Opens a root shell on the server |

Anything you install from `claude`, `codex` or `shell` is saved in **that agent's own storage**
(`~/.claude` for Claude agents, `~/.codex` for Codex agents), so the agent itself uses it after a
restart. Agents don't share installs: a plugin installed for `pm` isn't available to `designer`.

## First time you open Claude Code in an agent

This happens once per agent, and the choices are saved.

1. **Theme:** pick one and press Enter.
2. **Sign-in:** it should be skipped, because the container already has the subscription token.
   If it asks anyway, choose the Claude account option.
3. **"Do you trust this folder?"** (`/workspace`): choose **Yes**.

## Install a Claude Code plugin

```bash
buzz-team claude pm
```

In Claude Code, run `/plugin` to browse marketplaces and install. Then `/exit` and:

```bash
buzz-team restart pm
```

From a shell (`buzz-team shell pm`) you can also run `claude plugin --help` for the
command-line equivalents.

## Connect an MCP server

**Claude agents:** open `buzz-team claude <agent>` and use `/mcp`, or from `buzz-team shell <agent>`:

```bash
claude mcp add --scope user <name> -- <command> [args...]
```

**Codex agents:** open `buzz-team codex <agent>` and use `/mcp`, or from `buzz-team shell <agent>`:

```bash
codex mcp add <name> -- <command> [args...]
```

Then restart the agent: `buzz-team restart <agent>`.

- **npm packages work:** `npm install -g <package>` installs into the agent's storage and is on its
  PATH (the system folders are read-only by design).
- **Sign-in limitation:** connectors whose OAuth sign-in redirects your browser to `localhost` may
  not complete, because `localhost` there means the container, not your laptop. Connectors that
  use an API key, a token, or a code you paste work fine.

## Check the agent picked it up

Ask it in Buzz, for example: `@PM what MCP tools and plugins do you have?`

If it doesn't see them, check `buzz-team logs pm` for errors after the restart.

## What's in each container

| Path | Contents |
|---|---|
| `/home/agent` | The agent's home (persistent, writable) |
| `/workspace` | Its working files (persistent, writable) |
| `~/memory` | Its long-term memory (use the `mem` command: `mem stats`, `mem find <word>`) |
| `~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md` | Its team-editable standing instructions |
| `/prompts/<agent>.md` | Its base role and the team roster (read-only) |
| `/outbox` | Files it has handed off (only it can write here) |
| `/exchange/<agent>/` | Every agent's handoffs (read-only) |
| `/workspace/inbox/<event>/` | Attachments it downloaded from Buzz messages |
| `~/.claude/agents/team/` or `~/.codex/agents/` | Its subagent roles (read-only) |
| `~/.claude/skills/` or `~/.codex/skills/` | Its skills (read-only) |
| `~/.turn-gate.log`, `~/.ambient-gate.log` | Every turn-taking and ambient-gate decision |

Everything else in the container is read-only by design.

## Taking turns when several agents are mentioned

A message like "@PM @Engineer can we ship dark mode this sprint?" used to get two replies at
once. Now each mentioned agent first runs `turn-gate` (in `/opt/agent-tools`), which asks
TypeSafe's Jev model (https://docs.typesafe.ai) who should go first:

| Gate says | The agent… |
|---|---|
| `REPLY` | replies now (it's first, each agent was asked something different, or the gate is off) |
| `REPLY-AFTER` | waited for the agents ahead of it, then adds only what's new or answers what they asked it |
| `SKIP` | waited, and the others already covered its part, so it says nothing |

Expect the second agent to answer within a minute or two of the first (it waits up to 60 s per
agent ahead of it, 180 s at most). Every decision, with Jev's probabilities, is logged in the
agent's `~/.turn-gate.log` (`buzz-team shell pm`, then `tail ~/.turn-gate.log`). No TypeSafe key,
or any error, means `REPLY`: the old behaviour.

A direct message, or a message that @names only one agent, always gets an answer: the gate isn't
used there. Only the agents @named in the text count, not `p` tags a thread reply inherits from
earlier participants.

## Models and effort

Each agent has one main model and effort level, set for its everyday work. On the server:

```bash
agentctl model pm                  # show
agentctl model pm opus high        # change model and effort, restarts the agent
agentctl model pm - low            # change only the effort (- keeps the current value)
agentctl model pm default          # back to the runtime's default model
```

Claude efforts: `low`, `medium`, `high`, `xhigh`, `max`. Codex efforts: `minimal`, `low`,
`medium`, `high`, `xhigh`. Claude model names: `sonnet`, `opus`, `haiku`, `fable`, or a full model id.

Each agent is also an orchestrator with a small team of subagents, ported from
[drmas/codex-agent-team](https://github.com/drmas/codex-agent-team). Substantial code changes go
to a worker, then to an independent reviewer; findings go back to a worker.

| Role | Claude agents | Codex agents | Used for | Edits files |
|---|---|---|---|---|
| `explorer` | Haiku | gpt-5.6-luna, max | Finding code, callers, patterns, tests; long threads, memory, files | no |
| `researcher` | Sonnet | gpt-5.6-luna, max | Behavior, root causes, change impact, library docs | no |
| `planner` | Opus | gpt-6-astra, medium | Multi-step plans with file ownership and validation | no |
| `worker` | Sonnet | gpt-5.6-sol, medium | Implementing a scoped change and running its tests | yes |
| `reviewer` | Opus | gpt-5.6-sol, high | Independent review of a finished diff | no |
| `deep-work` | Opus | – | Non-code work: specs, designs, copy, analysis | /workspace |

Claude Code runs subagents at the agent's own effort (it ignores per-subagent effort), so where
the Codex roles use higher effort, the Claude roles use a stronger model instead. The agents
decide when to delegate (rules in `prompts/_delegate.md` and `_delegate-codex.md`). You can also
ask directly: "@Engineer have the reviewer check that diff", "@PM use deep-work to write the full
spec".

To move an agent between Claude Code and Codex (keeps its Buzz identity, memory, workspace and
standing instructions; set its model again afterwards, and reinstall any plugins or MCP servers,
since those are per runtime):

```bash
agentctl runtime engineer codex && agentctl login-codex engineer
```

`engineer` ran on Codex until it was moved to Claude Code with `agentctl runtime engineer claude`.

## Skills

`memory` and `update-instructions` go to every agent. Stack skills are opt-in per agent, listed in
`setup/skill-library.txt` and fetched on the server at a pinned commit:

| Skill | From | Default agents |
|---|---|---|
| `vercel-react-best-practices` | vercel-labs/agent-skills | Engineer, Claude, Codex |
| `vercel-composition-patterns` | vercel-labs/agent-skills | Engineer, Claude, Codex, Designer |
| `web-design-guidelines` | vercel-labs/agent-skills | Engineer, Claude, Codex, Designer |
| `supabase-postgres-best-practices` | supabase/agent-skills | Engineer, Claude, Codex |
| `frontend-design` | anthropics/skills | Engineer, Claude, Codex, Designer |

```bash
agentctl skills engineer                        # show
agentctl skills designer frontend-design web-design-guidelines   # set (restarts it)
agentctl skills pm none                         # remove all opt-in skills
```

To add a skill, add a line to `setup/skill-library.txt` and run `./deploy-team.sh`, then
`agentctl skills <agent> …`. Every skill's description is read on each turn, so keep lists short.

## Files between agents

Each agent's `/workspace` is private. To pass files, agents use `handoff`, which copies them into
a snapshot every agent can read (read-only) and posts one message with the mentions and the file
list:

```bash
handoff --channel <uuid> --reply-to <event> --to Engineer --file spec.md --file flow.png \
  --message "Build the toggle from spec.md. Done = PR with tests. Reply in this thread."
```

- Files land in `/exchange/<sender>/<timestamp>-<slug>/`. Every agent can read them there; only
  the sender can write to its own `/outbox`.
- Any file type works. Images and mp4s are also attached in Buzz so humans see them: Buzz
  uploads accept only jpeg, png, gif, webp and mp4.
- When a message has attachments, agents run `attachments --channel <uuid> --event <id>`, which
  downloads them to `/workspace/inbox/<event>/` and checks any `/exchange` paths.
- Humans can't open `/exchange` from Buzz Desktop. Agents give humans short text inline, images
  as attachments, and long markdown as a Buzz note (`buzz notes set`). To look at a handoff
  yourself: `buzz-team shell <agent>`, then `ls /exchange`.
- Handoffs older than 30 days are deleted nightly (`agentctl prune-exchange [days]` to run it by hand).

## Proof with every delivery

When an agent reports that it built or fixed something, it attaches proof of the test it ran to
that message (rule in `prompts/_proof.md`), so you can validate the work from the chat:

- UI work: a short MP4 of the real flow, with a caption for each step, plus a screenshot of the
  end state.
- Backend, API or CLI work: a screenshot of the test run or requests, output and exit code included.

Agents make these with `proof` (`proof video|shot <url> [--script flow.mjs]`, `proof term -- <cmd>`),
which drives the container's headless Chromium. Captures stay in the agent's `/workspace/proof/`.
If a report comes without proof, ask for it: the agents are told to treat that as not done.

## Ambient gate: fewer wasted turns

Agents read every human message in their channels, but most need no reply. Before the main model
runs, `ambient-gate` asks a fast model (Jev, or Haiku without a TypeSafe key) whether the message
is for this agent. If it clearly isn't, the turn ends right away: no tokens, no reply. Mentions,
DMs, scheduled check-ins and messages that write the agent's `@Name` always go through. Decisions are logged in each agent's
`~/.ambient-gate.log`:

```bash
buzz-team shell pm
tail ~/.ambient-gate.log
grep -c '"SKIP"' ~/.ambient-gate.log    # turns saved
```

To make the gate more or less strict for one agent, add `AMBIENT_GATE_MIN=0.15` (lets more
through; default 0.3) or `AMBIENT_GATE=off` to `/opt/buzz-agents/<agent>.env` on the server, then
`agentctl restart <agent>`.

## On the server (as root, `buzz-team server`)

| Command | What it does |
|---|---|
| `agentctl list` | Agents, model/effort, memory limit and status |
| `agentctl model <agent> [model] [effort]` | Show or change an agent's model and effort |
| `agentctl mem <agent> [size]` | Show or change its memory limit, e.g. `4g` (restarts it) |
| `agentctl skills <agent> [skill …\|none]` | Show or change its opt-in skills (restarts it) |
| `agentctl runtime <agent> claude\|codex` | Switch an agent between Claude Code and Codex |
| `agentctl restart <agent>` / `agentctl logs <agent> 100` | Restart / logs |
| `agentctl listen <agent> <channel> …` | Channels it reads without a mention (none = mentions only) |
| `agentctl respond-to <agent> owner-only\|anyone` | Who it answers |
| `agentctl sync` | Rebuild instructions and roster, restart changed agents |
| `agentctl mirror` | Copy memory into Buzz now (it also runs nightly at 02:00 UTC) |
| `agentctl prune-exchange [days]` | Delete file handoffs older than N days (default 30; also nightly) |

The people/company section of the roster is `/opt/buzz-agents/prompts/src/_people.md`; after
editing it, run `agentctl sync`. (Better: edit `setup/prompts/_people.md` and run
`./deploy-team.sh`, so your copy stays the source of truth.)

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Your session has expired` | `aws login` |
| `SessionManagerPlugin is not found` | `yay -S aws-session-manager-plugin` |
| Agent reports work without a screenshot or video | Ask for proof in the thread. If it says `proof` failed, check it in the container: `buzz-team shell engineer`, then `proof term -- echo ok` |
| Agent didn't answer a DM or a mention of only it | Check `~/.turn-gate.log` and `~/.ambient-gate.log` for that event; both should say `REPLY`. Resend with a real mention (picked from the list, not typed) |
| `permission denied … docker.sock` in a server shell | You're `ssm-user`; run `sudo -i` first |
| Agent doesn't use a new plugin or MCP server | `buzz-team restart <agent>`, then check `buzz-team logs <agent>` |
| Agent doesn't reply | Check it's a member of the channel and `buzz-team logs <agent>` |
| Agents still answer on top of each other | Check `~/.turn-gate.log` in each: `gate off (no TYPESAFE_API_KEY)` means the key isn't loaded (`./deploy-team.sh`) |
| Second agent is too slow | Lower `STEP` / `MAX_WAIT` at the top of `setup/tools/turn-gate`, then `./deploy-team.sh` |
| Second agent repeats the first one | The first reply took longer than `STEP` (60 s); raise it in `setup/tools/turn-gate` |
| Agent says it can't open another agent's file | The sender pointed at its own `/workspace`; ask it to resend with `handoff` |
| Agent ignores a message it should have answered | Check `~/.ambient-gate.log` for a `SKIP`; mention the agent, or lower `AMBIENT_GATE_MIN` (see "Ambient gate") |
| Agent answers too slowly or too shallowly | `agentctl model <agent> …` (lower effort for speed, `opus`/higher effort for depth) |
