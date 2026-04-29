# Claude Code Handoff v3: Sivan's Self-Expanding Stack

> **גרסה:** 3.0 — Service Mesh + Auto-Onboarding
> **בעלים:** Sivan
> **מבצע:** Claude Code
> **מחליף:** v1.0, v2.0
> **מסמך מקור:** `Paperclip_Jarvis_n8n_Evolution_Full_Process_Spec_HE.docx` (מצורף)
>
> **חדש ב-v3:** כל פרויקט/שירות חדש שנוצר ב-Railway נכנס אוטומטית ל-mesh בלי התערבות ידנית.

---

## 0. הוראות לקלוד קוד — קרא ראשון

המסמך הזה הוא **תוכנית ביצוע מלאה**, לא הצעה. אתה אמור להריץ אותו מסעיף 1 עד 12 בסדר, בלי לחזור לסיון בשאלות אלא אם הגעת ל-`STOP — REQUIRES USER INPUT`.

**מטרת העל של סיון:**

> "כל הכלים אצלי על Railway יהיו מחוברים אחד לשני. אם כלי A צריך משהו מכלי B, הוא ידע איפה B יושב, איך לדבר איתו, ואיך לשתף נתונים. אני רוצה שליטה. אם משהו נופל — אני אדע איפה ולמה ואיך לתקן.
> **ובנוסף — כל פעם שאני יוצר שירות חדש ב-Railway, הוא נכנס למערכת אוטומטית. אני לא אגע בקוד אחר.**"

זה אומר 4 שכבות:
1. **Service Mesh** — רשת שכל הכלים מחוברים אליה ומגלים זה את זה (v2)
2. **Auto-Onboarding** — שירות חדש = הצטרפות אוטומטית למסה (חדש ב-v3)
3. **Orchestration** — n8n מנהל workflows מורכבים
4. **Self-Healing Monitoring** — watchdog שמתריע ב-WhatsApp + Telegram עם סיבה והמלצת תיקון

**שלב 0 שלך:** הרץ `railway service list` והבא רשימה של כל השירותים ב-project. תיצור אותה בקובץ `services_inventory.json` בתחילת העבודה. כל החלטה אחרת מתבססת על זה.

---

## 1. מפת המערכת

```
                          ┌──────────────────────────┐
                          │    Service Registry      │
                          │  (Postgres + REST API)   │
                          └──────────┬───────────────┘
                                     │ קוראים/נרשמים
        ┌────────────────┬───────────┼───────────┬────────────────┐
        │                │           │           │                │
   ┌────▼────┐     ┌─────▼────┐ ┌───▼────┐ ┌────▼─────┐    ┌────▼────┐
   │ Jarvis  │     │ Paperclip│ │  n8n   │ │  Dify    │    │  ...    │
   │(Telegram│     │  (Tasks) │ │(Workflw│ │  (LLM)   │    │ Other   │
   │  Bot)   │     │          │ │ Engine)│ │          │    │ Tools   │
   └────┬────┘     └─────┬────┘ └───┬────┘ └────┬─────┘    └────┬────┘
        │                │          │           │                │
        │   ┌────────────┴──────────┼───────────┴────────────────┘
        │   │   Internal Network (Railway private)
        │   │   + Discovery Library
        ▼   ▼
   ┌─────────────────┐
   │  External:      │
   │  Telegram /     │
   │  WhatsApp via   │
   │  Evolution      │
   └─────────────────┘
                                     │
                          ┌──────────▼───────────┐
                          │  Watchdog (n8n WF)   │
                          │  בודק /health של כל  │
                          │  שירות כל 5 דק'      │
                          └──────────┬───────────┘
                                     │ אם כשל
                          ┌──────────▼───────────┐
                          │ Notification Router  │
                          └─────┬─────────┬──────┘
                                │         │
                                ▼         ▼
                          [WhatsApp]  [Telegram]
```

---

## 2. החלטות ארכיטקטורה (Final)

### 2.1 שלוש דרכי תקשורת — מתי כל אחת

| דרך | מתי משתמשים | יתרון | חיסרון |
|-----|---------|-------|--------|
| **Direct via Internal URL** | קריאות data-only, sync, ללא לוגיקה (Jarvis קורא רשימת agents מ-Paperclip) | מהיר, פשוט | coupling |
| **Orchestrated via n8n** | כל workflow עם החלטות, retry, התראות, שלבים | visibility, גמישות | overhead של hop |
| **MCP (AI-to-AI)** | תקשורת בין כלי AI (Dify ↔ Jarvis ↔ Flowise) | סטנדרט פתוח, capability negotiation | רק לכלי AI שתומכים |

**כלל אצבע לקלוד קוד:**
- אם זה "תביא לי X" — Direct.
- אם זה "תעשה X ואז Y ואז דווח" — n8n.
- אם זה "AI שואל AI שאלה" — MCP.

### 2.2 מקור אמת אחד — Service Registry

יש **רשם מרכזי** ב-Postgres. כל שירות נרשם בעלייה. כל שירות שואל אותו לפני קריאה לשירות אחר.

זה מחליף את הצורך לאתחל URLs ידנית בכל קובץ `.env`. שינוי שירות אחד → כל השאר רואים את זה תוך שניות.

### 2.3 Internal vs Public

- **Internal Network ב-Railway** לכל קריאת שרת-לשרת בתוך אותו project.
- **Public URLs** רק ל: Telegram webhooks, Evolution API callbacks, debugging מהמחשב המקומי.

---

## 3. Service Registry — הליבה החדשה

### 3.1 Schema של הרישום

טבלת Postgres `service_registry`:

```sql
CREATE TABLE service_registry (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,           -- 'paperclip', 'jarvis', 'dify'
  display_name TEXT NOT NULL,          -- 'Paperclip Task System'
  category TEXT NOT NULL,              -- 'orchestration' | 'ai' | 'task' | 'comms' | 'data'

  internal_url TEXT NOT NULL,          -- http://paperclip.railway.internal:8080
  public_url TEXT,                     -- https://paperclip-prod.up.railway.app (אם קיים)
  health_endpoint TEXT DEFAULT '/health',
  manifest_endpoint TEXT DEFAULT '/manifest',

  capabilities JSONB NOT NULL DEFAULT '[]'::jsonb,
  -- דוגמה: ["create_task", "list_agents", "task_status", "assign_task"]

  endpoints JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- דוגמה: {"create_task": {"method": "POST", "path": "/api/issues", "body_schema": {...}}}

  auth_type TEXT NOT NULL,             -- 'bearer' | 'api_key' | 'oauth' | 'none'
  auth_secret_env_var TEXT,            -- שם משתנה הסביבה שמכיל את הסוד (לא הסוד עצמו!)

  status TEXT NOT NULL DEFAULT 'active', -- 'active' | 'deprecated' | 'maintenance'
  version TEXT NOT NULL DEFAULT '1.0.0',

  registered_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ DEFAULT NOW(),
  metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_service_registry_capabilities ON service_registry USING GIN (capabilities);
CREATE INDEX idx_service_registry_category ON service_registry(category);
CREATE INDEX idx_service_registry_name ON service_registry(name);
```

