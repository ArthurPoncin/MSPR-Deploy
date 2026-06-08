#!/usr/bin/env bash
# Remise a zero de la stack MSPR HealthAI Coach.
# Arrete les services et supprime les volumes (BDD, Mongo, Ollama, monitoring).
# Le prochain demarrage repart d'une base vierge (l'ETL recharge les datasets).
#
# Usage : ./scripts/clean.sh [--dev] [--force]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="prod"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dev) MODE="dev" ;;
    --force|-y) FORCE=1 ;;
    -h|--help) echo "Usage: ./scripts/clean.sh [--dev] [--force]"; exit 0 ;;
    *) echo "Argument inconnu : $arg" >&2; exit 2 ;;
  esac
done

BASE="docker-compose.yml"
[[ "$MODE" == "dev" ]] && BASE="docker-compose.dev.yml"

FILES=(-f "$BASE")
[[ -f "$ROOT_DIR/docker-compose.monitoring.yml" ]] && FILES+=(-f docker-compose.monitoring.yml)

if [[ "$FORCE" -ne 1 ]]; then
  printf '\033[1;33m[clean]\033[0m Supprime TOUS les volumes (donnees BDD, Mongo, Ollama, monitoring). Continuer ? [y/N] '
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Annule."; exit 0; }
fi

echo "[clean] docker compose ${FILES[*]} down -v --remove-orphans"
( cd "$ROOT_DIR" && docker compose "${FILES[@]}" down -v --remove-orphans )
echo "[clean] Remise a zero terminee. Le prochain './bootstrap.sh' repart vierge."
