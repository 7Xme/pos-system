# YPOS — نظام نقطة بيع (POS)

تطبيق **ديسكتوب** لنقطة بيع محل كتب وأدوات مدرسية، بواجهة **عربية RTL** كاملة
ومهيّأة للمس. يعمل محليًا بالكامل على قاعدة بيانات SQLite (بدون سيرفر).

> Flutter Desktop (Windows) + Drift/SQLite + BLoC — بدون ضريبة ولا خصم على الفاتورة
> (المجموع فقط) وطباعة A4 عادية.

---

## ✨ المزايا

| الميزة | الوصف |
|---|---|
| 🛒 **نقطة البيع** | شبكة منتجات، شريط اختصاصات، قراءة باركود مباشرة، نطق عربي لأسماء الأصناف |
| 🏷️ **باركود متعدد** | أكثر من باركود لكل منتج (v5) مع باركود رئيسي للطباعة |
| 📦 **المخزون** | إضافة/تعديل منتجات، تنبيه النواقص (minStock)، فئات، صور منتجات |
| 🧾 **المبيعات** | سجل الفواتير، تفاصيل، إرجاع جزئي مع استعادة المخزون |
| 🚚 **المشتريات** | أوامر شراء (مسودة → مُستلَم) وتحديث التكلفة والمخزون |
| 🖨️ **الطباعة** | A4: فاتورة بيع، أمر شراء، مردود، وتقرير أرباح |
| 💾 **نسخ احتياطي** | تصدير/استيراد ZIP لقاعدة البيانات + الصور |
| 📥 **استيراد الكتالوج** | استيراد قاعدة جاهزة + صور من مجلد `data` |
| 🔊 **نطق عربي** | عبر أصوات ويندوز الأصلية (SAPI/FFI) أو صوت Google أونلاين كبديل |
| ⚙️ **الإعدادات** | بيانات المتجر، الكاشير، تفضيلات التطبيق |

---

## 🖥️ الشاشات

الشريط الجانبي (يمين في RTL) يبدّل بين:
**نقطة البيع · المنتجات · الفئات · المشتريات · المبيعات · نسخ احتياطي · استيراد · الإعدادات**

---

## 🧱 البنية التقنية

| الطبقة | التقنية |
|---|---|
| الواجهة | Flutter (`sdk ^3.4.0`)، `flutter_bloc` + `equatable` |
| قاعدة البيانات | Drift (SQLite)، `sqlite3_flutter_libs` **(0.5.x)** |
| الطباعة | `pdf` + `printing` + `barcode_widget` |
| النوافذ | `window_manager` |
| النطق | `ffi` (SAPI أصلي) + `http` + `audioplayers` (بديل) |
| متفرقات | `file_picker`، `intl`، `uuid`، `archive` (ZIP) |

دليل الكود: `lib/`
```
lib/
├─ main.dart                     تهيئة النافذة + DB + TTS + Providers
├─ app/                          shell.dart (التنقل) + theme.dart (RTL)
├─ core/
│  ├─ database/                  app_database + tables + repositories + seed
│  ├─ barcode/                   خدمة قارئ الباركود
│  ├─ printing/                  خدمات A4 وبناء PDF (بيع/شراء/مردود/أرباح)
│  ├─ images/                    مخزن صور المنتجات محليًا
│  ├─ tts/                       النطق العربي (SAPI + أونلاين)
│  └─ backup/                    نسخ احتياطي ZIP
└─ features/                     pos · inventory · sales · purchases · backup · import · settings
```

---

## ✅ المتطلبات

- Flutter (قناة مستقرة) مع دعم **Windows Desktop**.
- Python 3.10+ مع `aiohttp` — **فقط** لأدوات جمع الكتالوج (اختياري).

```powershell
python -m pip install aiohttp
```

---

## ▶️ التشغيل والبناء

```powershell
# تشغيل في وضع التطوير
flutter pub get
dart run build_runner build          # لتوليد ملفات Drift (.g.dart)
flutter run -d windows

# بناء نسخة الإصدار
flutter build windows --release
# الناتج: build\windows\x64\runner\Release\YPOS.exe
```

---

## 🗄️ قاعدة البيانات

مخطط Drift (`user_version = 5`) — 11 جدولًا:

`categories` · `products` · `settings` · `invoices` · `invoice_items` ·
`product_barcodes` · `returns` · `return_items` · `purchase_orders` ·
`purchase_order_items` (+ جداول Drift الداخلية)

