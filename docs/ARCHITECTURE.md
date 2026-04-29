# ARCHITECTURE — Sivan Mesh

מסמך הארכיטקטורה הרשמי של ה-mesh. מתאר איך 21 הפרויקטים ו-80 השירותים ב-Railway מחוברים דרך n8n אחד שמשמש כ-hub: registry, router, watchdog, ו-alert dispatcher במכה אחת.

מסמך זה הוא ה-source of truth לכל ההחלטות הארכיטקטוניות. אם משהו ב-codebase לא מתאים למה שכתוב כאן — המסמך נכון, הקוד שגוי.

---

## 1. תרשים על

```
                        ┌─────────────────────────────────────────────┐
                        │   n8n Hub  (Railway: n8n-production-986a)   │
                        │   https://n8n-production-986a.up.railway.app │
                        │                                             │
                        │  ┌────────────────────────────────────────┐ │
                        │  │  Data Tables (Postgres-backed)         │ │
                        │  │  - services_registry                   │ │
                        │  │  - incident_state                      │ │
                        │  │  - onboarding_history                  │ │
                        │  │  - idle_services                       │ │
                        │  └────────────────────────────────────────┘ │
                        │                                             │
                        │  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
                        │  │ 00 reg   │ │ 01 route │ │ 02 onboard │  │
                        │  └──────────┘ └──────────┘ └────────────┘  │
                        │  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
                        │  │ 03 watch │ │ 04 alert │ │ 99 errors  │  │
                        │  └──────────┘ └──────────┘ └────────────┘  │
                        └──────┬───────────────┬───────────────┬─────┘
                               │               │               │
              register/route   │   ping /health│   alerts out  │
                               │               │               │
        ┌──────────────────────┼───────────────┼───────────────┘
        │                      │               │
        ▼                      ▼               ▼
   ┌─────────┐          ┌─────────────┐  ┌──────────────┐  ┌──────────┐
   │ Service │          │   Service   │  │  Evolution   │  │ Telegram │
   │   A     │ ◀──────▶ │      B      │  │ (WhatsApp)   │  │  (Bot)   │
   │ /health │          │  /manifest  │  │ +972524568134│  │  CEO chat│
   │/manifest│          │   /health   │  └──────────────┘  └──────────┘
   └─────────┘          └─────────────┘
        ▲
        │
   ┌────┴────────────────────────────────────────┐
   │  21 Railway projects · 80 services          │
   │  (Paperclip, Dify, Evolution, Jarvis, ...)  │
   └─────────────────────────────────────────────┘
```

---

## 2. למה n8n כ-hub ולא Service Registry נפרד

הגרסאות המוקדמות (v1, v2 ב-handoff) הציעו שירות `service-registry` נפרד ב-Node+Postgres. ויתרנו על זה. הסיבות:

| שיקול | Service Registry נפרד | n8n כ-hub |
|-------|----------------------|-----------|
| תחזוקה | עוד שירות לתחזק, לעדכן, לפרוס | n8n כבר רץ ומתוחזק |
| Visibility | logs ב-Railway בלבד | כל execution נראה ב-UI |
| State store | צריך להקים Postgres + schema migrations | n8n Data Tables מובנות |
| HTTP routing | לכתוב Express + middleware | Webhook node מוכן |
| Alerts | לכתוב integration ל-Evolution + Telegram | nodes קיימים |
| Operational SPOF | 2 SPOFs (registry + n8n) | SPOF אחד (n8n) |

המחיר: n8n מקבל אחריות נוספת ועלול להיכשל יותר. את זה מטפלים עם UptimeRobot חיצוני שמנטר את n8n עצמו (ראה סעיף 6).

---

## 3. שישה Workflows — תפקיד מלא

כל ה-workflows חיים תחת n8n project `2b67xU5hnff91Quq` בקבצי JSON ב-`n8n_workflows/` ברפו.

### 3.1 `00_register.json`

