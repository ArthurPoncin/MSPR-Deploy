# MSPR-Deploy

Orchestration Docker Compose de la plateforme **MSPR HealthAI Coach**.

Deux modes :

- **Mode prod** (`docker-compose.yml`) : pull les images publiees sur GHCR. Zero clone supplementaire, ideal pour evaluation et demo.
- **Mode dev** (`docker-compose.dev.yml` + `bootstrap-dev.sh`) : clone les 8 depots sources sur leurs branches actives et build localement.

## Prerequis

- Docker Engine 24+ (Linux/macOS/Windows)
- Docker Compose v2 (inclus dans Docker Desktop)
- ~10 Go d'espace disque (pour Ollama gemma3:4b notamment)
- Ports libres : `3000`, `5173`, `5433`, `5434`, `8001`, `8002`, `8080`, `27018`
- Pour le mode dev : `git`, `bash`, `openssl`

## Mode prod : demarrage rapide

```bash
git clone git@github.com:ArthurPoncin/MSPR-Deploy.git
cd MSPR-Deploy
cp .env.example .env
# Generer le secret JWT puis l'inserer dans .env :
openssl rand -base64 64
docker compose up -d
```

Au premier lancement, Docker pull les 8 images depuis GHCR (`ghcr.io/whitefoxxyt/mspr-*:latest`) puis Ollama telecharge `gemma3:4b` (~3 Go). Comptez 5 a 10 minutes selon la connexion.

## Mode dev : setup en une commande

```bash
git clone git@github.com:ArthurPoncin/MSPR-Deploy.git
cd MSPR-Deploy
./bootstrap-dev.sh
```

Le script :

1. clone les 8 depots `whitefoxxyt/MSPR-HealthAI-Coach-*` dans `sources/` sur les branches actives (`main`, `master`, `Sonar`, `dev`) ;
2. cree `.env` depuis `.env.example` si absent et genere `BETTER_AUTH_SECRET` ;
3. lance `docker compose -f docker-compose.dev.yml up -d --build`.

Re-execution : le script fetch/pull les sources existantes (fast-forward only) puis relance le build.
Pour ne pas demarrer la stack a la fin : `./bootstrap-dev.sh --no-up`.

## Acces aux services

| Service | URL | Description |
|---------|-----|-------------|
| Frontend Vue 3 | http://localhost:5173 | Dashboard admin / data scientist |
| API Spring Boot | http://localhost:8080/api/swagger-ui.html | Swagger UI |
| Service Auth (Bun) | http://localhost:3000 | Endpoints better-auth |
| IA Nutrition (FastAPI) | http://localhost:8001/docs | Classification aliments + plan repas |
| Reco Fitness (FastAPI) | http://localhost:8002/docs | Recommandations fitness |
| PostgreSQL metier | localhost:5434 | base `healthai` |
| PostgreSQL auth | localhost:5433 | base `auth_db` |
| MongoDB reco | localhost:27018 | base `reco_fitness` |

## Verifier que tout est sain

```bash
docker compose ps
curl http://localhost:8080/api/actuator/health
curl http://localhost:8001/health
curl http://localhost:8002/health
```

## Commandes utiles

Les commandes ci-dessous sont en mode prod (compose file par defaut). En mode dev, ajouter `-f docker-compose.dev.yml` apres `docker compose`.

```bash
# Suivre les logs d'un service
docker compose logs -f api

# Arreter sans supprimer les donnees
docker compose down

# Reset complet (efface volumes : BDD, Mongo, Ollama)
docker compose down -v

# Mode prod : forcer le pull des dernieres images
docker compose pull && docker compose up -d

# Mode dev : rebuild apres modification d'un service source
docker compose -f docker-compose.dev.yml up -d --build api
```

## Configuration

Le `.env.example` documente chaque variable. Les seuls champs obligatoires sont :

- `BETTER_AUTH_SECRET` : secret HMAC partage entre `auth` et `api` (a generer)
- `RESEND_API_KEY` : cle Resend pour les emails (une cle de demo est fournie)

Les autres variables ont des valeurs par defaut dans le compose et restent commentees.

## Architecture

8 microservices independants connectes via le reseau Docker `mspr_data_network`.

```
front ─┐
       ├─> api (Spring Boot, JWT verify) ─> db (PostgreSQL metier)
auth ──┤    ai-nutrition (FastAPI) ─────────> ollama (gemma3:4b, reseau isole)
       │    reco-fitness (FastAPI) ────────> mongo (PostgreSQL + MongoDB)
       └─> auth-db (PostgreSQL auth)
              ^
              └─ auth-migrate (Drizzle, run once)

etl (Python, cron 0 2 * * *) ─────────────> db
```

## Depots sources

Les images GHCR sont buildees depuis ces depots publics. Le mode dev les clone dans `sources/`.

| Service | Branche active | Repository |
|---------|----------------|------------|
| `mspr-db` | `main` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-BDD |
| `mspr-auth` | `main` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-Auth |
| `mspr-api` | `Sonar` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-API |
| `mspr-etl` | `master` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-ETL |
| `mspr-front` | `dev` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-Dahsboard |
| `mspr-ai-nutrition` | `master` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-AI-Nutrition |
| `mspr-reco-fitness` | `master` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-Reco-Fitness- |
| `mspr-mongodb` | `master` | https://github.com/whitefoxxyt/MSPR-HealthAI-Coach-MongoDB |

## Depannage

**Le pull Ollama est tres long.** Le premier `docker compose up` telecharge `gemma3:4b` (~3 Go). Suivre avec `docker compose logs -f ollama`.

**Erreur `BETTER_AUTH_SECRET is required`.** Generer puis renseigner la valeur dans `.env` : `openssl rand -base64 64`.

**Conflit de port.** Adapter la partie hote des mappings dans `docker-compose.yml` (ex : `"15173:5173"`).

**Reset complet.** `docker compose down -v` supprime tous les volumes ; le prochain `up` repart d'une base vierge et l'ETL recharge les datasets.

**Re-cloner les sources (mode dev).** Supprimer un sous-dossier de `sources/` et relancer `./bootstrap-dev.sh`.
