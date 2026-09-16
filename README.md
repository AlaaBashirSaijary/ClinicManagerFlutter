# Clinic Manager — Flutter

نسخة موازية من مشروع [ClinicManager](../ClinicManager) (Laravel) بنفس الوظائف
بالضبط، مبنية بـ Flutter + Clean Architecture، لتشتغل كتطبيق آيباد أصلي —
قاعدة بيانات SQLite محلية بالكامل، بدون سيرفر وبدون إنترنت.

المشروع الأصلي (Laravel) **لم يُلغَ** — هذا مشروع منفصل تمامًا بجانبه.

## ليش هذا المشروع موجود

قرار العميل: البرنامج لازم يشتغل من آيباد واحد فقط، متّصل بهارد خارجي لتخزين
البيانات. هذا غير ممكن مع تطبيق ويب (Laravel + متصفح) — iOS لا يسمح لتطبيق
ويب بالوصول لملفات خارج الـ sandbox الخاص فيه، ولا بتشغيل سيرفر دائم بالخلفية.
الحل الوحيد هو تطبيق iOS أصلي، وهذا ما يوفره Flutter.

**القيد المصاحب لهذا القرار:** التطبيق أحادي الجهاز الآن — لا وصول من موبايلات
الموظفين ولا من فروع أخرى. لو تغيّر هذا القرار لاحقًا، الحل يرجع للمشروع
الأصلي (سيرفر + Tailscale)، وهذا موثّق بتفاصيله في محادثة تطوير المشروع
الأساسي.

## بنية المشروع (Clean Architecture)

كل ميزة (`features/*`) مقسومة لثلاث طبقات، بنفس الترتيب من الأعمق للأقرب
للواجهة:

```
lib/
  core/                     ← بنية تحتية مشتركة بين كل الميزات
    database/               ← AppDatabase: اتصال SQLite واحد لكل التطبيق
    di/                     ← get_it: نفس دور حاوية الخدمات (container) في Laravel
    error/                  ← Failure types بدل استثناءات PHP / $errors->all()
    theme/                  ← ألوان ومقاسات مطابقة لـ resources/css/app.css
    usecases/               ← عقد UseCase أساسي تلتزم فيه كل حالات الاستخدام

  features/
    auth/
      domain/               ← AppUser (= User model)، AuthRepository (عقد)، Login usecase
      data/                 ← AuthLocalDataSource (استعلامات SQL خام)، AuthRepositoryImpl
      presentation/         ← AuthNotifier (Riverpod)، صفحات تسجيل الدخول والإعداد الأول

    patients/
      domain/               ← Patient (= Patient model)، PatientValidator (= الفاليديشن بالكونترولر)
      data/                 ← PatientLocalDataSource، PatientRepositoryImpl
      presentation/         ← لوحة المرضى، نموذج الإضافة/التعديل، صفحة التفاصيل

    clinic_settings/
      presentation/         ← StorageSettingsPage: اختيار مكان قاعدة البيانات
                               (القرص الخارجي)، بديل صفحة /admin/settings
```

القاعدة: `domain` لا يعرف شيء عن Flutter ولا عن SQLite — فقط منطق العمل
(entities + قواعد التحقق + عقود repository). `data` ينفّذ تلك العقود عبر
sqflite. `presentation` هو الوحيد الذي يعرف عن Widgets وRiverpod. هذا يطابق
فكرة الفصل بين Models/Controllers/Views في Laravel، فقط بحدود أوضح.

## مطابقة الوظائف مع المشروع الأصلي

| Laravel | Flutter | ملاحظات |
|---|---|---|
| `database/migrations/*.php` | `AppDatabase._createSchema()` | نفس الجداول والفهارس بالضبط |
| `app/Models/Patient.php` | `Patient` entity + `PatientValidator` | نفس الحقول، نفس قواعد التحقق |
| `app/Models/User.php` | `AppUser` entity | نفس role/isAdmin |
| `PatientController::validated()` | `PatientValidator.validate()` | نفس الرسائل بالعربي |
| `PatientController::authorizeClinic()` | فحص `clinicId` داخل `PatientRepositoryImpl` | يرجع `UnauthorizedFailure` بدل 404 |
| `HomeController` (بحث/فلترة/صفحات) | `PatientsListNotifier` | نفس منطق البحث (`scopeSearch`) والفلترة (`scopeStatus`) |
| `Auth\LoginController` | `AuthNotifier` + `AuthRepositoryImpl` | جلسة محفوظة بـ `shared_preferences` بدل كوكي |
| `database/seeders/ClinicSeeder.php` | `OnboardingPage` | لا بيانات تجريبية مبيّتة؛ العيادة تُنشئ حسابها بنفسها أول مرة |
| `Admin\SettingsController` (مسار التخزين) | `StorageSettingsPage` | يستخدم منتقي ملفات iOS بدل حقل نص، لأن هذا ما يسمح فعليًا بالوصول لقرص خارجي |

## نواقص معروفة (لسا ما اتعملت)

- **الخط**: الموقع يستخدم IBM Plex Sans Arabic (ملفات `.woff2`)؛ Flutter
  يحتاج `.ttf`/`.otf`. لسا ما انضافت، فالتطبيق يستخدم خط النظام الافتراضي
  حاليًا (يعرض العربي صح، بس مو نفس الخط بالضبط).
- **النسخ الاحتياطي التلقائي** (نظير `clinic:backup` + الجدولة اليومية):
  لسا ما انبنى. الأولوية كانت لمنطق المرضى + مكان التخزين لأنه الأهم للعميل
  الآن.
- **اختبارات الوحدة للـ use cases/repositories**: البنية جاهزة لها
  (`mocktail` مضاف كـ dev dependency)، بس لسا ما انكتبت اختبارات فعلية غير
  اختبار الإقلاع الأساسي بـ `test/widget_test.dart`.

## التشغيل محليًا

```bash
flutter pub get
flutter run   # يحتاج جهاز iOS متصل أو محاكي مفتوح
```

الاختبارات (تعمل بدون جهاز حقيقي، عبر SQLite في الذاكرة):

```bash
flutter test
```
