#!/usr/bin/env bash
# Bootstrap MSPR HealthAI Coach.
#
# Mode prod (defaut) : pull les images depuis GHCR puis docker compose up.
# Mode dev (--dev)   : clone les 8 depots sources sur leurs branches actives,
#                      prepare .env, puis docker compose up --build.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$ROOT_DIR/sources"
ENV_FILE="$ROOT_DIR/.env"
GITHUB_OWNER="whitefoxxyt"

MODE="prod"
DO_UP=1

usage() {
  cat <<EOF
Usage: ./bootstrap.sh [OPTIONS]

Mode prod (defaut) : pull les images depuis GHCR et lance la stack.
Mode dev (--dev)   : clone les 8 depots sources et build localement.

Options:
  --dev       Active le mode dev (clone + build).
  --no-up     Prepare l'environnement sans lancer docker compose up.
  -h, --help  Affiche cette aide.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dev) MODE="dev" ;;
    --no-up) DO_UP=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argument inconnu : $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# Mapping : nom_local | repo_distant_whitefoxxyt | branche_active
REPOS=(
  "MSPR-DB|MSPR-HealthAI-Coach-BDD|main"
  "MSPR-AUTH|MSPR-HealthAI-Coach-Auth|main"
  "MSPR-API|MSPR-HealthAI-Coach-API|main"
  "MSPR-ETL|MSPR-HealthAI-Coach-ETL|master"
  "MSPR-FRONT|MSPR-HealthAI-Coach-Dahsboard|dev"
  "MSPR-AI-Nutrition|MSPR-HealthAI-Coach-AI-Nutrition|master"
  "MSPR-Reco-Fitness|MSPR-HealthAI-Coach-Reco-Fitness-|master"
  "MSPR-MongoDB|MSPR-HealthAI-Coach-MongoDB|master"
)

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; exit 1; }

# Set-or-append d'une variable dans .env, uniquement si elle est absente ou vide.
ensure_env_value() {
  local var="$1" value="$2" current
  current=$(grep -E "^${var}=" "$ENV_FILE" | head -1 | cut -d= -f2- || true)
  if [[ -z "$current" ]]; then
    local tmp; tmp=$(mktemp)
    awk -v k="$var" -v v="$value" '
      BEGIN { set = 0 }
      $0 ~ "^" k "=" { print k "=" v; set = 1; next }
      { print }
      END { if (!set) print k "=" v }
    ' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    log "$var genere"
  fi
}

# Mot de passe alphanumerique (URL-safe pour les chaines postgres://...).
gen_password() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24; }

# --- Prerequis ---------------------------------------------------------------
for cmd in docker openssl; do
  command -v "$cmd" >/dev/null || fail "Commande requise absente : $cmd"
done
if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose v2 introuvable. Mettre a jour Docker."
fi
if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon non accessible. Verifier que Docker tourne."
fi

# --- Clone des sources (mode dev uniquement) --------------------------------
if [[ "$MODE" == "dev" ]]; then
  command -v git >/dev/null || fail "git requis pour le mode dev"
  mkdir -p "$SOURCES_DIR"
  for entry in "${REPOS[@]}"; do
    IFS='|' read -r local_name remote_name branch <<<"$entry"
    target="$SOURCES_DIR/$local_name"
    url="https://github.com/$GITHUB_OWNER/$remote_name.git"
    if [[ -d "$target/.git" ]]; then
      log "$local_name : fetch + checkout $branch"
      git -C "$target" fetch --quiet origin
      git -C "$target" checkout --quiet "$branch"
      git -C "$target" pull --quiet --ff-only origin "$branch"
    else
      log "$local_name : clone (branche $branch)"
      git clone --quiet --branch "$branch" "$url" "$target"
    fi
  done
fi

# --- Preparation .env --------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
  log ".env cree depuis .env.example"
fi

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
  log "BETTER_AUTH_SECRET genere"
fi

# Mots de passe des bases generes si absents (evite le defaut 'password' en exploitation).
# Sur un volume deja initialise avec l'ancien mot de passe, faire d'abord un reset (down -v).
ensure_env_value DB_PASSWORD "$(gen_password)"
ensure_env_value AUTH_DB_PASSWORD "$(gen_password)"

# --- Dechiffrement des cles chiffrees ---------------------------------------
RESEND_ENC="$ROOT_DIR/secrets/resend.enc"
MISTRAL_ENC="$ROOT_DIR/secrets/mistral.enc"

