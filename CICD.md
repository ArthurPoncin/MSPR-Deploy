# Chaine CI/CD et deploiement (MSPR3 / TPRE601)

Industrialisation de la plateforme HealthAI Coach. Chaque service possede sa propre
chaine d'integration continue (GitHub Actions) qui teste le code puis publie une image
Docker sur GitHub Container Registry (GHCR). Le deploiement se fait en local via
`bootstrap.sh`, qui orchestre l'ensemble avec Docker Compose.

## Vue d'ensemble du flux

```
commit/push (branche par defaut ou tag vX.Y.Z)
   |
   v
GitHub Actions (un workflow par depot)
   |-- lint (selon la techno)
   |-- tests + couverture
   |-- build de l'image Docker
   v
publication sur GHCR (ghcr.io/whitefoxxyt/mspr-<service>)
   |
   v
deploiement local : ./bootstrap.sh  ->  docker compose up -d
```

La publication de l'image n'a lieu que sur `push` (pas sur les pull requests) et seulement
si le lint et les tests passent. Les workflows `docker-publish` sont appeles via
`workflow_call` depuis le workflow de CI principal.

## Chaine par service

| Service | Depot (whitefoxxyt) | Declencheurs | Lint | Tests | Image GHCR |
|---------|---------------------|--------------|------|-------|------------|
| API | MSPR-HealthAI-Coach-API | push/PR `main`, tags `v*.*.*` | non | JUnit + JaCoCo (seuil 80 %) | `mspr-api` |
| Auth | MSPR-HealthAI-Coach-AUTH | push/PR `main`, tags `v*.*.*` | non | `bun test` | `mspr-auth` |
| AI-Nutrition | MSPR-HealthAI-Coach-AI-Nutrition | push/PR `master`, tags `v*.*.*` | ruff | pytest + couverture | `mspr-ai-nutrition` |
| Reco-Fitness | MSPR-HealthAI-Coach-Reco-Fitness- | push/PR `master`/`main`, tags `v*.*.*` | ruff | pytest-cov (seuil 80 %) avec services PostgreSQL + MongoDB | `mspr-reco-fitness` |
| ETL | MSPR-HealthAI-Coach-ETL | push/PR `master`/`main`, tags `v*.*.*` | ruff + format | pytest unitaires + integration (PostgreSQL) | `mspr-etl` |
| Front | MSPR-HealthAI-Coach-Dahsboard | push/PR `main`, tags `v*.*.*` | oxlint + eslint + vue-tsc | Vitest + Cypress (e2e) | `mspr-front` |
| BDD | MSPR-HealthAI-Coach-BDD | push/PR `main`, tags `v*.*.*` | non | validation des migrations SQL (PostgreSQL) | `mspr-db` |
| MongoDB | MSPR-HealthAI-Coach-MongoDB | push/PR `master`/`main`, tags `v*.*.*` | `node --check` | validation des collections et index (MongoDB) | `mspr-mongodb` |

## Strategie d'images et de tags

Les workflows `docker-publish` utilisent `docker/metadata-action` et produisent plusieurs
tags par image :

- `type=ref,event=branch` : tag au nom de la branche.
- `type=semver,pattern={{version}}` et `{{major}}.{{minor}}` : sur les tags Git `vX.Y.Z`.
- `type=sha` : SHA court du commit, pour la tracabilite.
- `type=raw,value=latest,enable={{is_default_branch}}` : `latest` uniquement depuis la
  branche par defaut du depot.

Le deploiement en mode prod (`bootstrap.sh` sans option) tire les images `:latest`, donc
celles publiees depuis la branche par defaut de chaque depot.

## Qualite de code

- **Tests automatises** sur chaque service (JUnit, bun test, pytest, Vitest/Cypress,
  validations SQL et MongoDB). Seuil de couverture a 80 % impose cote API (JaCoCo) et
  Reco-Fitness (pytest-cov).
- **Linting** selon la techno : ruff (Python), oxlint + eslint + vue-tsc (Front),
  `node --check` (MongoDB).
- **SonarQube** : le service API embarque le plugin Sonar (`pom.xml`, organisation
  `healthai-coach`, projet `healthai-coach-api`) et un environnement d'analyse local
  (`docker-compose.sonar.yml` dans le depot API) pour une analyse manuelle
  (`mvn sonar:sonar`). La CI de l'API contient en plus une etape SonarCloud qui se declenche
  automatiquement des qu'un secret GitHub `SONAR_TOKEN` est configure (sinon elle est
  ignoree, sans casser le pipeline). Pour l'activer : creer le projet sur SonarCloud sous
  l'organisation `healthai-coach`, puis ajouter le token en secret `SONAR_TOKEN` du depot.

## Deploiement

Le deploiement de la plateforme est decrit en detail dans `README.md`. En resume :

- **Mode prod** : `./bootstrap.sh` tire les images GHCR `:latest` et lance
  `docker compose up -d`. C'est l'etape de mise en production locale (cible d'evaluation et
  de demo).
- **Mode dev** : `./bootstrap.sh --dev` clone les 8 depots sources et build les images
  localement (`docker-compose.dev.yml`).

`bootstrap.sh` prepare aussi l'environnement : creation du `.env`, generation des secrets
(`BETTER_AUTH_SECRET`, mots de passe des bases), dechiffrement des cles API.

Trois configurations sont disponibles via des overlays Compose (voir `CONFIGS.md`) :
complete (avec monitoring), offline (sans internet) et performance (limites de ressources).

## Sauvegarde, restauration, supervision

- Sauvegarde et restauration des bases : `scripts/backup.sh`, `scripts/restore.sh` (voir
  `README.md`).
- Observabilite : overlay `docker-compose.monitoring.yml` (Prometheus, Grafana, Loki,
  Alertmanager + exporters). Voir `monitoring/README.md`.
