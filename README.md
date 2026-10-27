# Relay — Flutter native

تطبيق واتساب خاص بجهازك، باللغة العربية افتراضياً مع دعم الإنجليزية. واجهة بسيطة بخط كبير. يتصل مباشرة بـ Twilio، ولا يحتاج خادماً خاصاً أو متصفحاً.

## Windows — تشغيل النسخة الجاهزة

1. فك ضغط **Relay-Windows.zip** إلى مجلد كامل.
2. افتح **Relay.exe** من داخل المجلد. أبقِ ملفات DLL ومجلد `data` بجانبه؛ لا تنقل ملف EXE وحده.
3. افتح **الإعدادات** وأدخل Account SID الذي يبدأ بـ AC، ورقم واتساب المعتمد بصيغة `+9647…`.
4. اختر **مفتاح API** وأدخل API Key SID الذي يبدأ بـ SK وسرّ المفتاح. أو اختر **Account Auth Token** وأدخل رمز الحساب. بيانات Twilio US1 الافتراضية مدعومة.
5. اضغط **حفظ واختبار الاتصال**. الاختبار يتحقق من صلاحية قراءة API ولا يرسل رسالة. لا يثبت اعتماد المرسل أو تسليم الرسائل.
6. افتح **جهات الاتصال** وأضف جهة تملكها للتجربة أو استورد CSV / XLSX / XLS. سجّل الموافقة الفعلية للمستلم.
7. افتح **إنشاء رسالة** واضغط **تحميل قوالبي من Twilio**. اختر القالب باسمه، واملأ حقول التفاصيل، ويمكنك استخدام اسم كل مستلم تلقائياً. في المراجعة ابدأ بخيار **الأولى فقط**؛ هذا إرسال حقيقي يستخدم رصيد Twilio.

لا ترسل بيانات API في المحادثة ولا تضعها في الملف التنفيذي. أدخل بياناتك داخل التطبيق فقط. كل تثبيت يستخدم بيانات اعتماد خاصة يدخِلها المستخدم، وليس أسراراً مدمجة في المصدر.

## الرسائل والصور

- **اختيار قالب:** اضغط تحميل قوالبي من Twilio، واختر القالب باسمه ولغته. يظهر نصه وأزراره في المعاينة، وتظهر تفاصيله كحقول عادية دون JSON. اختر **اسم كل مستلم** أو **رقم كل مستلم** للتخصيص التلقائي، أو اكتب قيمة ثابتة. اضغط تحديث الاعتماد؛ يراجع التطبيق الحالة مرة أخرى قبل تأكيد إرسال جديد. القالب غير المعتمد لا يُرسل من هذا المسار.
- **إنشاء قالب أو تعديله للمبتدئين:** اختر **قالب جديد + أزرار روابط**، أو **تعديل نسخة + الروابط** لقالب موجود. اكتب اسماً ونصاً، وأضف أمثلة للمتغيرات، وصورة اختيارية، وحتى زري موقع. لكل زر عنوان حتى 20 حرفاً ورابط HTTPS كامل. ثم احفظ القالب في Twilio واضغط **طلب اعتماد واتساب**. اختر التسويق للعروض أو تحديث طلب/خدمة للرسائل الخدمية المناسبة. انتظر الاعتماد وحدّث الحالة لاحقاً. إنشاء القالب لا يرسل رسالة. تعديل نسخة ينشئ قالباً جديداً يحتاج اعتماداً، ويحافظ على القالب السابق.
- **الأزرار والصور:** النص مع أزرار يستخدم `twilio/call-to-action`، والنص مع صورة وأزرار يستخدم `twilio/card`. الروابط في المحرر الجديد ثابتة. القوالب المحملة ذات الروابط المتغيرة تعرض المتغيرات كحقول؛ قد يحتاج متغير الرابط إلى جزء من الرابط حسب تصميم القالب. نص المعاينة ليس نصاً إضافياً يُرسل؛ يرسل Twilio القالب المعتمد نفسه.
- **الإعداد المتقدم:** يمكن إدخال Content SID يبدأ بـ HX وJSON يدوياً عند الحاجة. مثال `{"1":"{{name}}"}`، أو `{}` لقالب بلا متغيرات. هذا المسار يعتمد على معرف القالب الذي تدخله وعلى تحقق Twilio عند الإرسال.
- **رد 24 ساعة:** نص حر وصورة اختياريان، بشرط أن يكون كل مستلم قد راسل النشاط خلال آخر 24 ساعة. يؤكد المستخدم النافذة؛ التطبيق لا يتلقى رسائل واردة أو يتتبعها تلقائياً. يُطبّق Twilio قواعد الإرسال الفعلية.
- **صورة من رابط:** الصق رابط HTTPS مباشراً وعاماً لصورة JPG أو PNG تحت 5 MB. يجب أن يصل إليه Twilio دون تسجيل دخول. الصورة التي تظهر في المعاينة قد تُرفض عند الإرسال إذا كان الرابط لا يعيد نوع محتوى مناسباً أو كان الحجم غير مقبول.
- **صورة من جهازك:** لا تحتاج Cloudinary أو حساب صور منفصلاً. يستخدم التطبيق بيانات Twilio نفسها لإنشاء مساحة خاصة بالتطبيق داخل **Functions & Assets** ورفع JPG / PNG حتى 5 MB. تجهيز رابط الصورة قد يستغرق دقيقة أو أكثر. يحتفظ النشر بالصور السابقة، وتُحفظ معرفات المساحة على جهازك لإعادة استخدامها. الصور عامة لمن لديه الرابط وتبقى حتى تحذفها من لوحة Twilio؛ قد تطبق حدود ورسوم الخدمة. حد المساحة 1,000 صورة منشورة. إذا تغير النشر أثناء الرفع يتوقف التطبيق قبل استبداله.

