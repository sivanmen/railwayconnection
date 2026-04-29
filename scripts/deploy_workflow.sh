#!/usr/bin/env bash
# Deploy a workflow JSON file to n8n. Usage: ./deploy_workflow.sh <file.json>
set -euo pipefail
source "$(dirname "$0")/../.secrets.local.env"

FILE="$1"
NAME=$(jq -r '.name' "$FILE")

# Find existing workflow with same name
EXISTING_ID=$(curl -sS "$N8N_BASE_URL/api/v1/workflows?limit=250" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq -r --arg n "$NAME" '.data[] | select(.name == $n) | .id' | head -1)

# n8n public API rejects extra fields like 'active'/'tags'/'staticData' on POST
PAYLOAD=$(jq '{name, nodes, connections, settings}' "$FILE")

if [[ -n "$EXISTING_ID" ]]; then
  echo "→ Updating existing workflow $NAME (id=$EXISTING_ID)"
  RESPONSE=$(curl -sS -X PUT "$N8N_BASE_URL/api/v1/workflows/$EXISTING_ID" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  WF_ID="$EXISTING_ID"
else
  echo "→ Creating new workflow $NAME"
  RESPONSE=$(curl -sS -X POST "$N8N_BASE_URL/api/v1/workflows" \
    -H "X-N8N-API-KEY: $N8N_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  WF_ID=$(echo "$RESPONSE" | jq -r '.id')
fi

if [[ -z "$WF_ID" || "$WF_ID" == "null" ]]; then
  echo "❌ Failed to create/update workflow:"
  echo "$RESPONSE" | jq .
  exit 1
fi

# Activate
ACTIVATE=$(curl -sS -X POST "$N8N_BASE_URL/api/v1/workflows/$WF_ID/activate" \
  -H "X-N8N-API-KEY: $N8N_API_KEY")
ACTIVE=$(echo "$ACTIVATE" | jq -r '.active // false')

echo "✅ $NAME → id=$WF_ID active=$ACTIVE"
