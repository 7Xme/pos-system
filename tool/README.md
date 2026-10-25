# أداة بناء YPOS وتثبيته

هذا المجلد يبني **مثبّت ويندوز** لبرنامج YPOS، ويحزم معه **الكتالوج الافتراضي**
(المنتجات + الصور) الذي ينشرجه السكربتات في `tools/scraper`.

## البناء

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build_installer.ps1
```

أو انقر نقرًا مزدوجًا على `build_exe.cmd` في جذر المشروع. يقبل الوسائط نفسها
بالأسماء المختصرة: `build_exe.cmd quick` = `-SkipData`،
`build_exe.cmd nobuild` = `-SkipFlutterBuild`، ويمكن دمجهما.

المعاملات الاختيارية:

| المعامل | الأثر |
|---|---|
| `-SkipFlutterBuild` | يتخطّى `flutter build` ويستخدم آخر ناتج موجود |
| `-SkipData` | لا ينسخ قاعدة الكتالوج/الصور إلى `build\dist` (بناء سريع للمثبّت فقط) |

### مراحل البناء (`build_installer.ps1`)

1. `flutter build windows --release`
   (يُكتشف مسار `flutter` تلقائيًا؛ وإن غاب يُستعمل `flutter` من `PATH`).
2. تجهيز نسخة من مجلد `Release` وحذف ملفات `.pdb`.
3. ضغطها إلى `build\ypos_payload.zip`.
4. ترجمة `ypos_installer.cs` بـ `csc` مع تضمين الـ ZIP كمورد مانيفست،
   والناتج `build\YPOS-Setup.exe` (ملف واحد صغير ≈18MB).
5. إنشاء `build\dist\` = `YPOS-Setup.exe` + `data\` (قاعدة + صور).

## مجلد التوزيع

```
build\dist\
├─ YPOS-Setup.exe          المثبّت (صغير)
└─ data\
   ├─ bookstore_pos.sqlite قاعدة الكتالوج (≈29MB، 99,425 منتجًا)
   └─ product_images\      99,425 صورة (≈4.5GB)
```

**وزّع المجلد كاملًا.** لا تقسمه؛ المثبّت يقرأ `data` من جانبه.

> **لماذا ليس ملف exe واحدًا؟** 4.5GB من الصور لا يمكن تضمينها في exe واحد
> (حدود ZIP بدون ZIP64 + موارد PE). لذلك يبقى المثبّت صغيرًا ويُنشر الكتالوج
> بجانبه، ثم ينسخه المثبّت إلى مجلد التثبيت.

## ماذا يفعل المثبّت (`ypos_installer.cs`)

| الخطوة | التفصيل |
|---|---|
| إيقاف النسخة قيد التشغيل | يغلق `YPOS.exe` إن كان مفتوحًا |
| نسخ ملفات البرنامج | يفكّ مورد الـ ZIP إلى مجلد التثبيت |
| **نسخ الكتالوج الافتراضي** | ينسخ `data\` (قاعدة + صور) إلى `<مجلد التثبيت>\data` — **ينسخ الناقص فقط ولا يستبدل قاعدة بيانات موجودة** (حماية لبيانات المتجر الحية) |
| ترحيل بيانات قديمة | ينسخ `%APPDATA%\com.bookstore\bookstore_pos` إن وُجدت ولم تكن هناك بيانات جديدة |
| الاختصارات | سطح المكتب + قائمة ابدأ |
| التسجيل | مدخل الإزالة في الريجستري (`HKCU\...\Uninstall\YPOS`) |

### المسارات

| المسار | القيمة |
|---|---|
| مجلد التثبيت | `%LOCALAPPDATA%\Programs\YPOS` |
| بيانات المتجر (القاعدة والصور) | `<مجلد التثبيت>\data` — **وضع محمول** يعمل عليه التطبيق مباشرةً |
| بديل احتياطي | `%APPDATA%\YPOS\YPOS` إن لم يوجد مجلد `data` بجانب الـ exe |

### التشغيل والإلغاء

```powershell
build\dist\YPOS-Setup.exe             # تثبيت (واجهة رسومية)
build\dist\YPOS-Setup.exe --uninstall # إزالة (يحذف ملفات البرنامج ويُبقي مجلد data)
```

## عند أول تشغيل للبرنامج

`lib/core/storage/app_paths.dart` يكتشف تلقائياً وجود القاعدة بجانب الـ exe
(`YPOS.exe` + `bookstore_pos.sqlite` + `product_images` أو نفسها داخل `data`)،
ويعمل عليها مباشرةً بلا نسخ ولا استيراد. هذا يجعل مجلد التثبيت (أو أي مجلد
تنسخه إليه) نسخة محمولة تنتقل مع بياناتها إلى أي حاسوب.

إذا لم توجد قاعدة محمولة، يعود التطبيق إلى `%APPDATA%\YPOS\YPOS` ويزرع الكتالوج
المرفق عند أول تشغيل فقط (كما كان سابقاً).

## المتطلبات

- Flutter (Windows Desktop) — لبناء التطبيق.
- `csc.exe` من .NET Framework 4
  (`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`).
- أيقونة `windows\runner\resources\app_icon.ico` (اختيارية لكن مستحسنة).

## ملفات المجلد

| الملف | الدور |
|---|---|
| `build_installer.ps1` | يبني `YPOS-Setup.exe` + `build\dist\` |
| `ypos_installer.cs` | شيفرة المثبّت (واجهة WinForms + خطوات التثبيت/الإزالة) |
| `make_icon.ps1` | يولّد `app_icon.ico` |
