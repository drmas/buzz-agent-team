#!/usr/bin/env bash
# Run a local bash script on the Buzz instance via SSM and print its output. Settings from
# config.env (next to this script) are exported at the top of the remote script.
# Usage: ./ssm-run.sh script.sh        (INSTANCE_ID / AWS_REGION from config.env or the environment)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
_id=${INSTANCE_ID:-}; _region=${AWS_REGION:-}
[ -f "$HERE/config.env" ] && { set -a; . "$HERE/config.env"; set +a; }
INSTANCE_ID=${_id:-${INSTANCE_ID:-}}; REGION=${_region:-${AWS_REGION:-us-east-1}}
: "${INSTANCE_ID:?set INSTANCE_ID in config.env or the environment}"
VARS="RELAY_URL OWNER_HEX RELAY_SELF_HEX GENERAL_CHANNEL_ID ENGINEERING_CHANNEL_ID TEAM_NAME OWNER_NAME"
B64=$( { for v in $VARS; do [ -n "${!v:-}" ] && printf 'export %s=%q\n' "$v" "${!v}"; done; cat "${1:?script}"; } | base64 -w0)
ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
  --parameters "commands=[\"echo $B64 | base64 -d | bash\"],executionTimeout=[\"1800\"]" --query Command.CommandId --output text)
while :; do
  S=$(aws ssm get-command-invocation --region "$REGION" --command-id "$ID" --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || echo Pending)
  case "$S" in Pending|InProgress|Delayed) sleep 5 ;; *) break ;; esac
done
aws ssm get-command-invocation --region "$REGION" --command-id "$ID" --instance-id "$INSTANCE_ID" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text
echo "==> $S"; [[ "$S" == Success ]]
