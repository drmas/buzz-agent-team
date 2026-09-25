# Runs on the instance: scheduled check-in workflows (UTC cron). Created by the Claude agent so
# the mentioned agent is never the workflow's own author. Idempotent by workflow name.
set -uo pipefail
cd /opt/buzz-agents
X() { docker compose -p buzz-agents exec -T claude buzz "$@" </dev/null 2>&1; }
ch() { python3 -c "import json,sys;print(json.load(open('channels.json'))[sys.argv[1]])" "$1"; }
mk() {  # channel-name workflow-name yaml
  local cid; cid=$(ch "$1")
  if X workflows list --channel "$cid" | grep -q "name: $2\\\\n"; then echo "exists: $2"; return; fi
  echo "create: $2 -> #$1: $(X workflows create --channel "$cid" --yaml "$3" | head -c 200)"
}
X channels join --channel "$(ch engineering)" | head -c 120; echo
mk general "PM daily digest" "name: PM daily digest
description: Weekday digest of decisions, tasks and blockers
trigger:
  on: schedule
  cron: '0 7 * * 1-5'
steps:
  - id: ask
    action: send_message
    text: '@PM daily digest: review the last 24 hours in #general, #product, #design, #marketing and #engineering. Reply in this thread with a short digest: decisions made, new or open tasks with owners, blockers, and questions waiting on a human. Keep it under 15 lines. If nothing meaningful happened, reply with one line saying so.'"
mk engineering "Engineer daily triage" "name: Engineer daily triage
description: Weekday follow-up on unanswered engineering questions and bugs
trigger:
  on: schedule
  cron: '30 7 * * 1-5'
steps:
  - id: ask
    action: send_message
    text: '@Engineer daily triage: look through #engineering for bugs, errors or technical questions from the last 24 hours that have no answer or no owner. Answer or follow up in their threads, and suggest an owner where needed. Then reply in this thread with a 3-line summary of what you did, or one line if nothing needed attention.'"
mk marketing "Marketing weekly ideas" "name: Marketing weekly ideas
description: Monday content and launch ideas based on recent product activity
trigger:
  on: schedule
  cron: '0 8 * * 1'
steps:
  - id: ask
    action: send_message
    text: '@Marketing weekly ideas: based on the last week in #product, #general and #engineering, propose 2-3 concrete content or launch ideas (audience, channel, hook, and what we would need). Reply in this thread. If there was not enough product activity to base ideas on, say so in one line and ask @PM what is coming up.'"
for c in general engineering marketing; do printf "#%-12s " $c; X workflows list --channel "$(ch $c)" | grep -o '"name":"[^"]*"' | tr '\n' ' '; echo; done
