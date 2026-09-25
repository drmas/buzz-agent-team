#!/usr/bin/env bash
# Turn every AWS agent into a shared assistant: respond to anyone, team rules for all, and the
# NIP-OA owner proof from auth-tags.json (made by sign-owner-proofs.py) so Buzz shows them as
# the owner's agents. Republishes profiles so the proof is on each kind:0.
# Usage: ./share-assistants.sh   (settings from config.env)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/auth-tags.json" ] || { echo "auth-tags.json missing: run sign-owner-proofs.py first"; exit 1; }
"$HERE/deploy-team.sh" >/dev/null   # ship current agentctl + prompt sources

TAGS=$(python3 - "$HERE/auth-tags.json" <<'PY'
import json,sys
for pk,tag in json.load(open(sys.argv[1])).items(): print(pk, tag)
PY
)
SP=$(mktemp); trap 'rm -f "$SP"' EXIT
cat > "$SP" <<REMOTE
set -euo pipefail
cd /opt/buzz-agents
printf 'Claude\nShared general-purpose coding and research assistant (Claude Code).\n' > claude.meta
printf 'Codex\nShared general-purpose coding assistant (Codex).\n' > codex.meta
# claude/codex become shared team members too
awk '{ if (\$1=="claude"||\$1=="codex") \$4="team"; print }' agents.list > agents.list.new && mv agents.list.new agents.list
for id in \$(awk '{print \$1}' agents.list); do
  sed -i '/^BUZZ_ACP_RESPOND_TO=/d' "\$id.env"; echo "BUZZ_ACP_RESPOND_TO=anyone" >> "\$id.env"
done
while read -r pk tag; do
  id=\$(grep -l "^\$pk\$" *.pub | head -1 | sed 's/\.pub\$//')
  [ -n "\$id" ] && agentctl auth "\$id" "\$tag" || echo "no agent for \$pk"
done <<'TAGS'
$TAGS
TAGS
agentctl build >/dev/null
docker compose -p buzz-agents up -d --force-recreate 2>&1 | grep -E "Error" || true
sleep 12
for id in \$(awk '{print \$1}' agents.list); do
  agentctl profile "\$id" --name "\$(sed -n 1p \$id.meta)" --about "\$(sed -n 2p \$id.meta)" 2>/dev/null | grep -E "^profile|warning" || true
done
echo "---- verification ----"
for id in \$(awk '{print \$1}' agents.list); do
  L=\$(docker logs --since 3m buzz-agents-\$id-1 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  printf "%-10s owner_from_proof=%-4s connected=%-4s respond_to=%s\n" "\$id" \
    "\$(grep -q 'owner resolved from BUZZ_AUTH_TAG' <<<"\$L" && echo yes || echo NO)" \
    "\$(grep -q 'connected to relay' <<<"\$L" && echo yes || echo NO)" \
    "\$(grep -o 'respond_to=[a-z-]*' <<<"\$L" | tail -1 | cut -d= -f2)"
done
REMOTE
"$HERE/ssm-run.sh" "$SP"
