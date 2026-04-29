# ADD_NEW_SERVICE — איך מוסיפים שירות ל-Mesh

מסמך זה מתאר את שלוש הדרכים להוסיף שירות לרשת של Sivan, את הסכמה המלאה של ה-manifest, ופקודות לבדיקה אחרי deploy.

Hub: `https://n8n-production-986a.up.railway.app`
Register webhook: `POST /webhook/mesh-register`
Registry table: `gZRuzAmWa9sNwGc6`

---

## 1. שלוש הדרכים

### דרך A — שירות מאפס (מומלץ)

יש לנו 3 templates ב-`templates/` ברפו:

| Template | מתי | מה בפנים |
|----------|-----|---------|
| `mesh-template-node` | API service רגיל | Express + manifest + heartbeat |
| `mesh-template-python` | AI / ML service | FastAPI + manifest + heartbeat |
| `mesh-template-ai-agent` | סוכן AI שמשתמש בכלים אחרים ב-mesh | Anthropic SDK + auto-tool discovery |

#### צעדים

```bash
# 1. צור repo חדש מהtemplate
gh repo create sivan-mesh/my-new-service --template=sivan-mesh/mesh-template-node --private
cd my-new-service

# 2. עדכן את ה-manifest
$EDITOR src/manifest.js
# - שנה name, display_name, category
# - הוסף capabilities ו-endpoints

# 3. כתוב את הלוגיקה ב-src/routes/api.js

# 4. push ו-Railway deploy
git add . && git commit -m "init my-new-service"
git push

# חבר ל-Railway:
railway link
railway up

# 5. תוך 2 דק' תקבל WhatsApp ✅
```

המסה תזהה את השירות אוטומטית דרך `02_onboarding` (כשRailway webhooks יחוברו) או דרך הקריאה ש-template עושה ל-`registerSelf` בעלייה.

### דרך B — שירות קיים שלך

נניח שיש לך service שכבר רץ אבל לא חלק מה-mesh. שלוש תוספות נדרשות.

#### B.1 הוסף `/health` endpoint

```javascript
// Express
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    uptime_seconds: process.uptime(),
    timestamp: new Date().toISOString()
  });
});
```

```python
# FastAPI
@app.get('/health')
def health():
    return {
        'status': 'healthy',
        'uptime_seconds': time.time() - START_TIME,
        'timestamp': datetime.utcnow().isoformat()
    }
```

#### B.2 הוסף `/manifest` endpoint

```javascript
const MANIFEST = {
  name: 'my-existing-service',
  display_name: 'My Existing Service',
  version: '2.3.1',
  category: 'task',
  internal_url: `http://${process.env.RAILWAY_SERVICE_NAME}.railway.internal:${process.env.PORT}`,
  public_url: process.env.RAILWAY_PUBLIC_DOMAIN
    ? `https://${process.env.RAILWAY_PUBLIC_DOMAIN}` : null,
  health_endpoint: '/health',
  manifest_endpoint: '/manifest',
  auth_type: 'bearer',
  auth_secret_env_var: 'MY_SERVICE_API_KEY',
  capabilities: ['create_thing', 'list_things'],
  endpoints: {
    create_thing: {
      method: 'POST',
      path: '/api/things',
      body_schema: { name: 'string', value: 'number' },
      returns: { id: 'string' }
    },
    list_things: {
      method: 'GET',
      path: '/api/things',
      returns: 'array'
    }
  }
};

app.get('/manifest', (req, res) => res.json(MANIFEST));
```

#### B.3 רישום בעלייה + heartbeat

```javascript
const axios = require('axios');
const HUB = 'https://n8n-production-986a.up.railway.app';

async function joinMesh() {
  await axios.post(`${HUB}/webhook/mesh-register`, MANIFEST);
  setInterval(() => {
    axios.post(`${HUB}/webhook/mesh-register`, MANIFEST).catch(() => {});
  }, 60_000);
}

app.listen(PORT, () => {
  joinMesh().catch(console.error);
});
```

Push, deploy, תקבל WhatsApp ✅.

### דרך C — שירות צד שלישי

שירות SaaS חיצוני שאתה לא שולט בקוד שלו (Make, Zapier, וכו'). צריך לרשום ידנית.

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-register \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "make-com",
    "display_name": "Make.com Scenarios",
    "version": "1.0.0",
    "category": "orchestration",
    "internal_url": "https://hook.eu1.make.com/abc123xyz",
    "public_url": "https://hook.eu1.make.com/abc123xyz",
    "health_endpoint": "/",
    "manifest_endpoint": "/",
    "auth_type": "api_key",
    "auth_secret_env_var": "MAKE_WEBHOOK_TOKEN",
    "capabilities": ["trigger_scenario"],
    "endpoints": {
      "trigger_scenario": {
        "method": "POST",
        "path": "/",
        "body_schema": { "scenario_id": "string", "payload": "object" },
        "returns": { "execution_id": "string" }
      }
    },
    "metadata": {
      "external": true,
      "owner": "sivan",
      "notes": "Make.com webhook - no /health endpoint, watchdog uses HEAD /"
    }
  }'
```

