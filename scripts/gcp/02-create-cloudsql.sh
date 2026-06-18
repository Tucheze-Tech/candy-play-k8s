#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="candy-play"
REGION="europe-west3"
INSTANCE_NAME="candyplay-prod-pg"


echo "==> Setting gcloud project to: $PROJECT_ID"
gcloud config set project candy-play

# Private-IP Cloud SQL (--no-assign-ip / --enable-google-private-path) requires
# Private Service Access: an allocated range on the VPC + a servicenetworking
# VPC peering. Without it, instance create fails with an opaque [INTERNAL].
PSA_RANGE="google-managed-services-default"
echo "==> Ensuring Private Service Access on network 'default'..."
gcloud services enable servicenetworking.googleapis.com --project="$PROJECT_ID"
if ! gcloud compute addresses describe "$PSA_RANGE" \
       --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute addresses create "$PSA_RANGE" \
    --global --purpose=VPC_PEERING --prefix-length=16 \
    --network=default --project="$PROJECT_ID"
fi
if ! gcloud services vpc-peerings list --network=default --project="$PROJECT_ID" \
       --format="value(reservedPeeringRanges)" 2>/dev/null | grep -q "$PSA_RANGE"; then
  gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges="$PSA_RANGE" \
    --network=default --project="$PROJECT_ID"
fi

if gcloud sql instances describe "$INSTANCE_NAME" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "==> Cloud SQL instance $INSTANCE_NAME already exists — skipping create."
else
  echo "==> Creating Cloud SQL Postgres 15 instance: $INSTANCE_NAME..."
  gcloud sql instances create "$INSTANCE_NAME" \
    --project="$PROJECT_ID" \
    --database-version=POSTGRES_15 \
    --region="$REGION" \
    --tier=db-custom-1-3840 \
    --storage-type=SSD \
    --storage-size=10GB \
    --storage-auto-increase \
    --no-assign-ip \
    --network=projects/${PROJECT_ID}/global/networks/default \
    --enable-google-private-path \
    --deletion-protection \
    --backup-start-time=02:00 \
    --retained-backups-count=7 \
    --enable-point-in-time-recovery \
    --retained-transaction-log-days=3
fi

echo "==> Creating databases..."
for db in icore_prod ev_prod tpay_prod 01tech_prod metabase_prod kong_prod grafana_prod; do
  if gcloud sql databases describe "$db" --instance="$INSTANCE_NAME" \
       --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  Database $db already exists — skipping."
  else
    gcloud sql databases create "$db" \
      --instance="$INSTANCE_NAME" \
      --project="$PROJECT_ID"
    echo "  Created database: $db"
  fi
done

echo "==> Creating per-service users and storing passwords in Secret Manager..."
EXISTING_USERS=$(gcloud sql users list --instance="$INSTANCE_NAME" \
  --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || true)
for svc in icore ev tpay 01tech metabase kong grafana; do
  # Skip if the user already exists — its password is only known to the secret
  # created on first run; regenerating here would desync DB user vs Secret.
  if echo "$EXISTING_USERS" | grep -qx "${svc}_user"; then
    echo "  User ${svc}_user already exists — skipping (secret preserved)."
    continue
  fi
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
