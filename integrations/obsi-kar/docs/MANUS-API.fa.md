# راه‌اندازی Manus و Manus API برای ObSi KAR

**وضعیت:** راهنمای اتصال و کلاینت نمونه؛ سرور ObSi KAR، URL عمومی و اتصال زنده با این فایل ایجاد نمی‌شوند.

## سه چیز متفاوت را یکی نگیریم

1. **Custom MCP در حساب Manus** اتصال MCP حساب را به یک Adapter مجاز ObSi KAR برقرار می‌کند. برای هر Producer باید هویت و Token محدود خودش استفاده شود.
2. **Manus API v2** به برنامهٔ شما امکان می‌دهد با کلید API یا OAuth، تسک بسازد و اجرا را پیگیری کند. کلید Manus API مجوز خواندن Vault نیست.
3. **ObSi KAR API / Token** رابط دادهٔ خود سامانه است. این Token باید به `producer_id`، پروژه‌ها و Scopeهای تأییدشده محدود شود. آن را نه در Manus API بگذارید و نه به‌عنوان کلید Manus استفاده کنید.

مسیر داده چنین است: Manus → اتصال Custom MCP احراز‌شده → Adapter مجاز → همان صف/اعتبارسنج/آرشیو ObSi KAR → Writer کنترل‌شدهٔ موجود → Vault. این بسته فقط قرارداد، کلاینت انتقال و مثال API را فراهم می‌کند؛ Adapter و Writer اجرایی را نصب نمی‌کند.

## بخش اول: اضافه‌کردن Custom MCP به حساب Manus

این بخش را Owner سامانه پس از آماده‌شدن Adapter اجرا می‌کند:

1. مطمئن شوید Adapter واقعی و قابل‌دسترسی از Manus آماده است. نشانی باید HTTPS معتبر داشته باشد و فقط MCP Adapter محدود ObSi KAR را ارائه کند؛ نشانی `localhost`، `127.0.0.1` یا مسیر `C:\...` از Sandbox ابری قابل‌دسترسی فرض نمی‌شود.
2. در حساب Manus، صفحهٔ اتصال‌ها/Integrations را باز کنید و گزینهٔ افزودن Custom MCP را در رابط واقعی همان حساب پیدا کنید. عنوان منو ممکن است تغییر کند.
3. یک اتصال با نامی مانند `ObSi KAR — Manus` بسازید و URL واقعی MCP را وارد کنید. احراز هویت را با روش پشتیبانی‌شدهٔ همان رابط تنظیم کنید. از Token اختصاصی Producer منوس استفاده کنید؛ نه کلید اصلی REST، نه Token تونل OpenAI و نه Token پلتفرم دیگری.
4. از رابط Manus، اتصال را آزمایش کنید و Tool Discovery را ببینید. انتظار می‌رود فقط ابزارهای محدود و واقعیِ منتشرشده توسط Adapter را مشاهده کنید. اگر اتصال/ابزار دیده نمی‌شود، ثبت آن را موفق اعلام نکنید.
5. در آزمون نخست، یک سند غیرحساس و مجاز بخوانید و سپس بسته‌ای ساختگی و چندفرمتی را بفرستید. Hash هر عضو را با اصل مقایسه و رسید را جداگانه برای `received`، استخراج، نمایه‌سازی و `processed` بررسی کنید.

اگر Adapter یا URL آماده نیست، وضعیت دقیق `blocked_endpoint_not_provisioned` است. افزودن متن راهنما، نصب Skill یا راه‌اندازی تونل ChatGPT جایگزین این پیش‌نیاز نیست. اسناد Manus پشتیبانی از Custom MCP میزبانی‌شده را توضیح می‌دهند؛ قابلیت و گزینه‌های حساب واقعی را هنگام راه‌اندازی بررسی کنید [S1].

## بخش دوم: انتخاب اتصال در Manus API v2

برای API Task، ابتدا Custom MCP را در حساب Manus مجاز/نصب کنید. سپس با همان حساب و اعتبار API مجاز، `GET https://api.manus.ai/v2/connector.list` را صدا بزنید. پاسخ، اتصال‌های نصب‌شده را برمی‌گرداند؛ اتصال سفارشی MCP با `type: "mcp"` مشخص می‌شود. UUID را از پاسخ همان حساب بگیرید؛ هیچ UUID نمونه یا شناسه‌ای از حساب دیگری را hard-code نکنید [S10] [S11].

