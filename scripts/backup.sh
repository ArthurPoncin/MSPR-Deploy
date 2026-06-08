#!/usr/bin/env bash
# Sauvegarde des donnees locales de la stack MSPR HealthAI Coach.
# Dump PostgreSQL metier (healthai) + PostgreSQL auth (auth_db) + MongoDB (reco_fitness).
# Les conteneurs doivent tourner. Sortie horodatee dans backups/<timestamp>/.
#
# Usage : ./scripts/backup.sh [dossier_sortie]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${1:-$ROOT_DIR/backups/$TS}"

DB_CONTAINER="mspr-healthai-db"
AUTH_DB_CONTAINER="mspr-auth-db"
MONGO_CONTAINER="mspr-mongo"

DB_USER="${DB_USER:-healthai_user}"
DB_NAME="${DB_NAME:-healthai}"
AUTH_DB_USER="${AUTH_DB_USER:-root}"
AUTH_DB_NAME="${AUTH_DB_NAME:-auth_db}"
MONGO_DB="${MONGO_DATABASE:-reco_fitness}"

log()  { printf '\033[1;34m[backup]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[backup]\033[0m %s\n' "$*" >&2; exit 1; }
running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

command -v docker >/dev/null || fail "docker introuvable."
for c in "$DB_CONTAINER" "$AUTH_DB_CONTAINER" "$MONGO_CONTAINER"; do
  running "$c" || fail "Conteneur $c non demarre. Lance la stack avant de sauvegarder."
done

mkdir -p "$OUT_DIR"
log "Sortie : $OUT_DIR"

log "Dump PostgreSQL metier ($DB_NAME)"
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" --clean --if-exists "$DB_NAME" | gzip > "$OUT_DIR/healthai.sql.gz"

log "Dump PostgreSQL auth ($AUTH_DB_NAME)"
docker exec "$AUTH_DB_CONTAINER" pg_dump -U "$AUTH_DB_USER" --clean --if-exists "$AUTH_DB_NAME" | gzip > "$OUT_DIR/auth_db.sql.gz"

log "Dump MongoDB ($MONGO_DB)"
docker exec "$MONGO_CONTAINER" mongodump --db "$MONGO_DB" --archive | gzip > "$OUT_DIR/mongo_${MONGO_DB}.archive.gz"

log "Sauvegarde terminee :"
ls -lh "$OUT_DIR"
