# Runs on the instance (via ssm-run.sh, which passes RELAY_URL and OWNER_HEX from config.env). Sets up isolated Claude Code + Codex agent
# containers that connect to the hosted community relay. Idempotent: existing agent
# keys are kept. API keys come from SSM Parameter Store (/buzz/*) and are never printed.
set -euo pipefail
: "${RELAY_URL:?set RELAY_URL in config.env}" "${OWNER_HEX:?set OWNER_HEX in config.env}"
AGENTS="claude codex"
DIR=/opt/buzz-agents

command -v aws >/dev/null || snap install aws-cli --classic >/dev/null
install -d -m 0700 "$DIR" "$DIR/secrets"
cd "$DIR"

cat > Dockerfile <<'EOF'
FROM ghcr.io/block/buzz-sprig:sha-6530b58@sha256:17facfc7608d8ddb33bc056c9aaba1098f4ef6abe5655702fbfd7584d1f74d76
USER root
RUN apk add --no-cache nodejs npm ripgrep \
 && npm i -g @anthropic-ai/claude-code@2.1.281 @openai/codex@0.156.1 \
      @agentclientprotocol/claude-agent-acp@0.81.2 @agentclientprotocol/codex-acp@1.13.1 \
 && npm cache clean --force
RUN apk add --no-cache chromium nss freetype harfbuzz ttf-freefont font-noto-emoji
RUN apk add --no-cache ffmpeg && npm i -g playwright-core@1.63.0 && npm cache clean --force   # proof tool
ENV CHROME_BIN=/usr/bin/chromium-browser PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser PUPPETEER_SKIP_DOWNLOAD=true PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
USER agent
EOF

cat > compose.yml <<'EOF'
# One container per agent: own identity, volumes, network, and resource limits.
x-agent: &agent
  build: .
  image: buzz-agent:local
  restart: on-failure            # an owner !shutdown stays stopped
  read_only: true
  tmpfs: ["/tmp:size=512m"]
  shm_size: 1g                   # headless Chrome needs more than Docker's 64 MB /dev/shm
  cap_drop: [ALL]
  security_opt: ["no-new-privileges:true"]
  pids_limit: 512
  mem_limit: 3g
  cpus: 1.5
  environment:
    BUZZ_RELAY_URL: ${RELAY_URL}
  logging:
    driver: json-file
    options: { max-size: "10m", max-file: "3" }

services:
  claude:
    <<: *agent
    environment:
      BUZZ_RELAY_URL: ${RELAY_URL}
      CLAUDE_CODE_EXECUTABLE: /usr/local/bin/claude   # run the real Claude Code CLI
      DISABLE_AUTOUPDATER: "1"                        # image is read-only; rebuild to upgrade
    env_file:
      - claude.env
      - { path: secrets/claude.env, required: false }
    volumes: [claude-home:/home/agent, claude-ws:/workspace]
    networks: [claude-net]
  codex:
    <<: *agent
    environment:
      BUZZ_RELAY_URL: ${RELAY_URL}
      CODEX_PATH: /usr/local/bin/codex                # run the real Codex CLI
      NO_BROWSER: "1"
    env_file:
      - codex.env
      - { path: secrets/codex.env, required: false }
    volumes: [codex-home:/home/agent, codex-ws:/workspace]
    networks: [codex-net]

networks:
  claude-net: {}
  codex-net: {}
volumes:
  claude-home: {}
  claude-ws: {}
  codex-home: {}
  codex-ws: {}
EOF
echo "RELAY_URL=$RELAY_URL" > .env

cat > refresh-secrets.sh <<'EOF'
#!/bin/bash
# Pull model API keys from SSM Parameter Store into root-only env files.
set -euo pipefail
cd /opt/buzz-agents; umask 077
get() { aws ssm get-parameter --region us-east-1 --with-decryption --name "$1" --query Parameter.Value --output text 2>/dev/null || true; }
# Claude: subscription token from `claude setup-token` (preferred) or an API key.
k=$(get /buzz/claude-oauth-token); a=$(get /buzz/anthropic-api-key)
if   [ -n "$k" ]; then printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$k" > secrets/claude.env; echo "claude: subscription token loaded"
elif [ -n "$a" ]; then printf 'ANTHROPIC_API_KEY=%s\n' "$a" > secrets/claude.env;       echo "claude: API key loaded"
else echo "claude: no /buzz/claude-oauth-token or /buzz/anthropic-api-key"; fi
# Codex: ChatGPT login lives in the codex-home volume (~/.codex/auth.json); API key is optional.
k=$(get /buzz/openai-api-key); [ -n "$k" ] && printf 'OPENAI_API_KEY=%s\n' "$k" > secrets/codex.env && echo "codex: API key loaded" || true
# All agents: TypeSafe (Jev) key for turn-gate. Without it turn-gate always answers REPLY.
k=$(get /buzz/typesafe-api-key); if [ -n "$k" ]; then printf 'TYPESAFE_API_KEY=%s\n' "$k" > secrets/common.env; echo "typesafe: API key loaded"; else rm -f secrets/common.env; fi
EOF
chmod 700 refresh-secrets.sh

# Per-agent Nostr identity (generated once, root-only).
umask 077
for a in $AGENTS; do
  if [ ! -f "$a.env" ]; then
    out=$(docker run --rm --entrypoint /usr/local/bin/buzz-admin ghcr.io/block/buzz:main generate-key)
    sk=$(awk '/Secret key:/{print $3}' <<<"$out")
    awk '/Public key:/{print $3}' <<<"$out" > "$a.pub"
    [[ "$sk" =~ ^[0-9a-f]{64}$ ]] || { echo "key generation failed for $a"; exit 1; }
    printf 'BUZZ_PRIVATE_KEY=%s\nBUZZ_ACP_AGENT_COMMAND=%s\nBUZZ_ACP_AGENT_OWNER=%s\n' \
      "$sk" "$([ "$a" = claude ] && echo claude-agent-acp || echo codex-acp)" "$OWNER_HEX" > "$a.env"
  fi
done

./refresh-secrets.sh
docker compose -p buzz-agents build -q
docker compose -p buzz-agents run -T --rm --no-deps --entrypoint sh claude -c \
  'for b in buzz-acp claude-agent-acp codex-acp; do printf "%s: " $b; command -v $b || echo MISSING; done; id; \
   echo "claude CLI: $(claude --version 2>&1 | head -1)"; echo "codex CLI: $(codex --version 2>&1 | head -1)"; \
   wget -q -T 3 -O- --header "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token >/dev/null 2>&1 \
     && echo "IMDS: REACHABLE (bad)" || echo "IMDS: blocked"' </dev/null 2>/dev/null

for a in $AGENTS; do echo "AGENT $a pubkey: $(cat $a.pub)"; done