در `POST https://api.manus.ai/v2/task.create`، شناسهٔ اتصال را داخل `message.connectors` بفرستید. وقتی فهرست غیرخالی است، همان اتصال‌ها برای Task انتخاب می‌شوند. اگر Connector نصب‌شده نباشد یا مجوز API کافی نباشد، درخواست رد می‌شود. API key را در Header `x-manus-api-key` بفرستید؛ برای OAuth از `Authorization: Bearer …` استفاده می‌شود. این کلید فقط برای Manus API است و جایگزین Credential سمت ObSi KAR نیست [S10] [S12].

نمونهٔ بدنهٔ درخواست؛ مقدار شناسه صرفاً جای‌نگهدار است:

```json
{
  "message": {
    "content": "در پروژهٔ مجاز، یک یادداشت غیرحساس را با ابزار ObSi KAR جست‌وجو و بخوان. هیچ محتوای خارج از Scope را فاش نکن.",
    "connectors": ["<connector-uuid-from-connector.list>"]
  }
}
```

برای ساختن یک Task به‌صورت برنامه‌ای، نمونهٔ استانداردکتابخانهٔ Python در [`examples/manus_api_task.py`](../examples/manus_api_task.py) ابتدا Connector را به‌صورت پویا پیدا می‌کند و سپس `task.create` را فراخوانی می‌کند:

```powershell
# MANUS_API_KEY را از Secret Store/مدیر رمز همان محیط به فرایند بدهید؛ مقدار واقعی را در تاریخچهٔ PowerShell ننویسید.
python examples/manus_api_task.py --prompt-file .\approved-task.txt
```

نمونه فقط Task را ایجاد می‌کند و `task_id` را برمی‌گرداند. برای دریافت خروجی از `task.listMessages` استفاده کنید و وضعیت را با `task.detail` بررسی کنید. Task ممکن است پس از توقف Agent هنوز کار پس‌زمینه داشته باشد؛ اگر وضعیت کار پس‌زمینه نامعلوم یا فعال است، نتیجه را کامل اعلام نکنید. در درخواست follow-up به `task.sendMessage` اگر فیلد `message.connectors` حذف شود، اتصال‌های همان Task حفظ می‌شوند؛ برای عوض‌کردن یا پاک‌کردن آن‌ها قواعد جداگانهٔ API را رعایت کنید [S13].

## بخش سوم: خواندن دانش از Obsidian

اتصال MCP باید فقط ابزارهای scoped مانند `obsi_capabilities`، `obsi_search` و `obsi_read` را ارائه کند. ابتدا Scopeهای مجاز را دریافت کنید؛ جست‌وجو، شمارش، snippet و Read همگی باید پس از اعمال Scope انجام شوند. Read باید با شناسهٔ نتیجهٔ مجاز انجام شود، نه مسیر دلخواه فایل یا Vault. پاسخ باید منبع، نسخه/Hash، زمان مشاهده و مرز/ادامهٔ متن را مشخص کند. محتوای بریده را کامل معرفی نکنید.

مجوز نوشتن در Inbox به معنی مجوز خواندن کل Vault یا آرشیو خصوصی دیگر پلتفرم‌ها نیست. Scope پیش‌فرض Producer تازه خالی بماند تا Owner یک پروژهٔ مشخص را صریحاً مجاز کند. محتوای خصوصی با خواندن از Obsidian به سرویس ابری Manus فرستاده می‌شود؛ پیش از آن دامنهٔ داده و رضایت/مجوز لازم را تأیید کنید.

## بخش چهارم: تحویل فایل‌ها و دریافت رسید

فایل‌ها و پوشه‌ها را از Manus به API خود Manus به‌عنوان جایگزین Gateway نفرستید. برای تحویل به ObSi KAR، Adapter باید قرارداد `docs/TRANSPORT.md` را در همان Helper/Worker موجود پیاده کند. برای هر ارسال، Manifest و SHA-256 بسازید، اندازه و سقف واقعی را از Capabilities بخوانید، Reservation بگیرید، بایت‌های همهٔ فایل‌ها را قطعه‌ای و قابل Resume بفرستید، سپس پس از تأیید Hash کامل Commit کنید و رسید نهایی را بخوانید.

ZIP اصلی را بازنویسی/استخراج نکنید؛ پوشهٔ بدون ZIP هم ورودی معتبر است. نام و مسیر نسبی، بایت اصل و پیوند فایل‌های همراه باید حفظ شوند. گزارش یا README به‌تنهایی معادل تحویل مجموعه نیست. ابزار `tools/obsi_client.py` به قرارداد پیشنهادی همین بسته وصل است، نه به سرور واقعی نصب‌شده؛ از آن فقط پس از استقرار Adapter استفاده کنید. اندازهٔ بزرگ واقعی را جداگانه آزمایش کنید؛ قبولی Fixture کوچک ظرفیت حجیم را ثابت نمی‌کند.