### 3.2 Service Manifest — כל שירות חושף

כל שירות חייב לחשוף `GET /manifest` שמחזיר:

```json
{
  "name": "paperclip",
  "display_name": "Paperclip Task System",
  "version": "1.4.2",
  "category": "task",
  "internal_url": "http://paperclip.railway.internal:8080",
  "health_endpoint": "/health",
  "auth_type": "bearer",
  "auth_secret_env_var": "PAPERCLIP_API_KEY",
  "capabilities": [
    "create_task",
    "list_agents",
    "task_status",
    "assign_task",
    "list_departments"
  ],
  "endpoints": {
    "create_task": {
      "method": "POST",
      "path": "/api/issues",
      "body_schema": {
        "title": "string (required)",
        "body": "string (required)",
        "assignee": "string",
        "department": "string",
        "priority": "low | normal | high | urgent",
        "metadata": "object"
      },
      "returns": {
        "task_id": "string",
        "status": "string"
      }
    },
    "list_agents": {
      "method": "GET",
      "path": "/api/agents",
      "returns": "array of agent objects"
    },
    "task_status": {
      "method": "GET",
      "path": "/api/issues/{task_id}",
      "returns": "task object with status"
    }
  },
  "openapi_spec_url": "/openapi.json",
  "documentation_url": "/docs"
}
```

**אם שירות לא יודע לחשוף `/manifest`:** הוסף לו endpoint כזה. זה כיתבית כניסה ל-mesh.

### 3.3 Service Registry API

תקים שירות חדש ב-Railway בשם `service-registry`. הוא חושף:

```
POST /register      — שירות מתחבר ושולח את ה-manifest שלו
PUT  /heartbeat     — שירות מסמן שהוא חי (כל 60 שניות)
GET  /services      — רשימת כל השירותים הפעילים
GET  /services/:name — פרטי שירות אחד
GET  /capabilities/:cap — מי יודע לעשות capability מסוים
GET  /search?q=...  — חיפוש לפי שם/יכולת/קטגוריה
DELETE /services/:name — הסרת שירות (manual)
```

קוד מינימלי (Node.js + Express + Postgres):

```javascript
// service-registry/index.js
const express = require('express');
const { Pool } = require('pg');
const app = express();
app.use(express.json());

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Auth middleware פשוט — רק Internal traffic או עם REGISTRY_API_KEY
app.use((req, res, next) => {
  const internal = req.hostname.endsWith('.railway.internal');
  const apiKey = req.headers['x-registry-key'];
  if (!internal && apiKey !== process.env.REGISTRY_API_KEY) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  next();
});

app.post('/register', async (req, res) => {
  const m = req.body;
  await pool.query(`
    INSERT INTO service_registry
      (name, display_name, category, internal_url, public_url,
       health_endpoint, manifest_endpoint, capabilities, endpoints,
       auth_type, auth_secret_env_var, version, last_seen_at)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12, NOW())
    ON CONFLICT (name) DO UPDATE SET
      display_name = EXCLUDED.display_name,
      internal_url = EXCLUDED.internal_url,
      public_url = EXCLUDED.public_url,
      capabilities = EXCLUDED.capabilities,
      endpoints = EXCLUDED.endpoints,
      version = EXCLUDED.version,
      last_seen_at = NOW(),
      status = 'active'
  `, [
    m.name, m.display_name, m.category, m.internal_url, m.public_url,
    m.health_endpoint || '/health', m.manifest_endpoint || '/manifest',
    JSON.stringify(m.capabilities || []), JSON.stringify(m.endpoints || {}),
    m.auth_type || 'none', m.auth_secret_env_var || null, m.version || '1.0.0'
  ]);
  res.json({ status: 'registered', name: m.name });
});

app.put('/heartbeat/:name', async (req, res) => {
  await pool.query(
    'UPDATE service_registry SET last_seen_at = NOW() WHERE name = $1',
    [req.params.name]
  );
  res.json({ status: 'ok' });
});

app.get('/services', async (req, res) => {
  const r = await pool.query(`
    SELECT * FROM service_registry
    WHERE status = 'active'
      AND last_seen_at > NOW() - INTERVAL '5 minutes'
    ORDER BY name
  `);
  res.json(r.rows);
});

app.get('/services/:name', async (req, res) => {
  const r = await pool.query(
    'SELECT * FROM service_registry WHERE name = $1',
    [req.params.name]
  );
  if (!r.rows[0]) return res.status(404).json({ error: 'not_found' });
  res.json(r.rows[0]);
});

app.get('/capabilities/:cap', async (req, res) => {
  const r = await pool.query(`
    SELECT * FROM service_registry
    WHERE capabilities @> $1::jsonb
      AND status = 'active'
      AND last_seen_at > NOW() - INTERVAL '5 minutes'
  `, [JSON.stringify([req.params.cap])]);
  res.json(r.rows);
});

app.get('/search', async (req, res) => {
  const q = `%${req.query.q || ''}%`;
  const r = await pool.query(`
    SELECT * FROM service_registry
    WHERE (name ILIKE $1 OR display_name ILIKE $1 OR category ILIKE $1)
      AND status = 'active'
  `, [q]);
  res.json(r.rows);
});

app.listen(process.env.PORT || 3000, () => {
  console.log('Service Registry running');
});
```

### 3.4 Discovery Library — Python

קובץ `discovery_lib/python/discovery.py`:

```python
import os, requests
from functools import lru_cache
from typing import Optional, Dict, Any

REGISTRY_URL = os.environ.get(
    'REGISTRY_INTERNAL_URL',
    'http://service-registry.railway.internal:3000'
)

class ServiceClient:
    def __init__(self, manifest: Dict[str, Any]):
        self.manifest = manifest
        self.base = manifest['internal_url']
        self.auth_type = manifest.get('auth_type', 'none')
        self.secret = os.environ.get(manifest.get('auth_secret_env_var', ''), '')

    def _headers(self):
        h = {'Content-Type': 'application/json'}
        if self.auth_type == 'bearer':
            h['Authorization'] = f'Bearer {self.secret}'
        elif self.auth_type == 'api_key':
            h['X-API-Key'] = self.secret
        return h

    def call(self, capability: str, **kwargs):
        ep = self.manifest['endpoints'].get(capability)
        if not ep:
            raise ValueError(f"Service has no capability: {capability}")
        url = self.base + ep['path']
        # החלפת path params
        for k, v in kwargs.items():
            url = url.replace('{' + k + '}', str(v))
        method = ep['method'].upper()
        if method == 'GET':
            return requests.get(url, headers=self._headers(), timeout=30).json()
        else:
            return requests.request(
                method, url, headers=self._headers(),
                json=kwargs, timeout=30
            ).json()

@lru_cache(maxsize=64)
def discover(name: str) -> ServiceClient:
    """גלה שירות לפי שם."""
    r = requests.get(f"{REGISTRY_URL}/services/{name}", timeout=5)
    r.raise_for_status()
    return ServiceClient(r.json())

def find_capable(capability: str) -> list:
    """החזר את כל השירותים שיודעים לעשות capability מסוים."""
    r = requests.get(f"{REGISTRY_URL}/capabilities/{capability}", timeout=5)
    r.raise_for_status()
    return [ServiceClient(m) for m in r.json()]

def register_self(manifest: Dict[str, Any]):
    """כל שירות קורא לזה ב-startup."""
    requests.post(f"{REGISTRY_URL}/register", json=manifest, timeout=10)

def heartbeat(name: str):
    """כל שירות קורא לזה כל 60 שניות."""
    requests.put(f"{REGISTRY_URL}/heartbeat/{name}", timeout=5)
```

