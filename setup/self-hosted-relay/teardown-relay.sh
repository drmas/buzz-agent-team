set -euo pipefail
cd /opt/buzz/deploy/compose
docker compose --env-file .env -f compose.yml -f compose.caddy.yml down -v --remove-orphans 2>&1
rm -f .env
git checkout -- compose.yml
docker ps -a --format '{{.Names}}' | grep buzz-prod || echo "self-hosted relay removed"
docker volume ls -q | grep buzz-prod || echo "volumes removed"