برای Taskهای Manus، API مربوط به ساخت Task فقط هماهنگی اجرای Agent است؛ جابه‌جایی باینری بزرگ باید بین کلاینت انتقال و Adapter مجاز انجام شود. هرگز Token درگاه را در prompt، کد، URL، API key Manus، لاگ یا Git قرار ندهید.

## مسیرهای مستقل ChatGPT، Manus و سایر کانال‌ها

هویت ارسال‌کننده باید از Credential احرازشده تعیین شود. شناسهٔ کانال پیشنهادی و namespaceهای مستقل عبارت‌اند از:

```text
gateway/inbox/chatgpt/<package_id>/
gateway/inbox/manus/<package_id>/
gateway/inbox/claude/<package_id>/
gateway/inbox/codex/<package_id>/
gateway/inbox/runa/<package_id>/
```

نمایه‌های Obsidian نیز در یک مسیر کانالی مشترک و با زیرپوشه‌های مجزا نگهداری شوند:

```text
11-AI/40-Imports/ObSi-KAR/Channels/ChatGPT/
11-AI/40-Imports/ObSi-KAR/Channels/Manus/
11-AI/40-Imports/ObSi-KAR/Channels/Claude/
11-AI/40-Imports/ObSi-KAR/Channels/Codex/
11-AI/40-Imports/ObSi-KAR/Channels/RUNA/
```

این مسیرها **هدف پیشنهادی** هستند؛ این بسته آن‌ها را در Vault ایجاد نکرده است. Owner باید قواعد Vault، نام‌گذاری و رفتار Worker موجود را بررسی کند و تغییرها را از مسیر رسمی ObSi KAR اعمال کند. یک پروژهٔ دانشی بین چند کانال مشترک می‌ماند؛ محتوا را برای هر کانال تکثیر نکنید. پوشه‌بندی به‌تنهایی مرز امنیتی نیست.

`producer_id`، پلتفرم میزبان، Agent، پروژه و منشأ محتوای اصلی مفاهیم جدا هستند. اگر Manus یک Export متعلق به ChatGPT را تحویل می‌دهد، Producer تحویل `manus` است، اما منشأ گفتگو `ChatGPT` ثبت می‌شود. `RUNA` نام Agent است و پلتفرم میزبانش تا زمانی که شاهدی وجود ندارد نامعلوم می‌ماند.

## وضعیت پروندهٔ RUNA

درخواست ثبت موجود و مجموعهٔ منتخب باید ادامه پیدا کنند؛ آرشیوسازی از صفر، دانلود دوبارهٔ فایل‌های سالم، قرض‌گرفتن شناسهٔ APIJoo/Blender و تحویل فقط گزارش مجاز نیست. این بسته اطلاعات محلی و خصوصی RUNA را عمداً در Git عمومی نمی‌گذارد. اگر RunTime نشان دهد Producer مستقل یا دریافت چندفایلی هنوز فعال نیست، این موارد مانع هستند و باید از همان مسیر رسمی Owner حل شوند. **بدون رسید واقعی برای فایل‌ها و بسته، RUNA نه دریافت‌شده و نه پردازش‌شده اعلام نمی‌شود.**

## معیار پایان اتصال

اتصال Manus فقط وقتی آماده است که URL HTTPS واقعی و هویت محدود Producer موجود باشد؛ Manus Tool Discovery و خواندن مجاز را موفق انجام دهد؛ خواندن خارج از Scope رد شود؛ بستهٔ ساختگی چندفرمتی با Resume/Retry و Hash همهٔ اعضا تحویل شود؛ همان Worker موجود آن را بپذیرد؛ و رسید نهایی/Readback در Obsidian تأیید شود. ثبت Custom MCP، ساخت Manifest، ایجاد Task یا پاسخ `submitted` به‌تنهایی هیچ‌یک این معیار را کامل نمی‌کند.

## منابع رسمی

- [Manus Custom MCP Servers](https://manus.im/docs/integrations/custom-mcp) [S1]
- [Manus API Connectors](https://open.manus.im/docs/v2/connectors) [S10]
- [Manus API connector.list](https://open.manus.im/docs/v2/connector.list) [S11]
- [Manus API task.create](https://open.manus.im/docs/v2/task.create) [S12]
- [Manus API Task Lifecycle](https://open.manus.im/docs/v2/task-lifecycle) [S13]