**שימוש לדוגמה — Jarvis צריך ליצור משימה ב-Paperclip:**

```python
from discovery import discover

paperclip = discover('paperclip')
result = paperclip.call('create_task',
    title='פוסט שבועי',
    body='צור 5 פוסטים על השקעה ביוון',
    assignee='Marketing Manager',
    priority='normal'
)
print(result['task_id'])
```

או — Jarvis לא יודע איזה שירות יוצר משימות, רק שצריך:

```python
from discovery import find_capable

services = find_capable('create_task')
print([s.manifest['name'] for s in services])
# ['paperclip', 'asana_bridge', ...]
# בחר אחד לפי לוגיקה
```

### 3.5 Discovery Library — JavaScript (ל-n8n ולשירותי Node)

קובץ `discovery_lib/js/discovery.js`:

```javascript
const axios = require('axios');

const REGISTRY_URL = process.env.REGISTRY_INTERNAL_URL
  || 'http://service-registry.railway.internal:3000';

class ServiceClient {
  constructor(manifest) {
    this.manifest = manifest;
    this.base = manifest.internal_url;
    this.authType = manifest.auth_type || 'none';
    this.secret = process.env[manifest.auth_secret_env_var] || '';
  }

  headers() {
    const h = { 'Content-Type': 'application/json' };
    if (this.authType === 'bearer') h.Authorization = `Bearer ${this.secret}`;
    if (this.authType === 'api_key') h['X-API-Key'] = this.secret;
    return h;
  }

  async call(capability, params = {}) {
    const ep = this.manifest.endpoints[capability];
    if (!ep) throw new Error(`No capability: ${capability}`);
    let url = this.base + ep.path;
    for (const [k, v] of Object.entries(params)) {
      url = url.replace(`{${k}}`, v);
    }
    const cfg = { method: ep.method, url, headers: this.headers(), timeout: 30000 };
    if (ep.method.toUpperCase() !== 'GET') cfg.data = params;
    const r = await axios(cfg);
    return r.data;
  }
}

const cache = new Map();

async function discover(name) {
  if (cache.has(name)) return cache.get(name);
  const r = await axios.get(`${REGISTRY_URL}/services/${name}`, { timeout: 5000 });
  const client = new ServiceClient(r.data);
  cache.set(name, client);
  setTimeout(() => cache.delete(name), 60000); // refresh every minute
  return client;
}

async function findCapable(capability) {
  const r = await axios.get(`${REGISTRY_URL}/capabilities/${capability}`, { timeout: 5000 });
  return r.data.map(m => new ServiceClient(m));
}

async function registerSelf(manifest) {
  await axios.post(`${REGISTRY_URL}/register`, manifest, { timeout: 10000 });
}

async function heartbeat(name) {
  await axios.put(`${REGISTRY_URL}/heartbeat/${name}`, null, { timeout: 5000 });
}

module.exports = { discover, findCapable, registerSelf, heartbeat };
```

### 3.6 שימוש ב-n8n — Custom Function Node

הוסף ל-n8n קובץ `n8n_helpers/discover.js`:

```javascript
// בתוך n8n Function node:
const { discover } = require('/data/discovery');
const paperclip = await discover('paperclip');
const result = await paperclip.call('create_task', {
  title: $json.title,
  body: $json.body
});
return [{ json: result }];
```

### 3.7 Self-Registration ב-Startup

כל שירות חייב לרוץ בקוד שלו, ב-startup:

```python
# Python
from discovery import register_self, heartbeat
import threading, time

MANIFEST = { ... }  # ראה 3.2

def heartbeat_loop():
    while True:
        heartbeat(MANIFEST['name'])
        time.sleep(60)

if __name__ == '__main__':
    register_self(MANIFEST)
    threading.Thread(target=heartbeat_loop, daemon=True).start()
    # ... start your app
```

```javascript
// Node
const { registerSelf, heartbeat } = require('./discovery');
const MANIFEST = require('./manifest.json');

async function bootstrap() {
  await registerSelf(MANIFEST);
  setInterval(() => heartbeat(MANIFEST.name), 60000);
}
bootstrap();
```

---

---

## 4. Auto-Onboarding Pipeline — חדש ב-v3

זה החלק שהופך את ה-mesh לחי. בלי זה — כל שירות חדש דורש פעולה ידנית. עם זה — סיון יוצר שירות, הוא מצטרף לבד.

### 4.1 ארכיטקטורה

```
[Sivan creates new Railway service]
         │
         ▼
[Railway Webhook fires] ──┐
                          │     ├─ או ──┐
[Polling cron כל 5 דק']  ──┘             │
                                         ▼
                              [Onboarding Bot in n8n]
                                         │
                                ┌────────┴────────┐
                                ▼                 ▼
                       [Wait 90s for boot]  [Detect public+internal URL]
                                │
                                ▼
                       [Probe GET /manifest]
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
  [200 + valid manifest] [200 but invalid] [404 / no response]
        │                 │                 │
        ▼                 ▼                 ▼
  [Auto-register]   [Send fix notice]   [Bootstrap PR or manual notice]
        │                 │                 │
        ▼                 ▼                 ▼
  [WhatsApp ✅]     [WhatsApp 🟡]       [WhatsApp 🟠]
```

### 4.2 איך לזהות שירות חדש — שלוש אופציות

**Option A: Railway Project Webhook (מועדף)**

ב-Railway dashboard → Project Settings → Webhooks:
- Event: `service.created` או `deployment.success` (תלוי במה שזמין)
- URL: `https://your-n8n.up.railway.app/webhook/onboarding-trigger`

n8n מקבל payload עם פרטי השירות החדש.

**Option B: GraphQL Polling**

אם Railway לא מספק webhook לאירוע הרצוי — cron ב-n8n שרץ כל 5 דק':

```graphql
query GetServices($projectId: String!) {
  project(id: $projectId) {
    services {
      edges {
        node {
          id
          name
          createdAt
          deployments(first: 1) {
            edges { node { staticUrl status } }
          }
        }
      }
    }
  }
}
```

