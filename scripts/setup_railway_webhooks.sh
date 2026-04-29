#!/usr/bin/env bash
# Create a Railway notification rule (webhook -> n8n mesh-onboarding endpoint)
# for every project listed in services_inventory.json. Idempotent: skips
# projects that already have a matching rule.
#
# Requires: jq, curl, and .secrets.local.env with RAILWAY_TOKEN.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_FILE="${ROOT_DIR}/.secrets.local.env"
INVENTORY_FILE="${ROOT_DIR}/services_inventory.json"

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "ERROR: $SECRETS_FILE not found" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$SECRETS_FILE"; set +a

: "${RAILWAY_TOKEN:?RAILWAY_TOKEN missing}"

WEBHOOK_URL="https://n8n-production-986a.up.railway.app/webhook/railway-event"
EVENT_TYPE="DEPLOY_SUCCESS"
GQL="https://backboard.railway.app/graphql/v2"

gql() {
  local query="$1"
  curl -sS -X POST "$GQL" \
    -H "Authorization: Bearer $RAILWAY_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$(jq -nc --arg q "$query" '{query:$q}')"
}

# Discover workspace from the first project (account-token has access to one
# workspace).
FIRST_PROJECT="$(jq -r '.[0].project_id' "$INVENTORY_FILE")"
WORKSPACE_ID="$(gql "{ project(id: \"$FIRST_PROJECT\") { workspaceId } }" \
  | jq -r '.data.project.workspaceId')"
if [[ -z "$WORKSPACE_ID" || "$WORKSPACE_ID" == "null" ]]; then
  echo "ERROR: could not resolve workspaceId" >&2
  exit 1
fi
echo "Workspace: $WORKSPACE_ID"
echo "Webhook target: $WEBHOOK_URL"
echo "Event type: $EVENT_TYPE"
echo

# Pull existing rules once and index by projectId for the idempotency check.
EXISTING="$(gql "{ notificationRules(workspaceId: \"$WORKSPACE_ID\") { id projectId eventTypes channels { config } } }")"

created=0; existed=0; failed=0

while IFS=$'\t' read -r pid pname; do
  match="$(echo "$EXISTING" | jq -r --arg pid "$pid" --arg url "$WEBHOOK_URL" --arg ev "$EVENT_TYPE" '
    .data.notificationRules[]?
    | select(.projectId == $pid)
    | select(.eventTypes | index($ev))
    | select([.channels[].config.url] | index($url))
    | .id
  ' | head -n 1)"

  if [[ -n "$match" ]]; then
    printf "[exists]  %s  (%s) -> rule %s\n" "$pid" "$pname" "$match"
    existed=$((existed+1))
    continue
  fi

  resp="$(gql "mutation { notificationRuleCreate(input: {workspaceId: \"$WORKSPACE_ID\", projectId: \"$pid\", eventTypes: [\"$EVENT_TYPE\"], channelConfigs: [{type: \"WEBHOOK\", url: \"$WEBHOOK_URL\"}]}) { id } }")"
  rid="$(echo "$resp" | jq -r '.data.notificationRuleCreate.id // empty')"
  if [[ -n "$rid" ]]; then
    printf "[created] %s  (%s) -> rule %s\n" "$pid" "$pname" "$rid"
    created=$((created+1))
  else
    err="$(echo "$resp" | jq -c '.errors // .')"
    printf "[FAIL]    %s  (%s) :: %s\n" "$pid" "$pname" "$err"
    failed=$((failed+1))
  fi

  sleep 0.25
done < <(jq -r '.[] | "\(.project_id)\t\(.project_name)"' "$INVENTORY_FILE")

echo
echo "Summary: created=$created  already-existed=$existed  failed=$failed"
