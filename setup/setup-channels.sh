# Runs on the instance: create role channels (idempotent), add members, save ids to channels.json.
set -uo pipefail
cd /opt/buzz-agents
X() { a=$1; shift; docker compose -p buzz-agents exec -T $a buzz "$@" </dev/null 2>/dev/null; }
MO=$(cat owner.hex); pk() { cat "$1.pub"; }
find_id() { X claude channels list --visibility open | python3 -c "import json,sys
for c in json.load(sys.stdin):
    if c['name']=='$1': print(c['channel_id'])" | head -1; }
create() {  # creator name description
  id=$(find_id "$2")
  if [ -z "$id" ]; then
    out=$(X "$1" channels create --name "$2" --type stream --visibility open --description "$3")
    id=$(grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' <<<"$out" | head -1)
    echo "created #$2 ($id) by $1" >&2
  else echo "exists  #$2 ($id)" >&2; fi
  echo "$id"
}
add() {  # actor channel pubkey role
  r=$(X "$1" channels add-member --channel "$2" --pubkey "$3" ${4:+--role $4}); sleep 1
  grep -q -i '"accepted":true\|"ok":true\|already' <<<"$r" || echo "  add $3 -> $2: $(head -c 160 <<<"$r")" >&2
}
GEN=${GENERAL_CHANNEL_ID:?set GENERAL_CHANNEL_ID in config.env}; ENG=${ENGINEERING_CHANNEL_ID:?set ENGINEERING_CHANNEL_ID in config.env}
PROD=$(create pm product "Product: priorities, specs, roadmap and decisions. PM listens here.")
DES=$(create designer design "Design: UX flows, UI specs, mockups and reviews. Designer listens here.")
MKT=$(create marketing marketing "Marketing: positioning, copy, launches and content. Marketing listens here.")
for ch in "$PROD" "$DES" "$MKT"; do [ -n "$ch" ] || { echo "channel creation failed"; exit 1; }; done
add pm "$PROD" "$MO" admin; for a in designer marketing engineer claude codex; do add pm "$PROD" "$(pk $a)"; done
add designer "$DES" "$MO" admin; for a in pm claude; do add designer "$DES" "$(pk $a)"; done
add marketing "$MKT" "$MO" admin; for a in pm claude; do add marketing "$MKT" "$(pk $a)"; done
printf '{"general":"%s","engineering":"%s","product":"%s","design":"%s","marketing":"%s"}\n' "$GEN" "$ENG" "$PROD" "$DES" "$MKT" > channels.json
cat channels.json
for a in pm designer marketing engineer claude; do printf "%-10s member of: " $a; X $a channels list | python3 -c 'import json,sys; print(", ".join(sorted(c["name"] for c in json.load(sys.stdin) if "DM" not in c["name"])))'; done