n8n שומר רשימה של שירותים מוכרים ב-Data Store. כל שם חדש = trigger לonboarding.

**Option C: Hybrid (הכי בטוח)**

webhook **+** polling כל שעה כ-fallback. אם webhook פספס משהו, polling יתפוס.

קלוד קוד יבחר Option A אם Railway תומך, Option C אם לא בטוח.

### 4.3 Onboarding Bot Workflow

קובץ: `n8n_workflows/05_onboarding_bot.json`

| # | Node | תפקיד |
|---|------|-------|
| 1 | Webhook Trigger | מקבל אירוע "service created" |
| 2 | Wait | 90 שניות, לתת לשירות לעלות |
| 3 | Build URLs | בונה `internal_url` ו-`public_url` מ-service name |
| 4 | HTTP — Probe Manifest | `GET {internal_url}/manifest`, timeout 10s, retries 3 |
| 5 | Switch | פיצול לפי תוצאה |
| 6a | Validate Manifest | אם 200 — בדוק schema |
| 6b | Register in Mesh | `POST registry/register` עם ה-manifest |
| 6c | Notify Sivan ✅ | WhatsApp + Telegram |
| 7a | If invalid manifest | שלח לסיון רשימת שדות חסרים |
| 7b | If no manifest | בדוק אם יש לפחות `/health` |
| 7c | If completely silent | שלח לסיון "שירות חדש לא תקין" |
| 8 | Log | רישום ב-`onboarding_history` table |

### 4.4 Validation של Manifest

הקלט הוא ה-JSON שחוזר מ-`/manifest`. בדיקות חובה:

```javascript
function validateManifest(m) {
  const errors = [];
  if (!m.name || !/^[a-z0-9-]+$/.test(m.name))
    errors.push('name חייב להיות lowercase + מקפים');
  if (!m.version) errors.push('version חסר');
  if (!m.category) errors.push('category חסר');
  if (!m.internal_url?.includes('.railway.internal'))
    errors.push('internal_url לא חוקי או לא Railway internal');
  if (!Array.isArray(m.capabilities) || m.capabilities.length === 0)
    errors.push('חייב לפחות capability אחד');
  if (!m.endpoints || typeof m.endpoints !== 'object')
    errors.push('endpoints חסר');
  for (const cap of m.capabilities || []) {
    if (!m.endpoints[cap])
      errors.push(`capability '${cap}' מוצהר אבל אין לו endpoint`);
  }
  return { valid: errors.length === 0, errors };
}
```

### 4.5 הודעות לסיון

**🟢 הצלחה — שירות הצטרף:**
```
✅ שירות חדש הצטרף ל-mesh

שם: {{service_name}}
קטגוריה: {{category}}
יכולות: {{capabilities_list}}
URL פנימי: {{internal_url}}

סטטוס: רשום ופעיל. שירותים אחרים יכולים להשתמש בו עכשיו.
```

**🟡 שירות תקין חלקית:**
```
🟡 שירות חדש זוהה אבל לא תקין למלוא ה-mesh

שם: {{service_name}}
מה חסר:
{{validation_errors}}

תיקון: ראה {{registry_public_url}}/docs/add-new-service
או הקם את השירות מחדש מתבנית: {{template_repo_url}}
```

**🟠 שירות חדש לא מגיב:**
```
🟠 שירות חדש זוהה אבל לא תקין כלל

שם: {{service_name}}
זמן יצירה: {{created_at}}
סטטוס: לא מגיב ל-/manifest ולא ל-/health

זה יכול להיות:
1. שירות עדיין לא סיים deploy — נחזור לבדוק עוד 5 דק'
2. שירות לא מסה-compliant — צריך תבנית או wrapper
3. שירות שלא מיועד ל-mesh (DB, Redis) — סמן idle ב-registry
```

### 4.6 Retry & Recovery

אם הניסיון הראשון נכשל ב-stage 7c ("not responsive"), n8n מתזמן retry אחרי 5 דק', אחרי 15 דק', אחרי שעה. אחרי 3 כשלים — שולח לסיון הודעה סופית "שירות X זנוח" ושומר אותו ברשימת idle.

### 4.7 Idle Services Registry

שירותים שלא מגיבים אחרי כל ה-retries נשמרים ב-`idle_services` בטבלה נפרדת. ב-watchdog (סעיף 5) — לא מתריעים על idle services. אבל ב-dashboard סיון רואה אותם תחת "צריך טיפול".

### 4.8 Removing Services

כשסיון מוחק שירות מ-Railway:
- Webhook `service.deleted` (אם זמין) → onboarding bot מסמן ב-registry `status = 'deleted'`
- אחרת — ה-watchdog מזהה שאין `last_seen_at` יותר מ-30 דקות ומסמן `status = 'inactive'`. אחרי 24 שעות מסמן `status = 'deleted'`.

---

זהה ל-v1, עם שינוי אחד: ה-Watchdog לא צריך רשימת שירותים hardcoded יותר. הוא קורא ל-`GET /services` ב-Service Registry ובודק את כל מה שמוחזר.

## 5. שכבת מוניטורינג גלובלית

זהה ל-v1 — watchdog בודק את כל השירותים מה-registry, מתריע ב-WhatsApp + Telegram עם סיבה והמלצת תיקון. ה-watchdog לא צריך רשימה hardcoded — הוא קורא ל-`GET /services` ב-Service Registry ובודק את כל מה שמוחזר.

### 5.1 ארכיטקטורה

```
Schedule (כל 5 דק') → GET /services → לולאה: ping /health של כל שירות
   → אגרגציה → IF כשל → Error Classifier → Notification Router
       ├─ WhatsApp via Evolution → 972524568134
       └─ Telegram via Jarvis → CEO chat
```

### 5.2 Error Classifier

```javascript
function classify(input) {
  if (input.status_code === null && input.error_text?.includes('timeout')) {
    return {
      classification: 'unreachable',
      severity: 'critical',
      suggested_fix: `שירות ${input.service} לא מגיב. בדוק ב-Railway dashboard. אם הקונטיינר חי — בדוק לוגים: railway logs --service=${input.service}`
    };
  }
  if (input.status_code >= 500) {
    return {
      classification: 'server_error', severity: 'high',
      suggested_fix: `שגיאת שרת ב-${input.service}. railway logs --service=${input.service} --tail=100`
    };
  }
  if (input.status_code === 429) {
    return {
      classification: 'rate_limited', severity: 'medium',
      suggested_fix: `${input.service} מוגבל בקצב. בדוק תקרות upstream או העלה tier.`
    };
  }
  if (input.response_time_ms > 5000) {
    return {
      classification: 'slow_response', severity: 'medium',
      suggested_fix: `${input.service} איטי (${input.response_time_ms}ms). בדוק עומס DB או CPU.`
    };
  }
  return {
    classification: 'unknown', severity: 'low',
    suggested_fix: `שגיאה לא מסווגת ב-${input.service}. בדוק לוגים ידנית.`
  };
}
```