| מאפיין | ערך |
|--------|-----|
| Trigger | `POST /webhook/mesh-register` |
| תפקיד | קבלת manifest משירות חדש ורישום ב-Data Table |
| Input | JSON manifest (ראה סעיף 4 ב-handoff) |
| Output | `{ status: "registered", service_id: "..." }` |
| Downstream | מפעיל את `04_alert_router` עם `event=service_joined` |

הזרימה: validate manifest → upsert ל-`services_registry` (table `gZRuzAmWa9sNwGc6`) → שליחת אישור WhatsApp.

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-register \
  -H 'Content-Type: application/json' \
  -d @manifest.json
```

### 3.2 `01_route.json`

| מאפיין | ערך |
|--------|-----|
| Trigger | `POST /webhook/mesh-route` |
| תפקיד | router בין שירותים. שירות A מבקש ש-B יבצע capability |
| Input | `{ from, to, capability, params }` |
| Output | התשובה משירות היעד |
| Downstream | קריאה ל-`internal_url` של שירות היעד; logging ל-execution history |

יתרון: שירותים לא צריכים לדעת URLs של שירותים אחרים. רק קוראים ל-router. אם שירות זז, רק ה-registry מתעדכן.

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-route \
  -H 'Content-Type: application/json' \
  -d '{
    "from": "jarvis",
    "to": "paperclip",
    "capability": "create_task",
    "params": { "title": "test", "body": "..." }
  }'
```

### 3.3 `02_onboarding.json`

| מאפיין | ערך |
|--------|-----|
| Trigger | `POST /webhook/railway-event` (כרגע disabled) |
| תפקיד | זיהוי שירות חדש שעלה ל-Railway והכנסתו ל-mesh |
| Input | Railway webhook payload (`service.created` / `deployment.success`) |
| Output | רישום או הודעת שגיאה |
| Downstream | קורא ל-`00_register` עם manifest שנשאב מ-`/manifest`; כותב ל-`onboarding_history` (`DrZgGZwusgtdaw15`); שירותים שלא מגיבים נכנסים ל-`idle_services` (`0lrRutLikjTH1SPj`) |

הזרימה: wait 90s לעלייה → `GET internal_url/manifest` → validate → register או alert. כרגע ה-trigger מנותק עד שיוגדרו Railway project webhooks.

### 3.4 `03_watchdog.json`

| מאפיין | ערך |
|--------|-----|
| Trigger | Cron כל 5 דקות |
| תפקיד | בדיקת `/health` של כל השירותים ה-active |
| Input | (אין — קורא ל-`services_registry`) |
| Output | עדכון `last_health_status`, `last_seen_at` |
| Downstream | מפעיל את `04_alert_router` רק אם יש transition (healthy→down או down→healthy) |

### 3.5 `04_alert_router.json`

| מאפיין | ערך |
|--------|-----|
| Trigger | `POST /webhook/mesh-alert` (גם פנימי וגם חיצוני) |
| תפקיד | dedup, classify, ושליחת התראות ל-WhatsApp + Telegram |
| Input | `{ service, severity, classification, error_text, status_code }` |
| Output | `{ sent: true, incident_id: "..." }` או `{ sent: false, reason: "deduped" }` |
| Downstream | Evolution API (WhatsApp ל-972524568134); Telegram bot (CEO chat); כתיבה ל-`incident_state` (`IHRBBzaEkfrLOxJ9`) |

### 3.6 `99_error_handler.json`

| מאפיין | ערך |
|--------|-----|
| Trigger | n8n Error Trigger (default error workflow) |
| תפקיד | תפיסת כשלים מכל workflow אחר |
| Input | `{ workflow, execution, error }` |
| Output | התראת WhatsApp+Telegram עם stack trace חתוך |
| Downstream | `04_alert_router` עם severity=critical |

---

## 4. ארבע Data Tables — סכמה ושימוש

הטבלאות הן n8n Data Tables תחת project `2b67xU5hnff91Quq`. לא Postgres ישיר — הגישה דרך n8n REST API.

