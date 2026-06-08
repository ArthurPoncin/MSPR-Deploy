# Monitoring / observabilite

Stack d'observabilite de la plateforme MSPR HealthAI Coach (MSPR3 / TPRE601).
Elle est fournie sous forme d'overlay Docker Compose (`docker-compose.monitoring.yml`)
qui s'ajoute a la stack applicative sans la modifier.

## Lancement

```bash
# Mode prod (images GHCR)
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Mode dev (build local)
docker compose -f docker-compose.dev.yml -f docker-compose.monitoring.yml up -d
```

Arret de l'observabilite seule (sans toucher l'application) :

```bash
docker compose -f docker-compose.monitoring.yml down
```

## Acces

| Outil | URL | Role | Identifiants |
|-------|-----|------|--------------|
| Grafana | http://localhost:3001 | Tableaux de bord (metriques + logs) | admin / admin (par defaut) |
| Prometheus | http://localhost:9090 | Collecte de metriques + regles d'alerte | - |
| Alertmanager | http://localhost:9093 | Alertes declenchees | - |
| Loki | http://localhost:3100 | Logs centralises (interroges via Grafana) | - |

Le mot de passe Grafana se surcharge via `GRAFANA_ADMIN_PASSWORD` dans `.env`.

## Composants

| Service | Image | Role |
|---------|-------|------|
| `prometheus` | prom/prometheus | Collecte et stocke les metriques (retention 7 jours), evalue les regles d'alerte |
| `alertmanager` | prom/alertmanager | Recoit et regroupe les alertes de Prometheus |
| `grafana` | grafana/grafana | Tableaux de bord, datasources Prometheus + Loki provisionnees |
| `loki` | grafana/loki | Stockage des logs (filesystem, retention 7 jours) |
| `promtail` | grafana/promtail | Collecte les logs de tous les conteneurs via le socket Docker |
| `cadvisor` | cadvisor | Metriques par conteneur (CPU, RAM, reseau, IO) |
| `node-exporter` | prom/node-exporter | Metriques de l'hote (CPU, RAM, disque, charge) |
| `postgres-exporter` | postgres-exporter | Metriques PostgreSQL metier (base `healthai`) |
| `postgres-exporter-auth` | postgres-exporter | Metriques PostgreSQL auth (base `auth_db`) |
| `mongodb-exporter` | percona/mongodb_exporter | Metriques MongoDB (base `reco_fitness`) |

## Donnees collectees (liste exhaustive)

> Livrable MSPR3 : documentation du systeme de supervision incluant la liste
> exhaustive des donnees collectees.

### Metriques d'infrastructure (actives des le lancement)

| Source | Exemples de donnees | Niveau |
|--------|---------------------|--------|
| cAdvisor | `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_network_receive_bytes_total`, `container_fs_usage_bytes` | par conteneur |
| node-exporter | `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes`, `node_load1` | hote |
| postgres-exporter (x2) | `pg_up`, `pg_stat_database_*` (connexions, commits, rollbacks), `pg_database_size_bytes` | bases metier + auth |
| mongodb-exporter | `mongodb_up`, `mongodb_connections`, `mongodb_op_counters_total`, taille des collections | MongoDB |
| Prometheus | `up` (etat de chaque cible scrappee) | toutes cibles |

### Logs (actifs des le lancement)

Promtail collecte la sortie standard et d'erreur de **tous les conteneurs** et les
pousse vers Loki, etiquetes par `container`, `stream` (stdout/stderr) et `service`.
Interrogeables dans Grafana (Explore ou panneau "Logs recents").

### Metriques applicatives (instrumentees, sprint A2)

| Service | Endpoint | Donnees |
|---------|----------|---------|
| API Spring Boot | `/api/actuator/prometheus` | `http_server_requests_seconds` (latence, debit, codes HTTP), JVM (heap, GC, threads), pool de connexions |
| AI-Nutrition (FastAPI) | `/metrics` | requetes HTTP par route, latence, erreurs (RED) |
| Reco-Fitness (FastAPI) | `/metrics` | requetes HTTP par route, latence, erreurs (RED) |
| AUTH (Hono/Bun) | `/metrics` | requetes HTTP, latence, compteurs (RED) |

Les 4 cibles sont actives dans `prometheus/prometheus.yml`. L'endpoint Prometheus de l'API est ouvert sans JWT dans la config de securite (scraping interne) ; les endpoints `/metrics` des FastAPI et d'Auth sont publics sur le reseau Docker, acceptable en environnement de demonstration.

> Important : ces metriques applicatives ne sont visibles qu'apres reconstruction des images des services (l'instrumentation vit dans le code source des repos). En mode dev : `docker compose -f docker-compose.dev.yml -f docker-compose.monitoring.yml up -d --build`. En mode prod : apres publication des nouvelles images GHCR par la CI.

## Alertes basiques

Definies dans `prometheus/alerts.yml` :

| Alerte | Condition | Severite |
|--------|-----------|----------|
| `CibleInjoignable` | `up == 0` pendant 1 min | critical |
| `ConteneurCpuEleve` | > 0.9 coeur CPU pendant 5 min | warning |
| `ConteneurMemoireElevee` | > 2 Go de RAM pendant 5 min | warning |

## Tableau de bord

Le dashboard "MSPR HealthAI - Vue stack" est provisionne automatiquement dans Grafana
(dossier "MSPR HealthAI") : cibles UP, disponibilite par job, CPU et memoire par
conteneur, et flux de logs. Des dashboards par service seront ajoutes au sprint A3.