### 5.3 תבניות הודעה

#### WhatsApp:
```
🚨 התראת מערכת — Sivan Stack

שירות: {{service_name}}
חומרה: {{severity_he}}
זמן: {{timestamp_il}}

מה קרה:
{{error_summary}}

המלצה לתיקון:
{{suggested_fix}}

Incident ID: {{incident_id}}
```

severity mapping: critical→🔴 קריטי, high→🟠 גבוה, medium→🟡 בינוני, low→🔵 נמוך

#### Telegram via Jarvis:
JSON עם `type: "system_alert"` שג'רוויס מעצב להצגה.

### 5.4 Dedup — חלון 30 דק'

`incident_state` ב-Postgres עם מפתח `{service}_{classification}`. לפני שליחה — בדוק אם יש incident פתוח חדש מ-30 דק'. אם כן → אל תשלח שוב, רק עדכן מונה.

הודעת recovery כשהשירות חוזר:
```
✅ שירות חזר לפעולה — {{service_name}}
משך השבתה: {{downtime_minutes}} דק'
```

### 5.5 Error Trigger גלובלי ב-n8n

צור workflow `99_global_error_handler` שמופעל מכל workflow אחר במצב כשל. הגדר אותו כ-Default Error Workflow ב-n8n Settings.

### 5.6 External Heartbeat — מי שומר על השומר

UptimeRobot או cron-job.org שמבצע ping ל-`https://your-n8n.up.railway.app/healthz` כל 2 דק'. אם נופל — שולח SMS/email ישיר לסיון, וגם POST ישיר ל-Evolution API להודעת WhatsApp fallback.

---

## 6. תוכנית ביצוע — סדר חובה

**לא לשנות סדר.** כל שלב מבוסס על הקודם.

### Phase 0: Inventory & Prep
- [ ] 0.1 — `railway service list` → צור `services_inventory.json`
- [ ] 0.2 — לכל שירות: `railway variables` → תעד מה ה-`.env` שלו ב-`env_audit.md`
- [ ] 0.3 — ודא Private Networking דלוק לכל ה-project
- [ ] 0.4 — אם יש שירות ב-VPS אחר (לא Railway) — סמן אותו כ-`external` ב-inventory

### Phase 1: Service Registry
- [ ] 1.1 — צור שירות חדש ב-Railway: `service-registry`
- [ ] 1.2 — Postgres: או חדש או קיים. הרץ ה-DDL מ-3.1
- [ ] 1.3 — deploy את הקוד מ-3.3
- [ ] 1.4 — בדיקה: `curl http://service-registry.railway.internal:3000/services` → מחזיר `[]`

### Phase 2: Discovery Library
- [ ] 2.1 — צור repo `discovery-lib` עם תיקיות `python/` ו-`js/`
- [ ] 2.2 — קוד מ-3.4 ו-3.5
- [ ] 2.3 — פרסם package פנימי (`pip install` מ-git, `npm link`, או mount כ-volume)

### Phase 3: Onboarding כל שירות קיים
- [ ] 3.1 — לכל שירות ב-`services_inventory.json`:
  - הוסף endpoint `/manifest` עם תיאור מלא
  - הוסף endpoint `/health` בפורמט מהסעיף 3.2 ב-v1
  - הוסף בקוד ה-startup קריאה ל-`register_self` + `heartbeat` loop
  - deploy
  - בדוק: `curl http://service-registry.../services/<name>` → מחזיר manifest
- [ ] 3.2 — שינוי URLs בכל שירות: השתמש ב-`discover()` במקום ב-env vars hardcoded ל-URLs של שירותים אחרים
- [ ] 3.3 — שמור את env vars של **סודות בלבד** (API keys), לא URLs

🚦 **STOP אם:** שירות קיים שלא אפשר לשנות בו את הקוד. במקרה כזה צור wrapper service קטן שמתפקד כ-proxy ורושם את עצמו ב-mesh.

### Phase 4: Auto-Onboarding Pipeline (חדש ב-v3)
- [ ] 4.1 — צור workflow `05_onboarding_bot` ב-n8n לפי 4.3
- [ ] 4.2 — הגדר Railway webhook לפרויקט (Option A מ-3.5.2). אם לא קיים האירוע הרצוי — הקם cron polling (Option B/C)
- [ ] 4.3 — הקם טבלאות `onboarding_history` ו-`idle_services` ב-Postgres
- [ ] 4.4 — צור `templates/` repos (ראה סעיף 7) והעלה ל-GitHub
- [ ] 4.5 — בדיקה: צור שירות test ב-Railway מהתבנית `mesh-template-node` → ודא שתוך 2 דק' מתקבלת הודעת WhatsApp ✅ והשירות מופיע ב-`GET /services`
- [ ] 4.6 — בדיקה שלילית: צור שירות "ריק" (without manifest) → ודא שמתקבלת הודעה 🟠

