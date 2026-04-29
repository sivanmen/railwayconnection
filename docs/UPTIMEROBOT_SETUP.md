# UptimeRobot Setup — שומר על ה-Hub

UptimeRobot הוא ה"שומר של השומר" — שירות חיצוני שמוודא ש-n8n עצמו פועל. אם n8n נופל — הוא לא יכול לשלוח לך WhatsApp שהוא נפל. זו הסיבה שצריך מעקב חיצוני.

## הקמה (5 דק')

### שלב 1 — הירשם
- כנס ל: https://uptimerobot.com/signUp
- חשבון Free (50 monitors, 5 דק' interval) — מספיק

### שלב 2 — צור Monitor
1. **+ Add New Monitor**
2. Monitor Type: **HTTP(s)**
3. Friendly Name: `n8n Hub - Sivan Mesh`
4. URL: `https://n8n-production-986a.up.railway.app/healthz`
5. Monitoring Interval: **5 minutes** (בחינם זה המקסימום)
6. שמור

### שלב 3 — הוסף Alert Contacts
1. ב-Settings → My Settings → Alert Contacts
2. **+ Add Alert Contact**
3. Type: **SMS** (Free כולל 20 בחודש)
4. Number: `+972524518134`
5. Type: **Email**
6. Email: `sivanmen@gmail.com`
7. שמור

### שלב 4 — Webhook fallback ל-WhatsApp ישיר
זה הכי חשוב — אם n8n נופל, נריץ את Evolution ישירות:

1. **+ Add Alert Contact** → Type: **Web-Hook**
2. URL to Notify:
   ```
   https://evolution-api-production-aad5.up.railway.app/message/sendText/%D7%A1%D7%99%D7%95%D7%9F%200524518134
   ```
3. POST Value (JSON):
   ```json
   {"number":"972524518134","text":"🚨 n8n Hub נפל!\n\nMonitor: *monitorFriendlyName*\nStatus: *alertType*\nReason: *alertDetails*\n\nבדוק Railway dashboard מיד."}
   ```
4. Send as JSON: **Yes**
5. Custom HTTP Headers:
   ```
   apikey: 19FB28BE4E14-4F4B-8847-109EF1F2717F
   Content-Type: application/json
   ```
6. שמור

### שלב 5 — חבר את כל ה-Alerts ל-Monitor
1. חזור ל-Monitor שיצרת ב-שלב 2
2. Edit → Alert Contacts To Notify
3. סמן: SMS, Email, Web-Hook (כולם)
4. שמור

## בדיקה

זרוק את n8n באופן זמני:
1. Railway dashboard → N8n+MCP → n8n service
2. Settings → Pause
3. תוך 5-10 דק' תקבל:
   - SMS ל-+972524518134
   - Email
   - WhatsApp (ה-fallback ישיר)
4. הפעל שוב: Resume

## תיעוד

UptimeRobot Free מוגבל ל:
- 50 monitors
- 5 דק' interval
- 20 SMS לחודש (אחרי זה רק email + webhook)

לצרכים שלך זה מספיק. אם תרצה שיחת טלפון אוטומטית במקום SMS, שדרג ל-Pro ($7/חודש).