إذا رفض Twilio تحميل القوالب أو الصور برسالة صلاحيات، استخدم مفتاحاً يسمح بـ **Content API** و**Functions & Assets**، مثل Standard API key مناسب لحسابك أو Account Auth Token. نجاح اختبار Messaging وحده لا يثبت صلاحية هاتين الخدمتين. توفر الخدمة والرسوم يعتمد على حسابك. لم نختبر الرفع الفعلي أو اعتماد القوالب بحسابك؛ اختبارات التطوير تستخدم استجابات API اصطناعية ولا تتصل بحسابك.

**إذا ظهرت مشكلة في رابط الصورة:** النسخة 1.1.1 تقرأ الصورة بطلب GET وتتحقق من نوعها وتوقيع ملف JPG/PNG، بدلاً من الاعتماد على HEAD فقط. تنتظر إتاحة الرابط حتى 90 ثانية تقريباً. بعد قبول طلب النشر يُحفظ الرابط قبل فحصه. إذا فشل الفحص يظهر مربع يحتوي الرابط وسبب الخطأ، مع **فتح الصورة** و**نسخ الرابط** و**إعادة التحقق واستخدام الصورة**. إعادة التحقق لا ترفع ملفاً جديداً ولا تنشئ نشراً جديداً؛ يبقى الرابط محفوظاً بعد إعادة تشغيل التطبيق. روابط محاولات النسخة 1.1.0 لم تكن محفوظة؛ ارفع الصورة مرة واحدة بالنسخة الجديدة إذا لم يكن لديك رابط سابق. تحقق التطبيق من إتاحة الصورة لا يثبت تسليم واتساب.

التطبيق يتصل بواجهة Twilio؛ تحويله إلى Flutter لا يلغي متطلبات المرسل المعتمد أو موافقة المستلمين أو القوالب أو رسوم Twilio. لا يُرسل أي شيء عند فتح التطبيق أو اختبار الاتصال.

## الاستيراد