🚦 **STOP אם:** Railway webhook לא תומך ב-`service.created`. במקרה כזה הסתפק ב-polling וציין ב-RUNBOOK שהזיהוי איטי יותר (עד 5 דק').

### Phase 5: Monitoring
- [ ] 4.1 — צור `00_watchdog` workflow ב-n8n לפי 5.1-5.2
- [ ] 4.2 — צור `99_global_error_handler` והגדר אותו כ-default error workflow
- [ ] 4.3 — הקם UptimeRobot externally
- [ ] 4.4 — בדיקה: `railway down --service=paperclip` → התראה תוך 7 דק'

### Phase 6: פלואו ראשי Jarvis→Paperclip
על פי המסמך המקורי המצורף, סעיפים 5-21. שינוי יחיד: שימוש ב-`discover('paperclip')` במקום URL hardcoded.

- [ ] 5.1 — Webhook נכנס מ-Jarvis (סעיף 5)
- [ ] 5.2 — סינון "פייפרקליפ"/"paperclip"
- [ ] 5.3 — Parser ל-JSON (סעיף 7)
- [ ] 5.4 — Validation Checklist (סעיף 9)
- [ ] 5.5 — קריאה ל-Paperclip via discover (סעיף 11)
- [ ] 5.6 — שמירת Task ID
- [ ] 5.7 — Polling לסטטוס דרך discover (סעיף 13)
- [ ] 5.8 — WhatsApp דרך Evolution
- [ ] 5.9 — Payload לג'רוויס

### Phase 7: Cross-Tool Workflows (חדש — מה שאפשר ה-mesh)
דוגמאות לפלואים שנהיים אפשריים בקלות עם ה-mesh:

- [ ] 6.1 — Dify מקבל שאלה → שואל Jarvis → Jarvis מבקש מ-Paperclip מידע על משימה → Dify מנסח תשובה
- [ ] 6.2 — Flowise בונה automation → רושם אותה ב-Paperclip כמשימה למעקב
- [ ] 6.3 — Chatwoot/Chan מקבל פנייה מלקוח → קורא ל-Dify לסיווג → מנתב ל-Paperclip לעובד הנכון

(אם יש לך עוד כלים שלא הזכרת — הם אוטומטית מקבלים גישה ברגע שהם רשומים ב-mesh.)

### Phase 8: Permissions Layer
- [ ] 8.1 — מטריצת רמות (סעיף 16 ב-v1): INFO / TASK / APPROVAL / BLOCKED
- [ ] 8.2 — APPROVAL → WhatsApp לסיון לאישור לפני ביצוע
- [ ] 8.3 — BLOCKED → חסימה אוטומטית

### Phase 9: בדיקות קבלה
הרץ `scripts/test_full_mesh.sh` שכולל:
- [ ] 9.1 — כל שירות נראה ב-`GET /services`
- [ ] 9.2 — שירות יכול לגלות שירות אחר ולקרוא לו
- [ ] 9.3 — כשל יזום → התראה ב-WhatsApp + Telegram תוך 7 דק'
- [ ] 9.4 — recovery message כשהשירות חוזר
- [ ] 9.5 — פלואו פייפרקליפ E2E מהמסמך המקורי
- [ ] 9.6 — n8n נופל → UptimeRobot מודיע
- [ ] 9.7 — **שירות חדש שנוצר ב-Railway → onboarding תוך 2 דק'** (חדש ב-v3)
- [ ] 9.8 — **שירות חדש לא תקין → הודעה אבחון** (חדש ב-v3)

### Phase 10: Documentation
- [ ] 10.1 — `README.md` בכל repo עם הוראות
- [ ] 10.2 — `RUNBOOK.md` — מה לעשות כשמשהו נופל
- [ ] 10.3 — `MESH_DIAGRAM.md` — תרשים של כל השירותים והקשרים
- [ ] 10.4 — `ADD_NEW_SERVICE.md` — איך להוסיף שירות חדש (ראה סעיף 7 כאן)
- [ ] 10.5 — `TEMPLATES.md` — תיעוד של 3 התבניות (חדש ב-v3)

### Phase 11: סיון signoff
- [ ] 11.1 — שלח לסיון את הודעת הסיום (סעיף 13 בהמשך)

---

## 7. Adding a New Service — Template

עם Auto-Onboarding (3.5), ההוספה כמעט אוטומטית. אבל חייב להיות מבנה לעקוב אחריו.

### צ'קליסט להוספה (הדרך הקצרה — דרך תבנית)

1. ב-Railway: New Service → Deploy from GitHub
2. בחר אחד מהrepo templates: `mesh-template-node` / `mesh-template-python` / `mesh-template-ai-agent`
3. עדכן את `manifest.json` בקוד עם השם, ה-capabilities, וה-endpoints
4. Push → Railway deploy
5. **תוך 2 דק' תקבל WhatsApp ✅** שהשירות הצטרף ל-mesh

זהו. אין שלב 6.

### צ'קליסט להוספה (הדרך הארוכה — לשירות קיים)

1. הוסף `/health` ו-`/manifest` endpoints
2. ב-startup: `register_self()` + heartbeat loop כל 60 שניות
3. הוסף API keys ל-env של הצרכנים (אם לא חשוף לציבור)
4. Push + redeploy
5. Auto-Onboarding bot יזהה ויירשום

### Template manifest — הדבק והתאם

```json
{
  "name": "<lowercase-no-spaces>",
  "display_name": "<readable name>",
  "version": "1.0.0",
  "category": "<orchestration|ai|task|comms|data|other>",
  "internal_url": "http://<name>.railway.internal:<PORT>",
  "public_url": "<https url או null>",
  "health_endpoint": "/health",
  "manifest_endpoint": "/manifest",
  "auth_type": "<bearer|api_key|oauth|none>",
  "auth_secret_env_var": "<NAME_OF_ENV_VAR>",
  "capabilities": ["capability_1", "capability_2"],
  "endpoints": {
    "capability_1": {
      "method": "POST",
      "path": "/api/...",
      "body_schema": {...},
      "returns": {...}
    }
  }
}
```

---

## 8. Service Templates — 3 Starter Repos (חדש ב-v3)

קלוד קוד יוצר 3 GitHub repos כתבניות. כל repo מכיל skeleton עובד + manifest + self-registration. סיון יכול לעשות "Use this template" בלחיצה אחת.

### 7.1 `mesh-template-node`

מבוסס Express. מתאים ל-API services רגילים.

מבנה:
```
mesh-template-node/
├── src/
│   ├── index.js              # Entry point
│   ├── manifest.js            # Service manifest
│   ├── routes/
│   │   ├── health.js          # /health endpoint
│   │   ├── manifest.js        # /manifest endpoint
│   │   └── api.js             # YOUR business logic here
│   └── lib/
│       └── discovery.js       # Discovery library (from sec 3.5)
├── Dockerfile
├── railway.json               # Railway config
├── package.json
├── .env.example
└── README.md                  # Hebrew + English instructions
```

תוכן `src/index.js`:

```javascript
const express = require('express');
const { registerSelf, heartbeat } = require('./lib/discovery');
const manifest = require('./manifest');

const app = express();
app.use(express.json());

// Required mesh endpoints
app.use('/health', require('./routes/health'));
app.use('/manifest', require('./routes/manifest'));

// Your business logic
app.use('/api', require('./routes/api'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, async () => {
  console.log(`${manifest.name} running on ${PORT}`);
  try {
    await registerSelf(manifest);
    setInterval(() => heartbeat(manifest.name), 60_000);
    console.log('✅ Joined mesh');
  } catch (e) {
    console.error('❌ Mesh registration failed:', e.message);
    // ה-Onboarding Bot יזהה ויודיע לסיון
  }
});
```

תוכן `src/manifest.js`:

```javascript
module.exports = {
  name: process.env.SERVICE_NAME || 'CHANGE-ME',
  display_name: 'CHANGE ME',
  version: '1.0.0',
  category: 'other',          // orchestration | ai | task | comms | data | other
  internal_url: `http://${process.env.RAILWAY_SERVICE_NAME}.railway.internal:${process.env.PORT || 3000}`,
  public_url: process.env.RAILWAY_PUBLIC_DOMAIN ? `https://${process.env.RAILWAY_PUBLIC_DOMAIN}` : null,
  health_endpoint: '/health',
  manifest_endpoint: '/manifest',
  auth_type: 'none',
  capabilities: [
    // 'example_capability'
  ],
  endpoints: {
    // example_capability: {
    //   method: 'POST',
    //   path: '/api/example',
    //   body_schema: { input: 'string' },
    //   returns: { output: 'string' }
    // }
  }
};
```

תוכן `README.md`:

```markdown
# Mesh Template — Node

תבנית להוספת שירות חדש ל-mesh של סיון.

## איך משתמשים

1. Use this template → צור repo חדש
2. עדכן `src/manifest.js`:
   - שם השירות
   - capabilities שלך
   - endpoints
