# RUNBOOK — Sivan Mesh

מסמך תפעול. למה לעשות כש-pager צלצל, איך מוסיפים ומסירים שירותים, איך משתיקים alerts לתחזוקה, ואיך מחליפים מפתחות. שמור אותו פתוח כשאתה on-call.

Hub: `https://n8n-production-986a.up.railway.app`

טבלאות:
- `services_registry` — `gZRuzAmWa9sNwGc6`
- `incident_state` — `IHRBBzaEkfrLOxJ9`
- `onboarding_history` — `DrZgGZwusgtdaw15`
- `idle_services` — `0lrRutLikjTH1SPj`

---

## 1. כשמגיע WhatsApp עם 🚨

הודעת alert נראית ככה:

```
🚨 התראת מערכת — Sivan Stack
שירות: paperclip
חומרה: 🔴 קריטי
זמן: 14:32 IL
מה קרה: connection timeout after 30s
המלצה לתיקון: railway logs --service=paperclip --tail=100
Incident ID: 7f3a2b1c
```

**שלב 1 — תוך 60 שניות, אשר שראית.** השב WhatsApp `ack 7f3a2b1c` (אם יש Jarvis bot שתופס) או פשוט סמן לעצמך. זה לא עוצר התראות — זה רק רישום.

**שלב 2 — קרא את `המלצה לתיקון`.** היא לא רנדומלית. ה-classifier ב-`03_watchdog` בחר אותה לפי סוג השגיאה.

| Classification | סיבה אופיינית | מה לעשות |
|----------------|---------------|----------|
| `unreachable` | קונטיינר נפל / Railway issue | בדוק Railway dashboard. אם הקונטיינר חי, בדוק לוגים. |
| `server_error` (5xx) | bug / DB connection | `railway logs --service=X --tail=100`, חפש stack trace |
| `rate_limited` (429) | upstream limit / DDoS | בדוק traffic, העלה tier אם צריך |
| `slow_response` | DB עומס / GC pause | בדוק metrics ב-Railway, בדוק slow query log |

**שלב 3 — אם לא הצלחת תוך 15 דק':** הפעל maintenance mode (סעיף 6) כדי לעצור את ה-noise בזמן שאתה חוקר לעומק.

**שלב 4 — recovery יגיע אוטומטית.** כשה-watchdog רואה `/health` שחוזר 200, תקבל:

```
✅ שירות חזר לפעולה — paperclip
משך השבתה: 23 דק'
```

אם לא הגיע recovery תוך 5 דק' מהתיקון — בדוק שה-watchdog רץ:

```bash
curl https://n8n-production-986a.up.railway.app/api/v1/executions?workflowId=03_watchdog&limit=5
```

---

## 2. כשמגיע WhatsApp עם 🟠 onboarding_failed

זה אומר ששירות חדש זוהה ב-Railway אבל לא הצליח להצטרף ל-mesh. ההודעה תפרט את השלב שנכשל.

### 2.1 דיאגנוסטיקה צעד-צעד

```bash
# A. ודא שהשירות באמת רץ
curl -i https://<service>-production.up.railway.app/health
# אם 5xx או timeout -> deployment problem, בדוק ב-Railway

# B. בדוק שהוא חושף manifest
curl -i https://<service>-production.up.railway.app/manifest
# אם 404 -> השירות לא mesh-compliant. ראה ADD_NEW_SERVICE.md סעיף B

# C. בדוק את התשובה של manifest
curl https://<service>-production.up.railway.app/manifest | jq
# ודא שיש: name, version, category, internal_url, capabilities, endpoints

# D. בדוק ב-onboarding_history מה היו הסיבות
curl -X GET "https://n8n-production-986a.up.railway.app/api/v1/data-tables/DrZgGZwusgtdaw15/rows?filter=service_name:<name>" \
  -H "X-N8N-API-KEY: $N8N_API_KEY"
```

### 2.2 תיקונים נפוצים

