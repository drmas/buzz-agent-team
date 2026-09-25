#!/usr/bin/env bash
# Configure and start the Buzz relay (Postgres/Redis/MinIO/Caddy TLS) on the instance via SSM.
# Usage: INSTANCE_ID=i-... ./configure-relay.sh buzz.example.com [owner-pubkey-hex]
# Secrets are generated on the server and never printed.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
DOMAIN="${1:?Usage: $0 <domain> [owner-pubkey-hex]}"
OWNER="${2:-}"
: "${INSTANCE_ID:?set INSTANCE_ID}"
[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || { echo "Bad domain: $DOMAIN"; exit 1; }
[[ -z "$OWNER" || "$OWNER" =~ ^[0-9a-f]{64}$ ]] || { echo "Owner pubkey must be 64 hex chars"; exit 1; }

REMOTE=$(cat <<EOF
set -euo pipefail
DOMAIN='$DOMAIN'; OWNER='$OWNER'
for i in \$(seq 60); do [ -f /var/lib/buzz-bootstrap-done ] && break; sleep 10; done
[ -f /var/lib/buzz-bootstrap-done ] || { echo "bootstrap not finished; see /var/log/buzz-bootstrap.log"; exit 1; }
cd /opt/buzz/deploy/compose
IMG=ghcr.io/block/buzz:main
genkey() { docker run --rm --entrypoint /usr/local/bin/buzz-admin "\$IMG" generate-key; }
if [ ! -f .env ]; then
  umask 077
  cp .env.example .env
  sed -i "s/buzz\.example\.com/\$DOMAIN/g" .env
  for n in \$(grep 'CHANGE_ME_RANDOM' .env | cut -d= -f1); do sed -i "s|^\$n=.*|\$n=\$(openssl rand -hex 32)|" .env; done
  RELAY_SK=\$(genkey | awk '/Secret key:/{print \$3}')
  sed -i "s|^BUZZ_RELAY_PRIVATE_KEY=.*|BUZZ_RELAY_PRIVATE_KEY=\$RELAY_SK|" .env
  if [ -z "\$OWNER" ]; then
    genkey > /root/buzz-owner.key
    OWNER=\$(awk '/Public key:/{print \$3}' /root/buzz-owner.key)
    echo "Generated owner key: secret saved to /root/buzz-owner.key (root-only)"
  fi
  sed -i "s|^RELAY_OWNER_PUBKEY=.*|RELAY_OWNER_PUBKEY=\$OWNER|" .env
  chmod 600 .env
fi
grep -v "^#" .env | grep -q CHANGE_ME && { echo "Unfilled values remain in .env:"; grep -v "^#" .env | grep CHANGE_ME | cut -d= -f1; exit 1; }
# quay.io/minio/* now denies anonymous pulls; use Block's rebuild of the same
# MinIO/mc releases (ghcr.io/block/buzz-minio), pinned to the digest pulled here.
if grep -q 'quay.io/minio/' compose.yml; then
  docker pull -q ghcr.io/block/buzz-minio:latest >/dev/null
  MINIO_IMG=\$(docker inspect --format '{{index .RepoDigests 0}}' ghcr.io/block/buzz-minio:latest)
  sed -i "s|image: quay.io/minio/[^ ]*|image: \$MINIO_IMG|" compose.yml
  echo "MinIO image -> \$MINIO_IMG"
fi
BUZZ_COMPOSE_TLS=true ./run.sh start
./run.sh status || true
echo "Owner pubkey: \$(grep ^RELAY_OWNER_PUBKEY= .env | cut -d= -f2)"
echo "Relay URL:    \$(grep ^RELAY_URL= .env | cut -d= -f2)"
EOF
)

B64=$(printf '%s' "$REMOTE" | base64 -w0)
CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --comment "buzz relay setup" --timeout-seconds 600 \
  --parameters "commands=[\"echo $B64 | base64 -d | bash\"],executionTimeout=[\"1800\"]" \
  --query Command.CommandId --output text)
echo "==> SSM command $CMD_ID sent; waiting..."

while :; do
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in Pending|InProgress|Delayed) sleep 10 ;; *) break ;; esac
done
aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query '[StandardOutputContent,StandardErrorContent]' --output text
echo "==> Status: $STATUS"
[[ "$STATUS" == Success ]]
