#!/usr/bin/env bash
# Install agentctl, skills and prompt sources on the instance, create any missing team agents,
# rebuild every agent's prompt (with the Who's who roster) and restart agents that changed.
# Idempotent. Usage: ./deploy-team.sh   (settings from config.env)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/config.env" ] && { set -a; . "$HERE/config.env"; set +a; }
: "${TEAM_NAME:?set TEAM_NAME in config.env}" "${OWNER_NAME:?set OWNER_NAME in config.env}"
BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$BUILD/prompts/src"
cp "$HERE/agentctl" "$HERE/instructions-header.md" "$HERE/skill-library.txt" "$BUILD/"
cp -r "$HERE/skills" "$HERE/tools" "$HERE/claude" "$HERE/codex" "$BUILD/"
cp "$HERE"/prompts/*.md "$BUILD/prompts/src/"
# fill in {{TEAM_NAME}} / {{OWNER_NAME}}
TEAM_NAME="$TEAM_NAME" OWNER_NAME="$OWNER_NAME" perl -pi -e 's/\{\{(TEAM_NAME|OWNER_NAME)\}\}/$ENV{$1}/g' "$BUILD"/prompts/src/*.md
BUNDLE=$(tar -C "$BUILD" -czf - agentctl instructions-header.md skill-library.txt prompts skills tools claude codex | base64 -w0)

cat > "$BUILD/remote.sh" <<REMOTE
set -euo pipefail
cd /opt/buzz-agents
echo "$BUNDLE" | base64 -d | tar -xzf - -C /opt/buzz-agents
chmod 700 agentctl; ln -sf /opt/buzz-agents/agentctl /usr/local/bin/agentctl
chmod 755 prompts prompts/src skills skills/* tools tools/* claude claude/agents codex codex/agents; chmod 644 prompts/src/*.md skills/*/* instructions-header.md skill-library.txt claude/*.json claude/agents/* codex/agents/*
rm -f claude/agents/scout.md   # folded into explorer (roles from drmas/codex-agent-team)
# turn-gate: (re)write the TypeSafe key line in refresh-secrets.sh (servers set up before it existed)
sed -i '/typesafe/d;/turn-gate/d' refresh-secrets.sh
cat >> refresh-secrets.sh <<'EOF'
# All agents: TypeSafe (Jev) key for turn-gate. Without it turn-gate always answers REPLY.
k=\$(get /buzz/typesafe-api-key); if [ -n "\$k" ]; then printf 'TYPESAFE_API_KEY=%s\\n' "\$k" > secrets/common.env; echo "typesafe: API key loaded"; else rm -f secrets/common.env; fi
EOF
./refresh-secrets.sh | grep typesafe || echo "typesafe: no /buzz/typesafe-api-key (turn-gate stays off)"
# nightly timer: also prune file handoffs older than 30 days (servers set up before handoffs existed)
f=/etc/systemd/system/buzz-memory-mirror.service
if [ -f \$f ] && ! grep -q prune-exchange \$f; then sed -i '/agentctl mirror\$/a ExecStart=/opt/buzz-agents/agentctl prune-exchange 30' \$f; systemctl daemon-reload; echo "mirror timer: + prune-exchange"; fi
# headless Chrome for e2e tests (servers set up before it was in the image). Playwright's own
# browser downloads are glibc builds and don't run on this Alpine image; tools use CHROME_BIN.
if ! grep -q chromium Dockerfile; then
  sed -i '/^USER agent\$/i RUN apk add --no-cache chromium nss freetype harfbuzz ttf-freefont font-noto-emoji\nENV CHROME_BIN=/usr/bin/chromium-browser PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser PUPPETEER_SKIP_DOWNLOAD=true PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1' Dockerfile
  docker compose -p buzz-agents build -q && echo "image: + chromium"
fi
# proof tool: ffmpeg (video) + playwright-core (drives Chromium), for servers set up before it
if ! grep -q playwright-core Dockerfile; then
  sed -i '/^ENV CHROME_BIN=/i RUN apk add --no-cache ffmpeg && npm i -g playwright-core@1.63.0 && npm cache clean --force   # proof tool' Dockerfile
  docker compose -p buzz-agents build -q && echo "image: + ffmpeg, playwright-core"
fi
printf '%s\n' "\$OWNER_NAME" > owner.name   # exported by ssm-run.sh from config.env
[ -f owner.hex ] || sed -n 's/^BUZZ_ACP_AGENT_OWNER=//p' claude.env > owner.hex
[ -f agents.list ] || printf 'claude claude 3g solo\ncodex codex 3g solo\n' > agents.list
# registry v2: 4th column = kind (team|solo)
awk '{ if (NF==3) print \$0, ((\$1=="claude"||\$1=="codex") ? "solo" : "team"); else print }' agents.list > agents.list.new && mv agents.list.new agents.list
meta() { [ -f "\$1.meta" ] || printf '%s\n%s\n' "\$2" "\$3" > "\$1.meta"; }
meta claude    Claude    "General-purpose coding and research assistant for \$OWNER_NAME (Claude Code)."
meta codex     Codex     "General-purpose coding assistant for \$OWNER_NAME (Codex)."
meta pm        PM        "Product manager: specs, priorities, task breakdown, status."
meta designer  Designer  "Product & UX designer: flows, UI specs, mockups, design review."
meta marketing Marketing "Marketing: positioning, copy, launches, content."
meta engineer  Engineer  "Software engineer: technical design, code, estimates, reviews."
# opt-in skills (skill-library.txt), only for agents that have no list yet (change with: agentctl skills …)
agentctl skills-fetch
defskills() { local id=\$1; shift; [ -f "\$id.skills" ] || { echo "\$*" > "\$id.skills"; echo "skills \$id: \$*"; }; }
ENG="vercel-react-best-practices vercel-composition-patterns supabase-postgres-best-practices web-design-guidelines frontend-design"
defskills engineer  \$ENG
defskills claude    \$ENG
defskills codex     \$ENG
defskills designer  frontend-design web-design-guidelines vercel-composition-patterns
agentctl prep-all
# engineer moved from Codex to Claude Code: same identity, memory, workspace and instructions
if [ "\$(awk '\$1=="engineer"{print \$2}' agents.list)" = codex ]; then agentctl runtime engineer claude --no-restart; fi
add() { grep -q "^\$1 " agents.list && echo "exists: \$1" || agentctl add "\$@"; }
add pm        claude --name PM        --respond-to anyone --about "Product manager: specs, priorities, task breakdown, status."
add designer  claude --name Designer  --respond-to anyone --about "Product & UX designer: flows, UI specs, mockups, design review."
add marketing claude --name Marketing --respond-to anyone --about "Marketing: positioning, copy, launches, content."
add engineer  claude --name Engineer  --respond-to anyone --mem 4g --about "Software engineer: technical design, code, estimates, reviews."
# engineer runs dev servers + headless Chrome for e2e: raise the old 2g default (change later with: agentctl mem …)
if [ "\$(awk '\$1=="engineer"{print \$3}' agents.list)" = 2g ]; then agentctl mem engineer 4g --no-restart; fi
# model + effort per role, only where none is set yet (change later with: agentctl model <id> …)
defmodel() { grep -qE '^(ANTHROPIC_MODEL|CLAUDE_CODE_EFFORT_LEVEL|CODEX_CONFIG)=' "\$1.env" || agentctl model "\$@" --no-restart; }
defmodel claude    opus    medium    # general assistant: strongest model, everyday effort
defmodel pm        sonnet  medium    # conversation, specs, summaries; deep-work subagent for heavy lifting
defmodel designer  sonnet  medium
defmodel marketing sonnet  medium
defmodel engineer  opus    medium    # design and code: strongest model, everyday effort
defmodel codex     default medium    # Codex default model; effort up from Codex's default (low)
agentctl sync
# keep Buzz profiles in step with the roster
for id in claude codex pm designer marketing engineer; do
  agentctl profile "\$id" --name "\$(sed -n 1p \$id.meta)" --about "\$(sed -n 2p \$id.meta)" | grep -E "^profile|warning" || true
done
docker compose -p buzz-agents up -d 2>&1 | grep -E "Recreated|Error" || true
sleep 8
agentctl list
REMOTE
"$HERE/ssm-run.sh" "$BUILD/remote.sh"
