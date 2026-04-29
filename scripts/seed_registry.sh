#!/usr/bin/env bash
# Seed n8n services_registry with all known callable services from 21 Railway projects.
# Skips infra (Postgres/Redis/Worker/Sandbox/etc).
set -euo pipefail
source "$(dirname "$0")/../.secrets.local.env"

REGISTER_URL="$N8N_BASE_URL/webhook/mesh-register"

register() {
  local body="$1"
  local name=$(echo "$body" | jq -r '.name')
  local response=$(curl -sS -X POST "$REGISTER_URL" -H "Content-Type: application/json" -d "$body")
  echo "→ $name: $response"
}

# === MANAGED services (Sivan controls the code — placeholder /health, will add /manifest later) ===

register '{
  "name":"paperclip","display_name":"Paperclip - AI Team","category":"task",
  "public_url":"https://paperclip-production-89c6.up.railway.app","version":"1.0.0",
  "capabilities":["create_task","list_agents","task_status"],
  "endpoints":{
    "create_task":{"method":"POST","path":"/api/issues","body_schema":{"title":"string","body":"string","assignee":"string"}},
    "list_agents":{"method":"GET","path":"/api/agents"},
    "task_status":{"method":"GET","path":"/api/issues/{task_id}"}
  },
  "auth_type":"bearer","project_id":"0ee2c5dd-4a04-4748-9d93-92c8dfc5a14a","project_name":"Paperclip- Ai Team"
}'

register '{
  "name":"openjarvis","display_name":"OpenJarvis (Telegram bot)","category":"comms",
  "public_url":"https://openjarvis-production-6a47.up.railway.app","version":"1.0.0",
  "capabilities":["send_telegram","receive_command"],
  "endpoints":{
    "send_telegram":{"method":"POST","path":"/api/send","body_schema":{"chat_id":"string","text":"string"}},
    "receive_command":{"method":"POST","path":"/webhook/telegram"}
  },
  "auth_type":"bearer","project_id":"c39caef7-d19f-4998-8b55-867e7bc091cc","project_name":"OpenJarvis"
}'

register '{
  "name":"ruflo","display_name":"Ruflo MCP","category":"ai",
  "public_url":"https://ruflo-production-0594.up.railway.app","version":"3.5.0",
  "capabilities":["mcp_call","agent_spawn"],
  "endpoints":{
    "mcp_call":{"method":"POST","path":"/mcp"},
    "agent_spawn":{"method":"POST","path":"/api/spawn"}
  },
  "auth_type":"none","project_id":"c4389b55-1d35-4947-9d23-d5f6077f213f","project_name":"Ruflo"
}'

register '{
  "name":"langgraph","display_name":"LangGraph SYSTEM","category":"ai",
  "public_url":"https://langgraph-production-3382.up.railway.app","version":"1.0.0",
  "capabilities":["run_graph","list_graphs"],
  "endpoints":{
    "run_graph":{"method":"POST","path":"/api/run","body_schema":{"graph":"string","input":"object"}},
    "list_graphs":{"method":"GET","path":"/api/graphs"}
  },
  "auth_type":"none","project_id":"a6b9316d-0043-4c8a-923b-5edd23c380b9","project_name":"LangGraph SYSTEM"
}'

register '{
  "name":"openclaw","display_name":"OpenClaw","category":"ai",
  "public_url":"https://openclaw-production-a349.up.railway.app","version":"1.0.0",
  "capabilities":["search","scrape"],
  "endpoints":{
    "search":{"method":"GET","path":"/api/search"},
    "scrape":{"method":"POST","path":"/api/scrape","body_schema":{"url":"string"}}
  },
  "auth_type":"none","project_id":"8fd4c402-987d-4f7d-84b2-cbe81a8e21e0","project_name":"OpenClaw"
}'

register '{
  "name":"searxng","display_name":"SearXNG (OpenClaw)","category":"data",
  "public_url":"https://searxng-railway-production-d16d.up.railway.app","version":"1.0.0",
  "capabilities":["search"],
  "endpoints":{"search":{"method":"GET","path":"/search"}},
  "auth_type":"none","project_id":"8fd4c402-987d-4f7d-84b2-cbe81a8e21e0","project_name":"OpenClaw"
}'