3. כתוב את הלוגיקה ב-`src/routes/api.js`
4. Deploy ל-Railway
5. תקבל WhatsApp תוך 2 דק' שהצטרפת ל-mesh

## משתני סביבה

ראה `.env.example`. ל-Railway: בדרך כלל מוגדר אוטומטית.

## איך לבדוק

- `curl https://<your-service>.up.railway.app/health` → 200
- `curl https://<your-service>.up.railway.app/manifest` → manifest JSON
```

### 7.2 `mesh-template-python`

מבוסס FastAPI. מתאים ל-AI/ML services וכל מה שעובד טוב בפייתון.

מבנה דומה ל-Node:
```
mesh-template-python/
├── app/
│   ├── main.py                # FastAPI entry
│   ├── manifest.py
│   ├── routes/
│   │   ├── health.py
│   │   ├── manifest.py
│   │   └── api.py
│   └── lib/
│       └── discovery.py
├── Dockerfile
├── railway.json
├── requirements.txt
├── .env.example
└── README.md
```

תוכן `app/main.py`:

```python
from fastapi import FastAPI
import asyncio, threading, os
from app.manifest import MANIFEST
from app.lib.discovery import register_self, heartbeat
from app.routes import health, manifest as manifest_route, api

app = FastAPI(title=MANIFEST['display_name'])

app.include_router(health.router, prefix='/health')
app.include_router(manifest_route.router, prefix='/manifest')
app.include_router(api.router, prefix='/api')

def heartbeat_loop():
    import time
    while True:
        try:
            heartbeat(MANIFEST['name'])
        except Exception as e:
            print(f'heartbeat failed: {e}')
        time.sleep(60)

@app.on_event('startup')
async def startup():
    try:
        register_self(MANIFEST)
        threading.Thread(target=heartbeat_loop, daemon=True).start()
        print(f'✅ {MANIFEST["name"]} joined mesh')
    except Exception as e:
        print(f'❌ Mesh registration failed: {e}')
```

### 7.3 `mesh-template-ai-agent`

מבוסס Python + LangChain/Anthropic SDK. מתאים לסוכני AI שיודעים גם לקרוא ל-services אחרים ב-mesh.

תוספות מעבר ל-template-python:
- `app/agent.py` — הסוכן עצמו עם system prompt + tools
- כל service ב-mesh נחשף אוטומטית כ-tool לסוכן (דרך `find_capable`)
- `capabilities` מוגדרות אוטומטית: `["chat", "execute_task"]`

תוכן `app/agent.py`:

```python
from anthropic import Anthropic
from app.lib.discovery import discover, find_capable
import os, json

client = Anthropic(api_key=os.environ['ANTHROPIC_API_KEY'])

def build_tools_from_mesh():
    """כל capability ב-mesh הופך לכלי לסוכן."""
    from app.lib.discovery import list_all_services
    services = list_all_services()
    tools = []
    for svc in services:
        if svc['name'] == os.environ.get('SERVICE_NAME'):
            continue  # אל תכלול את עצמך
        for cap_name, ep in svc.get('endpoints', {}).items():
            tools.append({
                'name': f"{svc['name']}__{cap_name}",
                'description': f"קריאה ל-{svc['display_name']}: {cap_name}",
                'input_schema': {
                    'type': 'object',
                    'properties': ep.get('body_schema', {})
                }
            })
    return tools

def execute_tool_call(tool_name, args):
    """כשהסוכן קורא ל-tool, נתב לשירות הנכון."""
    service_name, cap_name = tool_name.split('__', 1)
    return discover(service_name).call(cap_name, **args)

async def chat(user_message):
    tools = build_tools_from_mesh()
    response = client.messages.create(
        model='claude-sonnet-4-20250514',
        max_tokens=4096,
        tools=tools,
        messages=[{'role': 'user', 'content': user_message}]
    )
    # ... handle tool_use blocks, loop until done
```

זה אומר שכל **שירות AI חדש** שמשתמש בתבנית הזו מקבל גישה אוטומטית לכל שאר השירותים. אין צורך לעדכן רשימת tools ידנית.

### 7.4 איפה התבניות חיות

GitHub orgs:
- `github.com/sivan-mesh/mesh-template-node`
- `github.com/sivan-mesh/mesh-template-python`
- `github.com/sivan-mesh/mesh-template-ai-agent`

(או mono-repo `sivan-mesh/templates` עם folder לכל אחד — לבחירת קלוד קוד)

### 7.5 Bonus: Mesh CLI (אופציונלי)

אם יש זמן ב-Phase 10, צור CLI קטן:

```bash
$ npx @sivan-mesh/cli create my-new-service --template=python --category=ai
✅ Created repo: github.com/sivan-mesh/my-new-service
✅ Created Railway service: my-new-service
✅ Set env vars
✅ Deploying...
🟢 Ready in 90s. WhatsApp confirmation will arrive shortly.
```

זה הופך את ההוספה לפקודה אחת. אופציונלי, רק אם הזמן מאפשר.

---

## 9. משתני סביבה — רשימת מינימום לכל שירות

```bash
# ===== זהה לכל שירות במsh =====
REGISTRY_INTERNAL_URL=http://service-registry.railway.internal:3000
REGISTRY_API_KEY=...                    # (רק אם השירות מחוץ ל-Railway)
SERVICE_NAME=<this-service-name>

# ===== Service Registry בלבד =====
DATABASE_URL=postgresql://...

# ===== n8n בלבד =====
N8N_INTERNAL_URL=http://n8n.railway.internal:5678
N8N_PUBLIC_URL=https://n8n-...up.railway.app

# ===== מוניטורינג =====
EVOLUTION_API_URL=...
EVOLUTION_INSTANCE=sivan-main
EVOLUTION_API_KEY=...
CEO_WHATSAPP_NUMBER=972524568134
CEO_TELEGRAM_CHAT_ID=...
WATCHDOG_INTERVAL_MINUTES=5
WATCHDOG_DEDUP_WINDOW_MINUTES=30