| Validation error | תיקון |
|------------------|-------|
| `name חייב להיות lowercase + מקפים` | תקן `name` ב-manifest, redeploy |
| `internal_url לא Railway internal` | השתמש ב-`http://X.railway.internal:PORT` ולא ב-public URL |
| `capability X מוצהר אבל אין לו endpoint` | הוסף ל-`endpoints[X]` או הסר מ-`capabilities` |
| `endpoints חסר` | הוסף לפחות mapping אחד |

### 2.3 אחרי תיקון — register ידני

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-register \
  -H 'Content-Type: application/json' \
  -d "$(curl -s https://<service>-production.up.railway.app/manifest)"
```

---

## 3. כש-n8n עצמו נופל

ה-pager שלך הוא **UptimeRobot** — לא ה-mesh. כשn8n נופל, ה-mesh כולו שותק וגם ה-alerter שלו.

### 3.1 איך תזהה

- SMS מ-UptimeRobot ל-`+972524568134`: `Monitor n8n-mesh is DOWN`
- Email מ-UptimeRobot
- WhatsApp לא מגיע (זה הסימן)

### 3.2 שלבי recovery

```bash
# 1. בדוק Railway dashboard
open https://railway.app/project/2b67xU5hnff91Quq

# 2. בדוק את service status ולוגים אחרונים
railway logs --service=n8n --tail=200

# 3. סיבות נפוצות:
#    - OOM kill (היה memory spike) -> restart
#    - DB connection lost -> בדוק את Postgres של n8n
#    - Disk full -> נקה /data/cache או הגדל volume

# 4. restart
railway service restart --service=n8n
```

### 3.3 verify אחרי recovery

```bash
curl https://n8n-production-986a.up.railway.app/healthz
# צריך 200 OK

# ודא שכל ה-active workflows עלו
curl https://n8n-production-986a.up.railway.app/api/v1/workflows?active=true \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq '.data | length'
# צריך להחזיר לפחות 5 (00, 01, 03, 04, 99)
```

---

## 4. איך להוסיף שירות חדש

ראה [`ADD_NEW_SERVICE.md`](ADD_NEW_SERVICE.md) — שלוש גישות (template, existing, 3rd-party) עם דוגמאות.

המקרה הקצר: deploy מ-`templates/mesh-template-node` או `mesh-template-python`, עדכן `manifest.js`, push ל-Railway, חכה 2 דקות ל-WhatsApp ✅.

---

## 5. איך להסיר שירות

### 5.1 מה-registry בלבד (נשאר ב-Railway)

```bash
# 1. מצא את ה-row id
curl -X GET "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows?filter=name:my-service" \
  -H "X-N8N-API-KEY: $N8N_API_KEY"

# 2. מחק לפי id
curl -X DELETE "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows/<row_id>" \
  -H "X-N8N-API-KEY: $N8N_API_KEY"
```

### 5.2 גם מ-Railway

```bash
# 1. הסר מה-mesh קודם (5.1)
# 2. מחק מ-Railway dashboard
# 3. סגור פתוח incidents ב-incident_state אם יש
curl -X GET "https://n8n-production-986a.up.railway.app/api/v1/data-tables/IHRBBzaEkfrLOxJ9/rows?filter=service:my-service,status:open" \
  -H "X-N8N-API-KEY: $N8N_API_KEY"
# מחק לפי row id כמו ב-5.1
```

### 5.3 Soft delete (מומלץ)

במקום DELETE, עדכן `status` ל-`deprecated`. שומר היסטוריה, מסיר מ-routing.

```bash
curl -X PATCH "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows/<row_id>" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"status": "deprecated"}'
```

---

## 6. השתקת alerts לתחזוקה

לפני deploy / DB migration / שינוי מבני — סמן את השירות כ-`maintenance` ב-registry. ה-watchdog ידלג.

```bash
# כניסה ל-maintenance
curl -X PATCH "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows/<row_id>" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"status": "maintenance"}'

# עשה את העבודה...