register '{
  "name":"payload-cms","display_name":"Payload CMS","category":"data",
  "public_url":"https://payload-cms-production-9eab.up.railway.app","version":"3.0.0",
  "capabilities":["read_content","write_content"],
  "endpoints":{
    "read_content":{"method":"GET","path":"/api/{collection}"},
    "write_content":{"method":"POST","path":"/api/{collection}"}
  },
  "auth_type":"bearer","project_id":"27d7e97e-61bd-4a62-91f4-e2a04a18282a","project_name":"Payload"
}'

register '{
  "name":"harmony-bonds-api","display_name":"Harmony Bonds API","category":"task",
  "public_url":"https://harmony-bonds-api-production.up.railway.app","version":"1.0.0",
  "capabilities":["list_bonds","create_investment"],
  "endpoints":{
    "list_bonds":{"method":"GET","path":"/api/bonds"},
    "create_investment":{"method":"POST","path":"/api/investments"}
  },
  "auth_type":"bearer","project_id":"81387d39-1ba4-45cc-b1fb-1294f9466388","project_name":"Harmony - investments system"
}'

register '{
  "name":"harmony-bonds-client","display_name":"Harmony Bonds Web","category":"data",
  "public_url":"https://client.harmony-bonds.com","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"81387d39-1ba4-45cc-b1fb-1294f9466388","project_name":"Harmony - investments system"
}'

register '{
  "name":"contentos-api","display_name":"ContentOS API","category":"task",
  "public_url":"https://contentos-api-production.up.railway.app","version":"1.0.0",
  "capabilities":["list_posts","create_post"],
  "endpoints":{
    "list_posts":{"method":"GET","path":"/api/posts"},
    "create_post":{"method":"POST","path":"/api/posts"}
  },
  "auth_type":"bearer","project_id":"9838659c-d22e-47fa-8ea2-8ffa1f7ec2af","project_name":"Social Media SYSTEM 2"
}'

register '{
  "name":"contentos-web","display_name":"ContentOS Web","category":"data",
  "public_url":"https://social.sivanmanagment.com","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"9838659c-d22e-47fa-8ea2-8ffa1f7ec2af","project_name":"Social Media SYSTEM 2"
}'

register '{
  "name":"blue-harbor-admin","display_name":"Blue Harbor Admin","category":"data",
  "public_url":"https://admin.blueharbor.agency","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"20af3da4-088b-4a71-9919-b5fba641a708","project_name":"Scared Investor Club"
}'

register '{
  "name":"blue-harbor-client","display_name":"Blue Harbor Client","category":"data",
  "public_url":"https://client.blueharbor.agency","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"20af3da4-088b-4a71-9919-b5fba641a708","project_name":"Scared Investor Club"
}'

register '{
  "name":"blue-harbor-web","display_name":"Blue Harbor Public Site","category":"data",
  "public_url":"https://www.blueharbor.agency","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"20af3da4-088b-4a71-9919-b5fba641a708","project_name":"Scared Investor Club"
}'

register '{
  "name":"property-mgmt-admin","display_name":"Property Mgmt Admin","category":"data",
  "public_url":"https://admin.sivanmanagment.com","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"fb7a2a6b-0e86-47ce-a091-454fbd45309e","project_name":"Property Managment System"
}'

register '{
  "name":"property-mgmt-client","display_name":"Property Mgmt Client","category":"data",
  "public_url":"https://client.sivanmanagment.com","version":"1.0.0",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"fb7a2a6b-0e86-47ce-a091-454fbd45309e","project_name":"Property Managment System"
}'

# === 3rd-PARTY services (off-the-shelf, register manually with their API surfaces) ===