- CSV بترميز UTF-8، أو Excel XLSX، أو XLS القديم بصيغة BIFF8 (Excel 97–2003).
- حد الملف 10 MB، وحتى 5,000 جهة اتصال و100 عمود.
- الصف الأول عناوين أعمدة. اختر ورقة Excel وطابق أعمدة الهاتف والاسم والموافقة.
- تدعم الموافقة `yes` و`true` و`1` و`نعم`. غير ذلك يعني عدم وجود موافقة مسجلة. تأكيد موافقة كل الملف يُستخدم فقط إذا كانت الموافقة موجودة فعلياً لكل الأرقام.
- الأرقام المحلية العراقية والأرقام العربية والفارسية تتحول إلى صيغة دولية. العراق +964 افتراضي ويمكن تغييره. الأرقام المكررة وغير الصالحة تُستبعد، وتظهر أرقام الصفوف غير الصالحة.
- اجعل أرقام الهاتف نصوصاً في Excel للحفاظ على الأصفار وكامل الأرقام؛ لا يمكن استعادة أرقام أتلفها تقريب Excel.
- ملفات `examples/` أمثلة اصطناعية وموافقتها `no`، وليست قوائم للإرسال.

## حفظ البيانات وسجل الإرسال

الأسرار محفوظة في مخزن النظام الآمن (Windows DPAPI المشفر، وKeychain على Apple، ومخزن آمن مشفر على Android). الإعدادات غير السرية وجهات الاتصال والمسودة والسجل في ملفات داخل مساحة بيانات التطبيق، مع كتابة متسلسلة ونسخة احتياطية. جهات الاتصال والسجل ليسا مشفرين بحد ذاتهما؛ تحميهما صلاحيات حساب الجهاز. لا ترسل هذه البيانات إلى خدمة تخزين سحابية، ولا تتزامن تلقائياً بين الأجهزة. تصدير CSV لا يتضمن الأسرار.

احتفظ بالتطبيق مفتوحاً وفي المقدمة أثناء الإرسال. يرسل طلباً واحداً تقريباً في الثانية. الإيقاف المؤقت ينتظر انتهاء الطلب الحالي. على الهاتف، إغلاق الشاشة أو نقل التطبيق إلى الخلفية قد يوقف التقدم؛ لا توجد خدمة إرسال في الخلفية.

يسجّل التطبيق محاولة الإرسال محلياً **قبل** طلب Twilio. إذا حدث انقطاع أو تعطل، لا يعيد تلقائياً المحاولات السابقة أو غير المؤكدة. افحص سجل Twilio قبل إنشاء إرسال جديد. يمكنك متابعة جهات لم تُقدّم طلباتها بعد، مع تأكيد الموافقة ونافذة الرد إن كانت مطلوبة. لا تشغّل أكثر من نسخة على الجهاز نفسه؛ التطبيق يقفل ملف بياناته لمنع تعارض النسخ.

**في الانتظار أو تم الإرسال لا يعني تم التسليم.** افتح سجل الإرسال واضغط تحديث الحالات للحصول على آخر حالة من Twilio. لا توجد webhooks أو مزامنة خلفية؛ الحالات تُحدّث يدوياً. حالة القراءة تعتمد على إعدادات واتساب. التصدير يستخدم حماية من صيغ جداول البيانات.

## macOS / Android / iPhone

المصدر يتضمن مشاريع Windows وmacOS وAndroid وiOS. **الملف الجاهز المرفق خاص بـ Windows x64.** لم تُبنَ نسخ Apple أو Android في هذه البيئة.

- macOS: يلزم Mac مع Flutter وXcode، ثم `flutter pub get` و`flutter build macos --release`. إعدادات الشبكة والملفات مضافة. يستخدم التخزين الآمن Keychain المحلي دون Keychain Sharing على Mac. التوزيع على أجهزة أخرى يحتاج توقيعاً وnotarization مناسبين.
- Android: يلزم Android SDK وأدوات Flutter؛ ثم `flutter build apk --release`. الحد الأدنى Android API 24 (وقد يرفعه إصدار Flutter). ملف Gradle ما زال يستخدم مفتاح التطوير الافتراضي؛ أضف مفتاح إصدار خاصاً قبل توزيع نسخة رسمية. إذن الإنترنت مضاف والنسخ الاحتياطي التلقائي معطل لتجنب مشاكل نقل مفاتيح التخزين.
- iPhone/iPad: يلزم Mac وXcode وحساب توقيع Apple لتثبيت التطبيق؛ ثم `flutter build ios --release`. الهدف الحالي iOS 15 فأحدث. ملف entitlements للتخزين الآمن مضاف؛ اختر فريق التوقيع المناسب في Xcode.
- هذه نسخة **Native**. لا يتضمن المشروع هدف Web؛ حفظ الأسرار داخل Flutter Web لن يحولها إلى أسرار خادم.