# יציאה מ-maintenance
curl -X PATCH "https://n8n-production-986a.up.railway.app/api/v1/data-tables/gZRuzAmWa9sNwGc6/rows/<row_id>" \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"status": "active"}'
```

**לא לשכוח** להחזיר ל-`active`. אחרת השירות לא ינוטר.

טיפ: הוסף תזכורת קלנדר אם המשך התחזוקה > שעה.

---

## 7. החלפת n8n API key

ה-key מופיע hardcoded ב-workflow JSONs (כל קריאה פנימית של workflow ל-API של n8n דורשת אותו). לכן rotation דורש כמה צעדים.

### 7.1 צור key חדש

1. n8n UI → Settings → API → Create new
2. שמור את הערך החדש בצד

### 7.2 עדכן בכל workflow

```bash
cd /Users/sivanmenahem/Documents/railwayconnection/n8n_workflows

# מצא את כל המקומות שבהם ה-key הישן מופיע
grep -l "<OLD_KEY_PREFIX>" *.json

# עבור כל קובץ, החלף עם sed (זהירות!)
for f in $(grep -l "<OLD_KEY>" *.json); do
  sed -i.bak "s|<OLD_KEY>|<NEW_KEY>|g" "$f"
done

# ודא שאין יותר מופעים
grep "<OLD_KEY>" *.json
```

### 7.3 העלה לכל ה-workflows ב-n8n

```bash
for f in *.json; do
  curl -X PUT "https://n8n-production-986a.up.railway.app/api/v1/workflows/$(jq -r .id $f)" \
    -H "X-N8N-API-KEY: <NEW_KEY>" \
    -H 'Content-Type: application/json' \
    -d @"$f"
done
```

### 7.4 בטל את ה-key הישן

n8n UI → Settings → API → revoke old.

### 7.5 verify

```bash
curl -X POST https://n8n-production-986a.up.railway.app/webhook/mesh-route \
  -H 'Content-Type: application/json' \
  -d '{"from":"runbook","to":"paperclip","capability":"list_agents","params":{}}'
```

אם זה עובד — ה-rotation הצליח.

---

## 8. שגיאות נפוצות

| הודעת שגיאה | סיבה | תיקון |
|-------------|------|-------|
| `ECONNREFUSED <service>.railway.internal:PORT` | השירות down או PORT שגוי ב-manifest | restart שירות, ודא PORT תואם |
| `manifest validation failed: name` | `name` עם רווחים/uppercase | תקן ל-`my-service-name` |
| `webhook not registered` ב-n8n | ה-workflow לא activated | activate ב-UI או POST ל-`/api/v1/workflows/X/activate` |
| `incident already open within 30min` | dedup window | הוא בכוונה, חכה או resolve ידנית |
| `Evolution API timeout` | Evolution down | בדוק Evolution service, Telegram יקבל לבד |
| `429 Too Many Requests` מ-Evolution | יותר מדי alerts | בדוק לולאת alert (תקלה ב-classifier?) |
| `data-table not found` | שגוי table id | ודא מול `n8n_data_stores/table_ids.json` |
| `unauthorized` ב-API call ל-n8n | API key פג / שגוי | rotate (סעיף 7) |
| `last_seen_at older than 30min` | heartbeat לא רץ בשירות | בדוק שה-template loop פעיל |
| `idle service triggering alerts` | הוא ב-`services_registry` במקום `idle_services` | העבר טבלה |

---

## 9. הפניות

- ארכיטקטורה מלאה: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- הוספת שירות: [`ADD_NEW_SERVICE.md`](ADD_NEW_SERVICE.md)
- ספק מקור: [`CLAUDE_CODE_HANDOFF_v3.md`](CLAUDE_CODE_HANDOFF_v3.md)
- inventory: `services_inventory.json` (root)
- workflows source: `n8n_workflows/`
- scripts: `scripts/seed_registry.sh`, `scripts/inventory_railway.sh`, `scripts/deploy_workflow.sh`