register '{
  "name":"dify","display_name":"Dify (LLM platform)","category":"ai",
  "public_url":"https://dify.sivanmanagment.com","version":"latest",
  "capabilities":["chat_completion","run_workflow"],
  "endpoints":{
    "chat_completion":{"method":"POST","path":"/v1/chat-messages","body_schema":{"query":"string","user":"string"}},
    "run_workflow":{"method":"POST","path":"/v1/workflows/run","body_schema":{"inputs":"object","user":"string"}}
  },
  "auth_type":"bearer","project_id":"09b95815-fd16-40e7-84cd-26689fa04be9","project_name":"Dify"
}'

register '{
  "name":"dify-api","display_name":"Dify API","category":"ai",
  "public_url":"https://difyapi.sivanmanagment.com","version":"latest",
  "capabilities":["chat_completion"],
  "endpoints":{"chat_completion":{"method":"POST","path":"/v1/chat-messages"}},
  "auth_type":"bearer","project_id":"09b95815-fd16-40e7-84cd-26689fa04be9","project_name":"Dify"
}'

register '{
  "name":"chatwoot","display_name":"Chatwoot","category":"comms",
  "public_url":"https://chatwoot-production-934d.up.railway.app","version":"latest",
  "capabilities":["send_message","list_conversations"],
  "endpoints":{
    "send_message":{"method":"POST","path":"/api/v1/accounts/{account_id}/conversations/{conv_id}/messages"},
    "list_conversations":{"method":"GET","path":"/api/v1/accounts/{account_id}/conversations"}
  },
  "auth_type":"api_key","project_id":"7b7c80aa-2a38-4837-ae69-2fe776a48376","project_name":"Chatwoot"
}'

register '{
  "name":"typebot-builder","display_name":"Typebot Builder","category":"comms",
  "public_url":"https://builder-production-30fda.up.railway.app","version":"latest",
  "capabilities":["create_typebot"],
  "endpoints":{"create_typebot":{"method":"POST","path":"/api/v1/typebots"}},
  "auth_type":"bearer","project_id":"5e29e00c-6322-4b84-9f98-b766a3f43141","project_name":"Typebot"
}'

register '{
  "name":"typebot-viewer","display_name":"Typebot Viewer","category":"comms",
  "public_url":"https://viewer-production-42c0.up.railway.app","version":"latest",
  "capabilities":["start_chat","send_input"],
  "endpoints":{
    "start_chat":{"method":"POST","path":"/api/v1/sessions"},
    "send_input":{"method":"POST","path":"/api/v1/sessions/{session_id}/messages"}
  },
  "auth_type":"none","project_id":"5e29e00c-6322-4b84-9f98-b766a3f43141","project_name":"Typebot"
}'

register '{
  "name":"typebot-console","display_name":"Typebot Console (admin)","category":"data",
  "public_url":"https://console-production-cecd.up.railway.app","version":"latest",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"5e29e00c-6322-4b84-9f98-b766a3f43141","project_name":"Typebot"
}'

register '{
  "name":"postiz-1","display_name":"Postiz (instance 1)","category":"comms",
  "public_url":"https://gitroomhqpostiz-applatest-production-c905.up.railway.app","version":"latest",
  "capabilities":["schedule_post"],
  "endpoints":{"schedule_post":{"method":"POST","path":"/api/posts"}},
  "auth_type":"bearer","project_id":"2fabb175-54ae-4cdd-b957-88038ee8aac5","project_name":"Postiz social media managment"
}'

register '{
  "name":"postiz-2","display_name":"Postiz (instance 2)","category":"comms",
  "public_url":"https://gitroomhqpostiz-applatest-production-db94.up.railway.app","version":"latest",
  "capabilities":["schedule_post"],
  "endpoints":{"schedule_post":{"method":"POST","path":"/api/posts"}},
  "auth_type":"bearer","project_id":"8000527b-bbf2-4a12-94cb-9d4bb0be713a","project_name":"Postiz 2"
}'