## Build and test

Flutter 3.47.7 / Dart 3.13.5 was used. Dependencies are pinned in `pubspec.lock`; newer incompatible dependency versions are not required.

```text
flutter pub get
flutter analyze
flutter test
flutter test integration_test/native_test.dart -d windows
flutter build windows --release
```

The unit tests mock Twilio and never send real messages. Native integration tests use isolated synthetic state, a separate secure-storage key, and a temporary application-support path inside the test sandbox; they test real Windows DPAPI encryption and persistence without using your account. Live Twilio delivery still needs your credentials, approved sender/template and consenting test recipient.

Project layout:

- `lib/main.dart`: responsive Material interface, Arabic/English, contacts/import dialog, composer, history and settings.
- `lib/domain.dart`: models, CSV parsing, phone normalization and personalization.
- `lib/services.dart`: native file storage, secure vault, Twilio Messaging HTTP and Excel readers.
- `lib/twilio_assets.dart`: public photo uploads, builds, deployment and link verification through Twilio.
- `lib/templates.dart` and `lib/template_editor.dart`: template loading, approval, beginner editor, photo/URL button creation and previews.
- `lib/controller.dart`: validation, durable send attempts, pause/resume, consent recheck, status refresh.
- `test/`: parser, API, persistence logic and UI tests.
- `integration_test/`: native Windows storage smoke test.

The app is a private, per-device business utility. A centralized multi-user application, shared account secrets, incoming message inbox, automatic contact syncing or unattended sending would need additional architecture.

Official references:

- https://www.twilio.com/docs/whatsapp/api
- https://www.twilio.com/docs/messaging/api/message-resource
- https://pub.dev/packages/flutter_secure_storage
- https://pub.dev/packages/file_picker
- https://www.twilio.com/docs/serverless/api/resource/asset-version
- https://www.twilio.com/docs/content/content-api-resources
- https://www.twilio.com/docs/content/twilio-call-to-action
- https://www.twilio.com/docs/content/twiliocard

## English quick start — templates, website buttons and photos

In New message, select **Load my Twilio templates**, choose a template by name and fill in the ordinary detail fields. Use **Each recipient’s name** for automatic personalization. The preview shows the template text, photo and website buttons. Advanced manual SID/JSON entry remains available.

Use **New template + link buttons** or **Edit a copy + links** to write the text, provide realistic variable samples, add an optional photo and up to two website buttons. Enter a label (20 characters maximum) and a full HTTPS link for each button. Save the template to Twilio, request WhatsApp approval, then close the editor and refresh its approval status later. Edited copies require new approval. Creating or submitting a template does not send any message.

Photo uploads now use **Twilio Functions & Assets** with the same Twilio credentials; no separate image provider is needed. Images are public to anyone with their URL and remain until you remove them in Twilio. Publishing can take a minute or more; prior photo versions are retained in each build. Twilio limits and charges may apply. Your credentials need Content API and Functions & Assets access in addition to Messaging access. Live upload, approval and delivery still require verification using your own account.

Version **1.1.1** checks the actual photo with GET, verifies its MIME type and JPG/PNG file signature, follows public HTTPS redirects and allows up to approximately 90 seconds for the public link check. It saves the published URL before checking. If verification fails, a recovery box displays the URL and HTTP, DNS, TLS or timeout detail. Use **Open photo**, **Copy link** or **Retry check & use photo**. Retrying checks the same link without uploading or deploying again, and the saved link survives app restarts. Version 1.1.0 did not retain failed links; if no link is available, upload once in the updated version. Successful verification does not prove WhatsApp delivery.
