#!/usr/bin/env bash
# SKELETON — EKS equivalent of gcp/02-create-cloudsql.sh.
# AWS uses RDS Postgres reached DIRECTLY (no cloud-sql-proxy sidecar); the
# DATABASE_URL is delivered to each pod through its AWS Secrets Manager secret.
set -euo pipefail

echo "RDS creation is a skeleton — see k8s/docs/gke-to-eks.md." >&2
exit 1

# --- reference ---
# aws rds create-db-instance \
#   --db-instance-identifier candyplay-prod-pg \
#   --engine postgres --engine-version 16 \
#   --db-instance-class db.t4g.small \
#   --allocated-storage 20 --storage-type gp3 \
#   --no-publicly-accessible \
#   --backup-retention-period 7
#
# Create one DB per service: icore_prod, ev_prod, tpay_prod, 01tech_prod,
# metabase_prod, kong_prod. Put each service's DATABASE_URL into its AWS
# Secrets Manager secret (see 03-create-secrets.sh).
