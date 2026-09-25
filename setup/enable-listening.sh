# Runs on the instance: set which channels each team agent listens to, then rebuild + restart.
set -euo pipefail
cd /opt/buzz-agents
echo "${RELAY_SELF_HEX:?set RELAY_SELF_HEX in config.env}" > relay.hex   # relay "self" key (NIP-11)
echo "general product" > pm.listen
echo "design"          > designer.listen
echo "marketing"       > marketing.listen
echo "engineering"     > engineer.listen
agentctl render
agentctl sync
sleep 15
for id in pm designer marketing engineer claude; do
  L=$(docker logs --since 2m buzz-agents-$id-1 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  printf "%-10s subscribe=%-9s connected=%-4s errors=%s\n" $id \
    "$(grep -o 'subscribe=[A-Za-z]*' <<<"$L" | tail -1 | cut -d= -f2)" \
    "$(grep -q 'connected to relay' <<<"$L" && echo yes || echo NO)" \
    "$(grep -c -E ' ERROR |config file error|rule' <<<"$L" || true)"
done
grep -h "rule\|filter\|config" <(docker logs --since 2m buzz-agents-pm-1 2>&1 | sed 's/\x1b\[[0-9;]*m//g') | cut -c1-200 | head -5
