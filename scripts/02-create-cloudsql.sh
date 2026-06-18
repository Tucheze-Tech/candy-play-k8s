#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="cm-services-prod"
REGION="europe-west3"
INSTANCE_NAME="candyplay-prod-pg"

echo "==> Creating Cloud SQL Postgres 15 instance: $INSTANCE_NAME..."
gcloud sql instances create "$INSTANCE_NAME" \
  --project="$PROJECT_ID" \
  --database-version=POSTGRES_15 \
  --region="$REGION" \
  --tier=db-custom-1-3840 \
  --storage-type=SSD \
  --storage-size=20GB \
  --storage-auto-increase \
  --no-assign-ip \
  --network=projects/${PROJECT_ID}/global/networks/default \
  --enable-google-private-path \
  --deletion-protection \
  --backup-start-time=02:00 \
  --retained-backups-count=7 \
  --retained-transaction-log-days=3

echo "==> Creating databases..."
for db in icore_prod ev_prod tpay_prod 01tech_prod metabase_prod kong_prod; do
  gcloud sql databases create "$db" \
    --instance="$INSTANCE_NAME" \
    --project="$PROJECT_ID"
  echo "  Created database: $db"
done

echo "==> Creating per-service users and storing passwords in Secret Manager..."
for svc in icore ev tpay 01tech metabase kong; do
  PASSWORD=$(openssl rand -base64 24)
  gcloud sql users create "${svc}_user" \
    --instance="$INSTANCE_NAME" \
    --project="$PROJECT_ID" \
    --password="$PASSWORD"

  # Store DB credentials in Secret Manager
  DB_NAME="${svc}_prod"

  # Kong secret key is "password" (read directly by Kong Helm chart)
  if [ "$svc" = "kong" ]; then
    echo "{\"password\": \"${PASSWORD}\", \"user\": \"kong_user\"}" \
      | gcloud secrets create "kong_db_credentials" \
          --project="$PROJECT_ID" \
          --data-file=- \
          --replication-policy=automatic \
          2>/dev/null || \
    echo "{\"password\": \"${PASSWORD}\", \"user\": \"kong_user\"}" \
      | gcloud secrets versions add "kong_db_credentials" \
          --project="$PROJECT_ID" \
          --data-file=-
    echo "  User kong_user created, credentials in secret: kong_db_credentials"
    continue
  fi

  echo "{\"DB_USER\": \"${svc}_user\", \"DB_PASSWORD\": \"${PASSWORD}\", \"DB_NAME\": \"${DB_NAME}\", \"DB_HOST\": \"127.0.0.1\", \"DB_PORT\": \"5432\"}" \
    | gcloud secrets create "${svc}_db_credentials" \
        --project="$PROJECT_ID" \
        --data-file=- \
        --replication-policy=automatic \
        2>/dev/null || \
  echo "{\"DB_USER\": \"${svc}_user\", \"DB_PASSWORD\": \"${PASSWORD}\", \"DB_NAME\": \"${DB_NAME}\", \"DB_HOST\": \"127.0.0.1\", \"DB_PORT\": \"5432\"}" \
    | gcloud secrets versions add "${svc}_db_credentials" \
        --project="$PROJECT_ID" \
        --data-file=-

  echo "  User ${svc}_user created, credentials stored in secret: ${svc}_db_credentials"
done

echo "==> Cloud SQL instance ready. Connection name:"
gcloud sql instances describe "$INSTANCE_NAME" \
  --project="$PROJECT_ID" \
  --format="value(connectionName)"