חשוב: לשירותי 3rd-party סמן `metadata.external: true`. ה-watchdog יעשה HEAD במקום GET, ולא יעיר על תגובות שאינן 200 בלבד (גם 405 נחשב alive).

---

## 2. מפרט Manifest מלא

### 2.1 שדות חובה

| שדה | טיפוס | חוקיות | תיאור |
|-----|-------|--------|-------|
| `name` | string | `^[a-z0-9-]+$` | מזהה ייחודי במסה |
| `display_name` | string | 1-100 chars | שם קריא לבני אדם |
| `version` | string | semver `X.Y.Z` | גרסת השירות |
| `category` | enum | ראה למטה | קטגוריה |
| `internal_url` | string | URL | URL פנימי של Railway או חיצוני |
| `capabilities` | array<string> | לפחות 1 | רשימת יכולות שהשירות חושף |
| `endpoints` | object | מפתח לכל capability | מיפוי `cap → {method, path, body_schema, returns}` |

`category` חוקי: `orchestration`, `ai`, `task`, `comms`, `data`, `other`.

### 2.2 שדות אופציונליים

| שדה | ברירת מחדל | תיאור |
|-----|------------|-------|
| `public_url` | `null` | URL ציבורי אם יש |
| `health_endpoint` | `/health` | path לבדיקת בריאות |
| `manifest_endpoint` | `/manifest` | path להחזרת manifest |
| `auth_type` | `none` | `bearer` / `api_key` / `oauth` / `none` |
| `auth_secret_env_var` | `null` | שם env var (לא הסוד עצמו!) |
| `status` | `active` | `active` / `maintenance` / `deprecated` |
| `metadata` | `{}` | שדות חופשיים (owner, notes, external flag) |

### 2.3 סכמת `endpoints[capability]`

```json
{
  "method": "POST",
  "path": "/api/things",
  "body_schema": {
    "name": "string (required)",
    "value": "number",
    "tags": "array of string"
  },
  "returns": {
    "id": "string",
    "created_at": "ISO timestamp"
  },
  "auth_required": true,
  "rate_limit_per_minute": 60
}
```

`body_schema` ו-`returns` הם תיאורי טקסט, לא JSON Schema פורמלי. מספיק שיהיה ברור לקורא איזה שדות.

### 2.4 דוגמת manifest מלאה

```json
{
  "name": "paperclip",
  "display_name": "Paperclip Task System",
  "version": "1.4.2",
  "category": "task",
  "internal_url": "http://paperclip.railway.internal:8080",
  "public_url": "https://paperclip-prod.up.railway.app",
  "health_endpoint": "/health",
  "manifest_endpoint": "/manifest",
  "auth_type": "bearer",
  "auth_secret_env_var": "PAPERCLIP_API_KEY",
  "status": "active",
  "capabilities": ["create_task", "list_agents", "task_status", "assign_task"],
  "endpoints": {
    "create_task": {
      "method": "POST",
      "path": "/api/issues",
      "body_schema": {
        "title": "string (required)",
        "body": "string (required)",
        "assignee": "string",
        "department": "string",
        "priority": "low | normal | high | urgent"
      },
      "returns": { "task_id": "string", "status": "string" }
    },
    "list_agents": {
      "method": "GET",
      "path": "/api/agents",
      "returns": "array of agent objects"
    },
    "task_status": {
      "method": "GET",
      "path": "/api/issues/{task_id}",
      "returns": "task object"
    },
    "assign_task": {
      "method": "PATCH",
      "path": "/api/issues/{task_id}/assign",
      "body_schema": { "assignee": "string (required)" },
      "returns": { "ok": "boolean" }
    }
  },
  "metadata": {
    "owner": "sivan",
    "docs_url": "https://paperclip-prod.up.railway.app/docs"
  }
}
```

---

## 3. Quick Test — verify שהשירות הצטרף

### 3.1 ודא שהוא ב-registry

```bash
curl -X GET "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows?filter=name:my-new-service" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq
```

