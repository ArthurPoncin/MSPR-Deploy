#!/usr/bin/env bash
# Restauration des donnees locales depuis une sauvegarde produite par backup.sh.
# Remplace les donnees existantes (pg_dump --clean, mongorestore --drop).
# Les conteneurs doivent tourner.
#
# Usage : ./scripts/restore.sh [chemin_backup]   (defaut : derniere sauvegarde dans backups/)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${1:-}"

DB_CONTAINER="mspr-healthai-db"
AUTH_DB_CONTAINER="mspr-auth-db"
MONGO_CONTAINER="mspr-mongo"

DB_USER="${DB_USER:-healthai_user}"
DB_NAME="${DB_NAME:-healthai}"
AUTH_DB_USER="${AUTH_DB_USER:-root}"
AUTH_DB_NAME="${AUTH_DB_NAME:-auth_db}"
MONGO_DB="${MONGO_DATABASE:-reco_fitness}"

log()  { printf '\033[1;34m[restore]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[restore]\033[0m %s\n' "$*" >&2; exit 1; }
running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

command -v docker >/dev/null || fail "docker introuvable."

if [[ -z "$BACKUP_DIR" ]]; then
  [[ -d "$ROOT_DIR/backups" ]] || fail "Aucun dossier backups/. Precise un chemin de sauvegarde."
  BACKUP_DIR="$(find "$ROOT_DIR/backups" -mindepth 1 -maxdepth 1 -type d | sort | tail -n1 || true)"
  [[ -n "$BACKUP_DIR" ]] || fail "Aucune sauvegarde trouvee dans backups/."
fi
[[ -d "$BACKUP_DIR" ]] || fail "Dossier introuvable : $BACKUP_DIR"
log "Restauration depuis : $BACKUP_DIR"

for c in "$DB_CONTAINER" "$AUTH_DB_CONTAINER" "$MONGO_CONTAINER"; do
  running "$c" || fail "Conteneur $c non demarre. Lance la stack avant de restaurer."
done

if [[ -f "$BACKUP_DIR/healthai.sql.gz" ]]; then
  log "Restauration PostgreSQL metier ($DB_NAME)"
  gunzip -c "$BACKUP_DIR/healthai.sql.gz" | docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"
fi

if [[ -f "$BACKUP_DIR/auth_db.sql.gz" ]]; then
  log "Restauration PostgreSQL auth ($AUTH_DB_NAME)"
  gunzip -c "$BACKUP_DIR/auth_db.sql.gz" | docker exec -i "$AUTH_DB_CONTAINER" psql -U "$AUTH_DB_USER" -d "$AUTH_DB_NAME"
fi

if [[ -f "$BACKUP_DIR/mongo_${MONGO_DB}.archive.gz" ]]; then
  log "Restauration MongoDB ($MONGO_DB)"
  gunzip -c "$BACKUP_DIR/mongo_${MONGO_DB}.archive.gz" | docker exec -i "$MONGO_CONTAINER" mongorestore --drop --archive
fi

log "Restauration terminee."
