# Brain Bridge — راهنمای فارسی نسخهٔ ۰٫۱

**نسخهٔ اولیه و رایگان برای ویندوز؛ هنوز پلاگین رسمی Obsidian نیست.**

این پروژه اجرای ارتباط میان Obsidian MCP Connector و ابزار رسمی OpenAI Tunnel را ساده می‌کند. اطلاعات هر کاربر محلی می‌ماند و هر شخص باید کلید و Tunnel خودش را داشته باشد.

## پیش‌نیازها

- نصب Obsidian و پلاگین MCP Connector
- آدرس **مستقیم** MCP، مانند `http://127.0.0.1:27200/mcp`، نه آدرس Broker مخصوص Codex
- توکن مربوط به همان Vault از Access Control
- `tunnel-client.exe` رسمی OpenAI
- شناسهٔ Tunnel و کلید Runtime محدود با مجوزهای Tunnels Read + Use

## نصب

بسته را خارج از پوشه Vault استخراج و PowerShell را در ریشهٔ آن باز کنید:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-BrainBridge.ps1 -EnableAutoStart
```

آدرس اجرایی، شناسه Tunnel و URL محلی را وارد کنید. کلیدها با ورودی مخفی دریافت و با Windows DPAPI برای همان کاربر رمزگذاری می‌شوند. **کلیدها را در چت یا تصویر نفرستید.**

پس از نصب:

```powershell
& "$env:LOCALAPPDATA\BrainBridge\Status-BrainBridge.ps1" -CheckOpenAI
Start-Process wscript.exe -ArgumentList ('"' + $env:LOCALAPPDATA + '\BrainBridge\Run-Hidden.vbs"')
```

در قسمت Plugins چت‌جی‌پی‌تی، Custom MCP را با Tunnel اختصاصی خود ثبت کنید.

## محدودیت‌ها

- این راه‌انداز ویندوزی، **یک سرور جدید MCP یا پلاگین Obsidian نیست**.
- بدون اجرای Obsidian و ویندوز، اتصال برقرار نخواهد بود.
- این نسخه فقط **یک Tunnel و یک MCP endpoint** دارد.
- Claude، Codex و سایر مدل‌ها در این نسخه خودکار متصل نمی‌شوند.
- اجرای مخفی به‌معنای افزایش امنیت یا محدودسازی دسترسی نیست.
- برای اولین آزمایش، دسترسی‌های Read/Search را ترجیح دهید.

## تشخیص خطای 401

دو منبع جدا وجود دارد: ردشدن کلید Runtime از سمت OpenAI، یا ردشدن توکن MCP از سمت Obsidian. یکی را برای رفع مشکل دیگری تعویض نکنید.

## توقف و حذف اجرای خودکار

```powershell
& "$env:LOCALAPPDATA\BrainBridge\Stop-BrainBridge.ps1"
& "$env:LOCALAPPDATA\BrainBridge\Remove-BrainBridge.ps1"
```

فایل‌های رمزگذاری‌شده فقط برای همان کاربر ویندوز قابل بازیابی‌اند. اجرای این نسخه روی دستگاه مستقل هنوز آزمایش نهایی نشده است.