צפוי: row אחד עם `status: "active"` ו-`last_seen_at` מהדקה האחרונה.

### 3.2 בדוק שהוא מגיב

```bash
curl https://my-new-service-production.up.railway.app/health
# expect: {"status":"healthy",...}

curl https://my-new-service-production.up.railway.app/manifest | jq
# expect: full manifest JSON
```

### 3.3 קרא ל-capability דרך ה-router

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-route \
  -H 'Content-Type: application/json' \
  -d '{
    "from": "test-client",
    "to": "my-new-service",
    "capability": "create_thing",
    "params": { "name": "smoke test", "value": 42 }
  }'
```

צפוי: התשובה של השירות (`{ id: "..." }`).

### 3.4 ודא שה-watchdog מנטר אותו

חכה 5 דקות, אחר כך:

```bash
curl -X GET "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows?filter=name:my-new-service" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq '.[0] | {name, last_health_status, last_seen_at}'
```

צפוי: `last_health_status: "healthy"`, `last_seen_at` בתוך הדקות האחרונות.

### 3.5 בדיקת alerts (אופציונלי)

הפסק את השירות ב-Railway. תוך 5-10 דקות אמורה להגיע WhatsApp 🚨. החזר אותו, תוך 5 דק' אמורה להגיע ✅ recovery.

---

## 4. Troubleshooting — "deployed אבל אין WhatsApp"

עבור על השלבים בסדר:

### 4.1 השירות בכלל רץ?

```bash
railway status --service=my-new-service
curl -i https://my-new-service-production.up.railway.app/health
```

אם 5xx / timeout → בעיית deploy. בדוק `railway logs`.

### 4.2 הקריאה ל-`mesh-register` הצליחה?

חפש בלוגים של השירות שלך:

```bash
railway logs --service=my-new-service | grep -i mesh
```

אם אתה רואה `ECONNREFUSED` או `404` ב-`mesh-register` — בדוק שה-URL נכון. ה-webhook הוא:
```
https://n8n-production-986a.up.railway.app/webhook/mesh-register
```
שים לב — `webhook` (לא `webhook-test`) ל-production.

### 4.3 ה-manifest תקין?

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-register \
  -H 'Content-Type: application/json' \
  -d "$(curl -s https://my-new-service-production.up.railway.app/manifest)"
```

אם חוזר `{"error":"validation_failed", "errors":[...]}` — תקן את השדות ב-manifest שלך.

### 4.4 בדוק את `onboarding_history`

```bash
curl -X GET "https://n8n-production-986a.up.railway.app/api/v1/data-tables/DrZgGZwusgtdaw15/rows?filter=service_name:my-new-service&sort=attempted_at:desc&limit=5" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq
```

תראה את כל ניסיונות ה-onboarding עם ה-`outcome` ו-`errors`.

### 4.5 Evolution API חי?

אם הכל למעלה אבל WhatsApp לא מגיע — אולי Evolution נפל. בדוק:

```bash
curl -i https://evolution-api-production-ef85.up.railway.app/instance/connectionState/sivan-main \
  -H "apikey: $EVOLUTION_API_KEY"
```

אם 5xx — restart Evolution. בינתיים תקבל רק Telegram alerts.

### 4.6 הגעת עד לפה ועדיין לא עובד

| תסמין | פתרון |
|-------|-------|
| `register` עובר אבל לא מופיע ב-table | ודא שה-workflow `00_register` activated ב-n8n UI |
| מופיע ב-table אבל `last_health_status: "down"` מיד | ה-`/health` שלך לא חוזר 200 — בדוק |
| WhatsApp מגיע אבל מהשירות הלא נכון | ה-`name` ב-manifest כפול עם שירות קיים |
| `internal_url` לא מגיב מ-n8n | ודא ש-Private Networking דלוק ב-Railway project |
| אין אף ניסיון ב-`onboarding_history` | ה-`02_onboarding` workflow disabled (זה המצב הנוכחי) — השתמש ב-register ישיר במקום |

---

## 5. הפניות

- ארכיטקטורה: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- תפעול: [`RUNBOOK.md`](RUNBOOK.md)
- ספק מקור: [`CLAUDE_CODE_HANDOFF_v3.md`](CLAUDE_CODE_HANDOFF_v3.md)
- Templates: `templates/mesh-template-node/`, `templates/mesh-template-python/`
- Workflow JSONs: `n8n_workflows/00_register.json`, `01_route.json`, `02_onboarding.json`
- Inventory מלא של 80 השירותים: `services_inventory.json`