### 4.1 `services_registry` — `gZRuzAmWa9sNwGc6`

המקור היחיד לאמת על מי במסה.

| עמודה | טיפוס | תיאור |
|-------|-------|-------|
| `name` | string (unique) | מזהה שירות, lowercase + מקפים |
| `display_name` | string | שם קריא |
| `category` | string | orchestration / ai / task / comms / data |
| `internal_url` | string | `http://x.railway.internal:PORT` |
| `public_url` | string \| null | URL ציבורי אם יש |
| `capabilities` | json | מערך של capability strings |
| `endpoints` | json | מיפוי `capability → {method, path, schema}` |
| `auth_type` | string | bearer / api_key / oauth / none |
| `auth_secret_env_var` | string | שם env var (לא הסוד עצמו) |
| `status` | string | active / maintenance / deprecated |
| `version` | string | semver |
| `last_seen_at` | timestamp | עדכון מ-watchdog/heartbeat |
| `last_health_status` | string | healthy / degraded / down |

Retention: ללא תפוגה. שירות שנמחק → `status='deprecated'`, נשמר לצרכי היסטוריה.

### 4.2 `incident_state` — `IHRBBzaEkfrLOxJ9`

State machine ל-deduplication של התראות.

| עמודה | טיפוס | תיאור |
|-------|-------|-------|
| `incident_key` | string | `{service}_{classification}` |
| `service` | string | |
| `classification` | string | unreachable / server_error / rate_limited / slow_response |
| `severity` | string | critical / high / medium / low |
| `opened_at` | timestamp | |
| `last_alerted_at` | timestamp | |
| `alert_count` | int | |
| `status` | string | open / resolved |
| `resolved_at` | timestamp | |

Retention: רשומות `resolved` נשמרות 30 יום לתחקור, אחר כך נמחקות (manual cleanup).

### 4.3 `onboarding_history` — `DrZgGZwusgtdaw15`

לוג של כל ניסיון onboarding.

| עמודה | טיפוס | תיאור |
|-------|-------|-------|
| `service_name` | string | |
| `attempted_at` | timestamp | |
| `outcome` | string | success / invalid_manifest / no_response |
| `errors` | json | רשימת validation errors |
| `manifest_snapshot` | json | מה שחזר מ-`/manifest` |

Retention: 90 יום.

### 4.4 `idle_services` — `0lrRutLikjTH1SPj`

שירותים שזוהו אבל לא הצטרפו (DBs, Redis, etc). ה-watchdog לא מתריע עליהם.

| עמודה | טיפוס | תיאור |
|-------|-------|-------|
| `service_id` | string | Railway service ID |
| `service_name` | string | |
| `project_name` | string | |
| `reason` | string | no_manifest / not_http / db_service |
| `marked_at` | timestamp | |

Retention: ללא תפוגה.

---

## 5. Alert Dedup דרך `last_health_status` Transition Tracking

הבעיה: watchdog רץ כל 5 דקות. אם שירות down — אנחנו לא רוצים WhatsApp כל 5 דקות.

הפתרון: לכל שירות ב-`services_registry` יש עמודה `last_health_status`. אחרי כל ping, ה-watchdog משווה:

```
prev_status = registry.last_health_status
new_status  = result of /health probe (healthy | degraded | down)

if prev_status == new_status:
    UPDATE last_seen_at  (אבל לא שולחים alert)
elif prev_status == 'healthy' AND new_status == 'down':
    -> trigger 04_alert_router with severity based on classification
    -> open incident in incident_state
elif prev_status == 'down' AND new_status == 'healthy':
    -> trigger 04_alert_router with type='recovery'
    -> resolve incident
```

שכבת dedup שנייה: גם אם transition קורה — `04_alert_router` בודק ב-`incident_state` אם יש incident open עם אותו `incident_key` שנפתח לפני פחות מ-30 דקות. אם כן, רק מעלה את `alert_count` בלי לשלוח שוב.