- `products.barcode` فريد، و`product_barcodes` يسمح بعدّة باركودات لكل منتج.
- الجداول تُنشأ وتُزرَع تلقائيًا عند أول تشغيل (`ensureSeeded`).

---

## 📥 استيراد الكتالوج

تطبيق YPOS يستورد مجلد `data/` الناتج من أدوات جمع الكتالوج
(انظر [`tools/scraper/README.md`](tools/scraper/README.md)):

```powershell
# 1) جمع كل الكتالوج (قابل للاستكمال)
powershell -File tools\scraper\run_full.ps1
# 2) بناء قاعدة جاهزة للاستيراد
python tools\scraper\build_db.py --sql
```

ثم داخل التطبيق: **استيراد** → اختر مجلد `data`.

### الكتالوج الافتراضي المرفق + الوضع المحمول

**الوضع المحمول (تلقائي):** إذا وُجدت قاعدة البيانات بجانب `YPOS.exe`:

```
مجلد البرنامج\
├─ YPOS.exe
├─ bookstore_pos.sqlite        (أو داخل data\)
└─ product_images\             (أو داخل data\)
```

يعمل التطبيق على هذه الملفات **مباشرةً** (بلا نسخ إلى AppData ولا استيراد).
انقل المجلد كاملًا إلى أي جهاز آخر وسيعمل، حتى لو تغيّر المسار. الصور القديمة
المحفوظة بمسارات مطلقة تُطابق باسم الملف داخل مجلد الصور الحالي.

إن لم يوجد مجلد محمول، يعود التطبيق إلى مسار دعم التطبيق
(`%APPDATA%\YPOS\YPOS`) ويزرع الكتالوج المرفق عند أول تشغيل فقط:

1. ينسخ `data/bookstore_pos.sqlite` إلى قاعدة التطبيق.
2. يعيد كتابة مسارات الصور لتشير مباشرةً إلى `data/product_images`.

المنطق في `lib/core/storage/app_paths.dart` و
`lib/core/database/catalog_bootstrap.dart`.

عند البناء للتوزيع:

```powershell
powershell -File tool\build_installer.ps1
```

ينتج `build\dist\` = `YPOS-Setup.exe` + `data\` (قاعدة + صور). وزّع المجلد
كاملًا؛ المثبّت ينسخ `data\` إلى مجلد التثبيت ليكون الكتالوج هو الافتراضي.

> المنتجات التجريبية الستة القديمة أُلغيت من الإقلاع (بقيت في `seed.dart`
> للاختبارات فقط).

### جمع سريع متوازٍ (عدّة عمّال)

لتقسيم العمل على عدّة مهام (شُعب) بالتوازي بدل عملية واحدة:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\scraper\finalize_parallel.ps1 -Shards 3
```

يبني قاعدة البيانات ويتحقق منها تلقائيًا بعد انتهاء العمّال، ويكتب `data\.finalized`.

متابعة الحالة في أي وقت:

```powershell
python tools\scraper\status.py          # قراءة مقروءة
python tools\scraper\status.py --json   # لِلسكربتات
```

---

## 📂 مجلد `data/` (خارج Git)

```
data/
├─ product_urls.txt        روابط المنتجات من خرائط الموقع
├─ products.jsonl          سجل JSON لكل منتج (الجمع الخام)
├─ categories.json         قائمة الفئات
├─ bookstore_pos.sqlite    قاعدة Drift جاهزة للاستيراد
├─ bookstore_pos.sql.gz     نفس البيانات كـ SQL مضغوط
├─ product_images/         صور المنتجات (512px) باسم <id>.jpg
├─ logs/                   سجلات الجمع
└─ .finalized / .pages_complete   علامات اكتمال المراحل
```

---

## 🪟 ملاحظات بناء ويندوز

- يجب تثبيت `sqlite3_flutter_libs: >=0.5.0 <0.6.0` — الإصدار `0.6.0+eol` شيم فارغ
  يتطلب `package:sqlite3` 3.x، بينما `drift` 2.x يحتاج بناء 0.5.x ليضمّ `sqlite3.dll`
  بجانب `YPOS.exe`.
- بعد `build_runner build` تأكد من توليد `app_database.g.dart`.
- إن فشل التحزيم في `flutter_assemble` بخطأ `IconTreeShakerException`، تحقّق من
  وجود `const_finder.dart.snapshot` و`font-subset.exe` في مخزّن محرّك Flutter.

---

## 📌 حالة المشروع

الإصدار `1.0.0+1` — جاهز للاستخدام على ويندوز.