# ===== סודות לכל שירות =====
PAPERCLIP_API_KEY=...
JARVIS_API_KEY=...
DIFY_API_KEY=...
# ... לפי הצורך
```

**שים לב:** URLs של שירותים *אחרים* כבר לא ב-env. השרת מקבל אותם מ-Service Registry בעלייה.

---

## 10. Edge Cases

### 8.1 n8n נופל
External Heartbeat (UptimeRobot) מודיע לסיון. הוא גם שולח ישירות ל-Evolution API הודעת WhatsApp fallback.

### 8.2 Service Registry נופל
זה SPOF. שני פתרונות:
- **קצר מועד:** כל שירות שומר cache מקומי של 5 דק' של תוצאות discovery. אם הregistry נופל — עובדים מ-cache עוד כמה דקות.
- **ארוך מועד:** רכיב את registry על Postgres עם backup חי, או duplicate לרשם נוסף.

ב-Phase 1 תממש את ה-cache. ב-Phase 9 תתעד את הסיכון של ה-SPOF ב-RUNBOOK.

### 8.3 Evolution נופל → אין WhatsApp
Watchdog יזהה. הוא לא יכול לשלוח WhatsApp להגיד את זה. לכן:
- הודעת Telegram תיתן ההתראה
- בנוסף — הוסף בעיצוב ההודעה: "WhatsApp לא זמין כרגע — כל ההתראות יגיעו לכאן עד שיחזור"

### 8.4 שירות חיצוני (לא Railway)
- לא יכול להיכנס ל-internal network
- יש לו רק `public_url`
- הוא משתמש ב-`REGISTRY_API_KEY` להרשמה דרך הPublic URL של ה-registry
- ה-Watchdog מבצע ping ל-public_url שלו

### 8.5 שירות לא יכול להוסיף `/manifest` (closed source)
הקם **wrapper service** קטן (50 שורות Express) שמתפקד כ-proxy:
- לקוחות פונים ל-wrapper
- wrapper חושף `/manifest` תקני
- wrapper מתרגם לקריאה ל-API המקורי

### 8.6 הודעות כפולות
n8n ידוע באתחול webhooks. שמור `message_id` ב-Data Store, ignore אם חוזר תוך 60 שניות.

---

## 11. תוצרים סופיים שתציג לסיון

```
/repos/
  service-registry/
    index.js
    package.json
    Dockerfile
    railway.json
  discovery-lib/
    python/
      discovery.py
      setup.py
    js/
      discovery.js
      package.json

/n8n_workflows/
  00_watchdog.json
  01_main_jarvis_to_paperclip.json
  02_validation_helper.json
  03_paperclip_status_poller.json
  99_global_error_handler.json

/scripts/
  bootstrap_mesh.sh
  test_full_mesh.sh
  rollback.sh

/docs/
  ARCHITECTURE.md
  MESH_DIAGRAM.md
  RUNBOOK.md
  ADD_NEW_SERVICE.md
  ENV_REFERENCE.md
  ORIGINAL_PAPERCLIP_SPEC.docx   ← המסמך המצורף, מועבר לכאן

services_inventory.json
env_audit.md
CHANGELOG.md
README.md
```

---

## 12. בדיקת קבלה סופית

הרץ `scripts/test_full_mesh.sh`:

1. ודא שכל השירותים מ-`services_inventory.json` רשומים ב-Service Registry
2. סקריפט פייתון: `discover('paperclip').call('list_agents')` → מחזיר רשימה
3. סקריפט ב-JS דרך n8n: זהה
4. שלח לג'רוויס: `"פייפרקליפ צור משימה לבדיקה: 5 פוסטים על השקעה"`
5. ודא: WhatsApp תוך 30 שניות, משימה ב-Paperclip, payload לג'רוויס בסיום
6. הפל את Paperclip ידנית: `railway down --service=paperclip`
7. ודא: התראה ב-WhatsApp + Telegram תוך 7 דק'
8. החזר: `railway up --service=paperclip`
9. ודא: recovery message
10. הפל את n8n
11. ודא: UptimeRobot שולח email/SMS + Evolution WhatsApp fallback
12. דוח JSON ב-`acceptance_report_<timestamp>.json`

כל 12 ירוקים → Production.

---

## 13. הודעת סיום לסיון

שלח דרך Jarvis:

```
✅ סטאק Sivan מאוחד — הסתיים.

מה נבנה:
1. Service Registry — כל הכלים מחוברים, מגלים זה את זה אוטומטית
2. Discovery Library — Python + JS + n8n
3. Self-registration לכל שירות קיים
4. Watchdog גלובלי — בדיקה כל 5 דק'
5. Error handler גלובלי ב-n8n
6. UptimeRobot חיצוני שומר על n8n עצמו
7. פלואו פייפרקליפ E2E

איך לבדוק:
- שלח לי כאן: "פייפרקליפ בדיקה: צור 3 פוסטים על השקעה ביוון"
- אמור לקבל WhatsApp תוך 30 שניות

סטטוס mesh:
- {{n8n_dashboard_url}}/workflows
- שירותים פעילים: {{registry_url}}/services

הוספת כלי חדש בעתיד:
- מסמך: ADD_NEW_SERVICE.md
- פעולה: deploy + register_self() + מאת זה גם n8n גם Jarvis יודעים עליו

אם משהו נשבר:
- WhatsApp ל-972524568134 עם הסיבה והתיקון המומלץ
- וגם הודעה כאן בטלגרם
- אם n8n עצמו נופל — UptimeRobot ישלח SMS

ממתין לפקודה הראשונה.
```

---

## נספח A — שאלות פתוחות שדורשות תשובה מסיון לפני העבודה

הוסף בעלייה לעבודה (Phase 0) שאלות לסיון:

1. **רשימת שירותים** — `railway service list` ייתן את הרוב, אבל יש כלים מחוץ ל-Railway? (Make/Zapier/external SaaS)
2. **Chan / אוף לו** — אישור: Chatwoot? Flowise? (סיון אמר את השמות בקול)
3. **CEO Telegram chat_id** — צריך אותו לפלואו ההתראות. אפשר לקבל מ-Jarvis bot logs.
4. **API keys למוניטורינג של Evolution** — אישור שיש לך גישה.
5. **Postgres חדש או קיים?** — האם להקים DB חדש ל-Service Registry או לעלות על Postgres קיים?

---

## נספח B — Decision Log

| החלטה | סיבה |
|-------|------|
| Service Registry ב-Postgres ולא Consul/etcd | פשוט יותר, כבר יש לו Postgres |
| Discovery library במקום service mesh מלא (Istio) | overhead מטורף, לא נחוץ ב-scale הזה |
| Self-registration ולא static config | הוספת שירות חדש לא דורשת לגעת בשירותים קיימים |
| MCP נשאר אופציה אבל לא חובה | רק לשירותי AI; לרוב לא נחוץ |
| n8n נשאר orchestrator | המשתמש רוצה visibility ושליטה |
| Watchdog קורא ל-registry, לא לרשימה hardcoded | מוסיף שירות חדש = אוטומטית מנוטר |
| **Auto-Onboarding דרך Railway webhook + polling fallback (v3)** | webhook יכול לפספס, polling קולט הכל |
| **3 Service Templates במקום 1 (v3)** | קלוד קוד יודע ש-Node ל-API services, Python ל-AI, AI-agent כשצריך agent מלא |
| **Auto-Onboarding bot שולח הודעה גם בכשל (v3)** | סיון יודע מיד אם שירות חדש שלו לא תקין, לא רק כשהוא מנסה להשתמש |
| **AI-agent template בונה tools אוטומטית מ-mesh (v3)** | סוכן AI חדש מקבל גישה לכל יכולות ה-mesh בלי קונפיגורציה |

---

**END OF HANDOFF v3**