register '{
  "name":"buddyboss","display_name":"BuddyBoss WordPress","category":"comms",
  "public_url":"https://docker-image-production-85b2.up.railway.app","version":"latest",
  "capabilities":["serve_ui"],
  "endpoints":{"serve_ui":{"method":"GET","path":"/"}},
  "auth_type":"none","project_id":"f4536e6f-dbb9-4082-9f0a-ce56217a121d","project_name":"buddyboss"
}'

# === Evolution API instances ===

register '{
  "name":"evolution-harmony","display_name":"Evolution API (Harmony WhatsApp)","category":"comms",
  "public_url":"https://evolution-api-production-aad5.up.railway.app","version":"latest",
  "capabilities":["send_text","send_media","fetch_instances"],
  "endpoints":{
    "send_text":{"method":"POST","path":"/message/sendText/{instance}","body_schema":{"number":"string","text":"string"}},
    "send_media":{"method":"POST","path":"/message/sendMedia/{instance}"},
    "fetch_instances":{"method":"GET","path":"/instance/fetchInstances"}
  },
  "auth_type":"api_key","project_id":"36982cb7-3842-4d9a-a8df-a2303e5a13ee","project_name":"Evolution API - Harmony SYSTEM"
}'

register '{
  "name":"evolution-sivan-m","display_name":"Evolution API (Sivan M)","category":"comms",
  "public_url":"https://evolution-api-production-eaab.up.railway.app","version":"latest",
  "capabilities":["send_text","send_media"],
  "endpoints":{"send_text":{"method":"POST","path":"/message/sendText/{instance}"}},
  "auth_type":"api_key","project_id":"9f0ac8b2-e062-4be4-b000-377279792d14","project_name":"Evolution API - Sivan M SYSTEM"
}'

register '{
  "name":"evolution-social-m","display_name":"Evolution API (Social M)","category":"comms",
  "public_url":"https://evolution-api-production-ef85.up.railway.app","version":"latest",
  "capabilities":["send_text","send_media"],
  "endpoints":{"send_text":{"method":"POST","path":"/message/sendText/{instance}"}},
  "auth_type":"api_key","project_id":"08ae6d8b-972a-4deb-be32-36a670938a84","project_name":"Evolution API - Social M SYSTEM"
}'

# === N8n+MCP itself (the hub) ===

register '{
  "name":"n8n","display_name":"n8n (hub)","category":"orchestration",
  "public_url":"https://n8n-production-986a.up.railway.app","version":"1.0.0",
  "capabilities":["run_webhook","trigger_workflow","query_workflows"],
  "endpoints":{
    "run_webhook":{"method":"POST","path":"/webhook/{path}"},
    "trigger_workflow":{"method":"POST","path":"/api/v1/workflows/{id}/execute"},
    "query_workflows":{"method":"GET","path":"/api/v1/workflows"}
  },
  "auth_type":"api_key","project_id":"5873bd15-0f38-4e5a-a0f2-db233e63e625","project_name":"N8n+MCP"
}'

register '{
  "name":"n8n-webhook","display_name":"n8n webhook node","category":"orchestration",
  "public_url":"https://webhook-n8nmcp.up.railway.app","version":"1.0.0",
  "capabilities":["receive_webhook"],
  "endpoints":{"receive_webhook":{"method":"POST","path":"/webhook/{path}"}},
  "auth_type":"none","project_id":"5873bd15-0f38-4e5a-a0f2-db233e63e625","project_name":"N8n+MCP"
}'

register '{
  "name":"n8n-mcp","display_name":"n8n MCP server","category":"orchestration",
  "public_url":"https://mcp-n8nmcp.up.railway.app","version":"1.0.0",
  "capabilities":["mcp_query"],
  "endpoints":{"mcp_query":{"method":"POST","path":"/mcp"}},
  "auth_type":"api_key","project_id":"5873bd15-0f38-4e5a-a0f2-db233e63e625","project_name":"N8n+MCP"
}'

echo ""
echo "=== Final state ==="
N8N_KEY="$N8N_API_KEY"
curl -s "$N8N_BASE_URL/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows?limit=250" -H "X-N8N-API-KEY: $N8N_KEY" | jq '.data | length as $n | "Total registered: \($n)"'