זה מבטיח: alert ראשון מיידי, recovery message מיידי, בין לבין שקט.

---

## 6. מה לא נמצא ב-mesh

לא כל מה שרץ ב-Railway צריך להיות חלק מה-mesh. כללים:

| סוג שירות | האם ב-mesh? | למה |
|-----------|-------------|-----|
| Postgres / MySQL | לא | אין `/health` HTTP, נכנס ל-`idle_services` |
| Redis / Memcached | לא | אותה סיבה |
| MinIO / S3 storage | לא | לא מבצע capabilities עסקיות |
| Worker queues (BullMQ workers) | לא | נצרכים דרך השירות שמחזיק את ה-API |
| Frontends סטטיים בלבד | לא | אין מה לקרוא להם |
| Cron jobs ללא HTTP | לא | אין endpoint לdiscovery |

זה בכוונה. ה-mesh הוא שכבת **תקשורת בין שירותים**, לא inventory של תשתית. תשתית גלויה ב-Railway dashboard.

רשימת ה-idle_services נטענת ידנית או דרך `02_onboarding` כשהוא מזהה שירות בלי `/manifest`. ראה `services_inventory.json` ברפו לרשימה המלאה של 80 השירותים — חלק גדול מהם DBs/Redis ולא יהיו ב-registry.

---

## 7. Failure Modes

### 7.1 n8n נופל

**השפעה:** כל ה-mesh משותק. אין routing, אין watchdog, אין alerts.

**זיהוי:** UptimeRobot חיצוני מבצע ping ל-`https://n8n-production-986a.up.railway.app/healthz` כל 2 דקות. אם נכשל — שולח SMS לסיון + email.

**Recovery:** ידני. בדוק Railway dashboard, restart השירות. workflows יעלו אוטומטית כשn8n חוזר.

**הקלה:** שירותים שמשתמשים ב-router (`01_route`) צריכים timeout קצר (30s) ולוגיקת fallback. אבל אין mitigation אמיתי — n8n הוא SPOF מתוכנן.

### 7.2 Evolution API נופל

**השפעה:** אין WhatsApp. Telegram עדיין עובד.

**זיהוי:** `04_alert_router` רואה HTTP error מ-Evolution. שולח רק Telegram עם prefix `[WhatsApp DOWN]`.

**Recovery:** Evolution רץ תחת project `Evolution API - Social M SYSTEM` (id `08ae6d8b-972a-4deb-be32-36a670938a84`). restart ב-Railway dashboard.

### 7.3 שירות בודד נופל

**השפעה:** רק יכולות אותו שירות לא זמינות. כל השאר ממשיך.

**זיהוי:** `03_watchdog` בתוך 5 דקות. WhatsApp+Telegram עם classification ו-suggested fix.

**Recovery:** לפי ה-suggested fix בהודעה. בדרך כלל `railway logs` + restart.

### 7.4 n8n Data Table corruption / loss

**השפעה:** registry ריק, שירותים צריכים להירשם מחדש.

**Recovery:** הרץ `scripts/seed_registry.sh` כדי לאכלס מ-`services_inventory.json`. כל שירות שהוקם מ-template יירשם מחדש בעלייה הבאה.

### 7.5 Railway webhook לא מגיע (`02_onboarding`)

**השפעה:** שירות חדש לא מצטרף אוטומטית.

**Recovery:** קריאה ידנית ל-`POST /webhook/mesh-register` עם ה-manifest. ראה `ADD_NEW_SERVICE.md`.

---

## 8. הפניות נוספות

- `RUNBOOK.md` — מה לעשות כשמשהו נשבר
- `ADD_NEW_SERVICE.md` — איך להוסיף שירות חדש
- `CLAUDE_CODE_HANDOFF_v3.md` — הספק המקורי
- `services_inventory.json` — רשימת 21 פרויקטים ו-80 שירותים
- `n8n_data_stores/table_ids.json` — IDs של 4 הטבלאות
- `n8n_workflows/*.json` — קבצי המקור של 6 ה-workflows
