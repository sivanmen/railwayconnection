# railwayconnection — Sivan Mesh

מערכת אורקסטרציה שמחברת את כל 21 הפרויקטים של Sivan ב-Railway למסה אחת מנוהלת דרך n8n.

## מה זה

- **Hub יחיד:** `n8n-production-986a.up.railway.app` משמש כ-registry + orchestrator + watchdog + alert router
- **Auto-onboarding:** כל שירות חדש שעולה ל-Railway מצטרף אוטומטית ל-mesh תוך 2 דק'
- **התראות:** WhatsApp (Evolution API) + Telegram על כל כשל, עם סיבה והמלצת תיקון
- **Self-healing:** watchdog רץ כל 5 דק' ובודק `/health` של כל שירות

## ארכיטקטורה

ראה [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## שימוש מהיר

### הוספת שירות חדש למסה
1. צור repo מ-template: `templates/mesh-template-node` או `mesh-template-python`
2. עדכן `manifest.json` עם השם, capabilities, endpoints
3. Deploy ל-Railway
4. תקבל WhatsApp ✅ תוך 2 דק'

ראה [`docs/ADD_NEW_SERVICE.md`](docs/ADD_NEW_SERVICE.md).

### תקשורת בין שירותים
במקום לקרוא ישירות ל-URL של שירות אחר, קרא ל-n8n router:
```
POST https://n8n-production-986a.up.railway.app/webhook/route
{
  "from": "my-service",
  "to": "paperclip",
  "capability": "create_task",
  "params": { "title": "...", "body": "..." }
}
```

## מבנה ריפו

| תיקייה | מה בפנים |
|--------|----------|
| `docs/` | מסמכי מקור + ARCHITECTURE + RUNBOOK + ADD_NEW_SERVICE |
| `n8n_workflows/` | קבצי JSON של 7 ה-workflows שרצים ב-hub |
| `n8n_data_stores/` | סכמות של 4 ה-Data Stores |
| `templates/` | 3 starter templates לשירותים חדשים |
| `scripts/` | inventory, seed, setup, test |
| `services_inventory.json` | רשימת 21 הפרויקטים ב-Railway |

## סודות

קובץ `.secrets.local.env` (לא נכנס ל-git) — מכיל Railway/n8n/Evolution/Telegram tokens.

## RUNBOOK

מה לעשות כשמשהו נופל — ראה [`docs/RUNBOOK.md`](docs/RUNBOOK.md).