current_resend=$(grep -E '^RESEND_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)
current_mistral=$(grep -E '^MISTRAL_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)

need_resend=0
need_mistral=0
[[ -z "$current_resend" && -f "$RESEND_ENC" ]] && need_resend=1
[[ -z "$current_mistral" && -f "$MISTRAL_ENC" ]] && need_mistral=1

if [[ "$need_resend" -eq 1 || "$need_mistral" -eq 1 ]]; then
  if [[ -n "${MSPR_PASS:-}" ]]; then
    pass="$MSPR_PASS"
  else
    printf '\033[1;34m[bootstrap]\033[0m Passphrase pour dechiffrer les cles API (Resend + Mistral) : '
    read -rs pass
    echo
  fi

  if [[ "$need_resend" -eq 1 ]]; then
    if decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -salt -pass pass:"$pass" -in "$RESEND_ENC" 2>/dev/null) \
        && [[ "$decrypted" =~ ^re_ ]]; then
      tmp=$(mktemp)
      awk -v key="$decrypted" '
        BEGIN { set = 0 }
        /^RESEND_API_KEY=/ { print "RESEND_API_KEY=" key; set = 1; next }
        { print }
        END { if (!set) print "RESEND_API_KEY=" key }
      ' "$ENV_FILE" > "$tmp"
      mv "$tmp" "$ENV_FILE"
      log "RESEND_API_KEY dechiffree depuis secrets/resend.enc"
    else
      fail "Dechiffrement Resend echoue (passphrase incorrecte ?). Relancez ou renseignez RESEND_API_KEY a la main."
    fi
    unset decrypted
  fi

  if [[ "$need_mistral" -eq 1 ]]; then
    if decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 -salt -pass pass:"$pass" -in "$MISTRAL_ENC" 2>/dev/null) \
        && [[ "$decrypted" =~ ^[A-Za-z0-9]{20,}$ ]]; then
      tmp=$(mktemp)
      awk -v key="$decrypted" '
        BEGIN { set = 0 }
        /^MISTRAL_API_KEY=/ { print "MISTRAL_API_KEY=" key; set = 1; next }
        { print }
        END { if (!set) print "MISTRAL_API_KEY=" key }
      ' "$ENV_FILE" > "$tmp"
      mv "$tmp" "$ENV_FILE"
      log "MISTRAL_API_KEY dechiffree depuis secrets/mistral.enc"
    else
      fail "Dechiffrement Mistral echoue (passphrase incorrecte ?). Relancez ou renseignez MISTRAL_API_KEY a la main."
    fi
    unset decrypted
  fi

  unset pass
else
  [[ -z "$current_resend" && ! -f "$RESEND_ENC" ]] && log "secrets/resend.enc absent : passez votre propre RESEND_API_KEY dans .env"
  [[ -z "$current_mistral" && ! -f "$MISTRAL_ENC" ]] && log "secrets/mistral.enc absent : MISTRAL_API_KEY vide, Ollama sera utilise en fallback"
fi

# --- Selection du compose file ----------------------------------------------
if [[ "$MODE" == "dev" ]]; then
  COMPOSE_FILE="$ROOT_DIR/docker-compose.dev.yml"
  UP_FLAGS=(-d --build)
else
  COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
  UP_FLAGS=(-d)
fi
COMPOSE_NAME=$(basename "$COMPOSE_FILE")

# --- Lancement ---------------------------------------------------------------
if [[ "$DO_UP" -eq 1 ]]; then
  log "Mode $MODE : docker compose -f $COMPOSE_NAME up ${UP_FLAGS[*]}"
  log "Au premier run, comptez 5 a 10 min (pull/build + telechargement Ollama)."
  cd "$ROOT_DIR"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up "${UP_FLAGS[@]}"
  log "Stack demarree (mode $MODE)."
  log "Status   : docker compose -f $COMPOSE_NAME ps"
  log "Logs     : docker compose -f $COMPOSE_NAME logs -f"
  log "Frontend : http://localhost:5173"
  log "API doc  : http://localhost:8080/api/swagger-ui.html"
else
  log "Setup termine (mode $MODE). Pour lancer :"
  build_flag=""
  [[ "$MODE" == "dev" ]] && build_flag=" --build"
  log "  docker compose -f $COMPOSE_NAME up -d$build_flag"
fi
