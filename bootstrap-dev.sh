#!/usr/bin/env bash
# Bootstrap dev MSPR HealthAI Coach.
# Clone les 8 depots sources sur leurs branches actives, prepare .env,
# puis lance la stack en mode dev (build local).
#
# Usage : ./bootstrap-dev.sh [--no-up]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$ROOT_DIR/sources"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/docker-compose.dev.yml"
GITHUB_OWNER="whitefoxxyt"
DO_UP=1

for arg in "$@"; do
  case "$arg" in
    --no-up) DO_UP=0 ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Argument inconnu : $arg" >&2; exit 2 ;;
  esac
done

# Mapping : nom_local | repo_distant_whitefoxxyt | branche_active
REPOS=(
  "MSPR-DB|MSPR-HealthAI-Coach-BDD|main"
  "MSPR-AUTH|MSPR-HealthAI-Coach-Auth|main"
  "MSPR-API|MSPR-HealthAI-Coach-API|Sonar"
  "MSPR-ETL|MSPR-HealthAI-Coach-ETL|master"
  "MSPR-FRONT|MSPR-HealthAI-Coach-Dahsboard|dev"
  "MSPR-AI-Nutrition|MSPR-HealthAI-Coach-AI-Nutrition|master"
  "MSPR-Reco-Fitness|MSPR-HealthAI-Coach-Reco-Fitness-|master"
  "MSPR-MongoDB|MSPR-HealthAI-Coach-MongoDB|master"
)

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "bootstrap" "$*"; }
fail() { printf '\033[1;31m[%s]\033[0m %s\n' "bootstrap" "$*" >&2; exit 1; }

# --- Prerequis ---------------------------------------------------------------
for cmd in git docker openssl; do
  command -v "$cmd" >/dev/null || fail "Commande requise absente : $cmd"
done

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose v2 introuvable. Mettre a jour Docker."
fi

if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon non accessible. Verifier que Docker tourne."
fi

# --- Clone / update des sources ---------------------------------------------
mkdir -p "$SOURCES_DIR"

for entry in "${REPOS[@]}"; do
  IFS='|' read -r local_name remote_name branch <<<"$entry"
  target="$SOURCES_DIR/$local_name"
  url="https://github.com/$GITHUB_OWNER/$remote_name.git"

  if [[ -d "$target/.git" ]]; then
    log "$local_name : deja clone, fetch + checkout $branch"
    git -C "$target" fetch --quiet origin
    git -C "$target" checkout --quiet "$branch"
    git -C "$target" pull --quiet --ff-only origin "$branch"
  else
    log "$local_name : clone (branche $branch)"
    git clone --quiet --branch "$branch" "$url" "$target"
  fi
done

# --- Preparation .env --------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  log ".env cree depuis .env.example"
fi

# Genere BETTER_AUTH_SECRET si absent ou vide
current_secret=$(grep -E '^BETTER_AUTH_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)
if [[ -z "$current_secret" ]]; then
  new_secret=$(openssl rand -base64 64 | tr -d '\n')
  tmp=$(mktemp)
  awk -v secret="$new_secret" '
    BEGIN { set = 0 }
    /^BETTER_AUTH_SECRET=/ { print "BETTER_AUTH_SECRET=" secret; set = 1; next }
    { print }
    END { if (!set) print "BETTER_AUTH_SECRET=" secret }
  ' "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
  log "BETTER_AUTH_SECRET genere et ecrit dans .env"
fi

# --- Lancement du compose dev ------------------------------------------------
if [[ "$DO_UP" -eq 1 ]]; then
  log "docker compose up -d --build (peut prendre 5-10 min au premier run)"
  cd "$ROOT_DIR"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build
  log "Stack dev demarree."
  log "Status   : docker compose -f docker-compose.dev.yml ps"
  log "Logs     : docker compose -f docker-compose.dev.yml logs -f"
  log "Frontend : http://localhost:5173"
  log "API doc  : http://localhost:8080/api/swagger-ui.html"
else
  log "Setup termine sans up. Lancer manuellement :"
  log "  docker compose -f docker-compose.dev.yml up -d --build"
fi
