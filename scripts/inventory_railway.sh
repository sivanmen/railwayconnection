#!/usr/bin/env bash
# Fetch detailed inventory of all 21 Railway projects + their services + public URLs
# Outputs services_inventory.json (full version)
set -euo pipefail

source "$(dirname "$0")/../.secrets.local.env"

GQL_URL="https://backboard.railway.app/graphql/v2"

call_gql() {
  local query="$1"
  curl -sS -X POST "$GQL_URL" \
    -H "Authorization: Bearer ${RAILWAY_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"query\":$(jq -Rs . <<<"$query")}"
}

# 1. Get all projects with their services + deployments
QUERY='query {
  projects {
    edges {
      node {
        id
        name
        services {
          edges {
            node {
              id
              name
              deployments(first: 1) {
                edges {
                  node {
                    id
                    status
                    staticUrl
                  }
                }
              }
              serviceInstances {
                edges {
                  node {
                    domains {
                      serviceDomains {
                        domain
                      }
                      customDomains {
                        domain
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}'

call_gql "$QUERY" > /tmp/railway_full_dump.json
jq '.' /tmp/railway_full_dump.json > "$(dirname "$0")/../services_inventory_full.json"
echo "✅ wrote services_inventory_full.json"

# 2. Flat summary
jq '[.data.projects.edges[].node | {project_id: .id, project_name: .name, services: [.services.edges[].node | {service_id: .id, service_name: .name, last_status: (.deployments.edges[0].node.status // "none"), static_url: (.deployments.edges[0].node.staticUrl // null), domains: ((.serviceInstances.edges | map(.node.domains.serviceDomains // [] | map(.domain)) | flatten) + (.serviceInstances.edges | map(.node.domains.customDomains // [] | map(.domain)) | flatten))}]}]' /tmp/railway_full_dump.json > "$(dirname "$0")/../services_inventory.json"

echo "✅ wrote services_inventory.json (flat)"
jq 'length as $n | "Projects: \($n), Total services: \([.[].services | length] | add)"' "$(dirname "$0")/../services_inventory.json"
