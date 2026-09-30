import 'package:flutter/foundation.dart';

import '../game/engine.dart';

/// Minimal bilingual support (English + Arabic).
///
/// Usage: `tr('Start game')` returns the Arabic text when the language is
/// Arabic, otherwise the English source itself. Untranslated strings safely
/// fall back to English, so partial coverage never shows blanks.
final appLang = ValueNotifier<String>('en');

bool get isRtl => appLang.value == 'ar';

String tr(String en) => appLang.value == 'ar' ? (_ar[en] ?? en) : en;

/// Template translation with a `{n}` numeric slot (e.g. step counts).
String trn(String template, Object value) =>
    tr(template).replaceFirst('{n}', '$value');

/// Two-slot template (`{n}` then `{m}`).
String tr2(String template, Object first, Object second) => tr(template)
    .replaceFirst('{n}', '$first')
    .replaceFirst('{m}', '$second');

final _levelShout = RegExp(r'^LEVEL (\d+)$');
final _springShout = RegExp(r'^SPRING ON STEP (\d+)$');

/// Gameplay shout-outs shown over the canvas. Static shouts translate
/// directly; the two dynamic ones are matched and templated.
String shout(String message) {
  final level = _levelShout.firstMatch(message);
  if (level != null) return trn('LEVEL {n}', level.group(1)!);
  final spring = _springShout.firstMatch(message);
  if (spring != null) return trn('SPRING ON STEP {n}', spring.group(1)!);
  return tr(message);
}

/// Shop catalog display helpers honoring the selected language.
String productName(Product item) =>
    appLang.value == 'ar' && item.arName.isNotEmpty ? item.arName : item.name;
String productDesc(Product item) =>
    appLang.value == 'ar' && item.arDesc.isNotEmpty
    ? item.arDesc
    : item.description;

const _ar = <String, String>{
  // Onboarding.
  'Welcome to Cloud Hop': 'مرحباً بك في كلاود هوب',
  'Choose how to play': 'اختر طريقة اللعب',
  'Swipe': 'السحب',
  'Flick to move and jump': 'اسحب للتحرك والقفز',
  'Joystick': 'عصا التحكم',
  'Hold to hop continuously, drag to steer': 'اضغط باستمرار للقفز المتواصل واسحب للتوجيه',
  'Choose your language': 'اختر لغتك',
  'English': 'الإنجليزية',
  'Arabic': 'العربية',
  'Choose your character': 'اختر شخصيتك',
  'Male': 'ولد',
  'Female': 'بنت',
  'Round male': 'ولد دائري',
  'Round female': 'بنت دائرية',
  'Back': 'رجوع',
  'Next': 'التالي',
  'Start game': 'ابدأ اللعب',
  // Home / menu.
  'CLOUD HOP': 'كلاود هوب',
  'Start': 'ابدأ',
  'Resume': 'استئناف',
  'Play again': 'العب مجدداً',
  'Waiting for host…': 'بانتظار المضيف…',
  'Create a room & invite': 'أنشئ غرفة وادعُ',
  'Swipe up to jump · Diagonal to steer': 'اسحب للأعلى للقفز · وقطرياً للتوجيه',
  'Hold to hop · Drag to steer': 'اضغط للقفز · اسحب للتوجيه',
  'Finding your challenger…': 'جارٍ البحث عن منافس…',
  'Cancel': 'إلغاء',
  'Keep climbing?': 'تواصل التسلق؟',
  'Watch ad · Revive': 'شاهد إعلاناً · إحياء',
  'No thanks': 'لا شكراً',
  'Nice climbing!': 'تسلق رائع!',
  'Shop': 'المتجر',
  'Friends & invitations': 'الأصدقاء والدعوات',
  'Watch ad for 100 coins': 'شاهد إعلاناً مقابل ١٠٠ عملة',
  'Settings': 'الإعدادات',
  // Settings sheet.
  'Make it yours': 'اجعله خاصاً بك',
  'Player name': 'اسم اللاعب',
  'Nature ambience & sound effects': 'أصوات الطبيعة والمؤثرات',
  'Sound effects': 'المؤثرات الصوتية',
  'Voice chat in races': 'الدردشة الصوتية في السباقات',
  'Join room voice automatically (muted)': 'انضم لصوت الغرفة تلقائياً (صامت)',
  'Game mode': 'وضع اللعب',
  'Modes': 'الأوضاع',
  'Choose the mode you want to play': 'اختر الوضع الذي تريد لعبه',
  'Classic': 'كلاسيكي',
  'Arcade': 'أركيد',
  'Race': 'سباق',
  'Climb at your own pace': 'تسلق على وتيرتك الخاصة',
  'Last player standing · three attempts each':
      'آخر لاعب صامد · ثلاث محاولات لكل لاعب',
  'First to the finish · three attempts each':
      'الأول للنهاية · ثلاث محاولات لكل لاعب',
  'Controls': 'التحكم',
  'Country for practice rivals': 'دولة منافسي التدريب',
  'City': 'المدينة',
  'Your player ID': 'معرّف اللاعب الخاص بك',
  'Copy player ID': 'نسخ معرّف اللاعب',
  'Save settings': 'حفظ الإعدادات',
  'Saving…': 'جارٍ الحفظ…',
  'Retry online sync': 'إعادة مزامنة الاتصال',
  'Copy connection details': 'نسخ تفاصيل الاتصال',
  'Could not save on this device. Please retry.':
      'تعذّر الحفظ على هذا الجهاز. حاول مجدداً.',
  'Online profile sync is pending.': 'مزامنة الملف الشخصي معلّقة.',
  'Saved on this device. ': 'تم الحفظ على هذا الجهاز. ',
  'Language': 'اللغة',
  'Playing character': 'شخصية اللعب',
  'Race finish line': 'خط نهاية السباق',
  // Race dialog.
  'Live challenge': 'تحدٍّ مباشر',
  'Arcade · last player standing · 3 attempts each':
      'أركيد · آخر لاعب صامد · ثلاث محاولات لكل لاعب',
  'Race · {n} steps · 3 attempts each':
      'سباق · {n} خطوة · ثلاث محاولات لكل لاعب',
  'Name': 'الاسم',
  'Use the microphone at the bottom-right during gameplay to talk or mute.':
      'استخدم الميكروفون أسفل اليمين أثناء اللعب للتحدث أو الكتم.',
  'Create room': 'إنشاء غرفة',
  'Join room': 'الانضمام لغرفة',
  'Room code': 'رمز الغرفة',
  'Start race': 'ابدأ السباق',
  'Starting together…': 'البدء معاً…',
  'Leave room': 'مغادرة الغرفة',
  'Close': 'إغلاق',
  'Join voice (starts muted)': 'انضم للصوت (يبدأ صامتاً)',
  'Mute microphone': 'كتم الميكروفون',
  'Unmute microphone': 'إلغاء كتم الميكروفون',
  // Results.
  'You win!': 'لقد فزت!',
  'Draw!': 'تعادل!',
  'Out of attempts': 'انتهت المحاولات',
  'WINNER': 'الفائز',
  'DRAW': 'تعادل',
  'VS': 'ضد',
  'steps': 'خطوات',
  'Exit to menu': 'خروج للقائمة',
  'SPECTATING': 'مشاهدة',
  'Watching the round…': 'مشاهدة الجولة…',
  'Watching {n}': 'مشاهدة {n}',
  'Send a diagonal meteor shower': 'أرسل زخة شهب قطرية',
  'Throw Rocks ({n} left)': 'ارمِ الصخور (متبقٍ {n})',
  'Throw Rocks (500 coins each)': 'ارمِ الصخور (٥٠٠ عملة للرشقة)',
  'Play again — same room': 'العب مجدداً — نفس الغرفة',
  'Request rematch': 'طلب إعادة المباراة',
  '{n} want a rematch': '{n} يريدون إعادة المباراة',
  'Mystery rival': 'منافس غامض',
  // Shop.
  'Sky shop': 'متجر السماء',
  'Helpers': 'المساعدات',
  'Skins': 'الأشكال',
  'Skies': 'السماوات',
  'Equipped': 'مجهّز',
  'Equip': 'تجهيز',
  // Friends.
  'Friends & invites': 'الأصدقاء والدعوات',
  'Friend added': 'تمت إضافة الصديق',
  'Friend request sent': 'تم إرسال طلب الصداقة',
  'Room invitations': 'دعوات الغرف',
  '{n} invited you': 'دعاك {n}',
  'Room {n}': 'الغرفة {n}',
  'Join': 'انضمام',
  'Add a friend by ID. Accept their request to exchange room invitations.':
      'أضف صديقاً بالمعرف. اقبل طلبه لتبادل دعوات الغرف.',
  'Friend': 'صديق',
  'Wants to be your friend': 'يريد أن يكون صديقك',
  'Request sent': 'تم إرسال الطلب',
  'Invite': 'دعوة',
  'Done': 'تم',
  'Refresh': 'تحديث',
  'My player ID': 'معرّفي كلاعب',
  'Copy ID': 'نسخ المعرف',
  'Friend’s player ID': 'معرّف اللاعب الصديق',
  'Add friend': 'إضافة صديق',
  'Accept': 'قبول',
  'Decline': 'رفض',
  // Profile.
  'Sign in with Google': 'تسجيل الدخول بجوجل',
  'Google account (signed in)': 'حساب جوجل (مسجّل الدخول)',
  'Sign out': 'تسجيل الخروج',
  'Guest climber': 'متسلق ضيف',
  'Google player': 'لاعب جوجل',
  'Retry Firebase access': 'إعادة محاولة الاتصال',
  'Sign in to sync progress and race online.':
      'سجّل الدخول لمزامنة التقدم والسباق أونلاين.',
  'Linking keeps your current coins and skins.':
      'الربط يحافظ على عملاتك وأشكالك الحالية.',
  // Common toasts/buttons.
  'Room invitation': 'دعوة غرفة',
  'Friend request': 'طلب صداقة',
  '{n} invited you to room {m}': 'دعاك {n} إلى الغرفة {m}',
  '{n} wants to be your friend.': '{n} يريد أن يكون صديقك.',
  'Friend request accepted': 'تم قبول طلب الصداقة',
  'View friends': 'عرض الأصدقاء',
  'Copied': 'تم النسخ',
  'Speaker on': 'السماعة الخارجية مفعّلة',
  'Speaker off (earpiece)': 'السماعة مغلقة (سماعة الأذن)',
  'Watch ad for gift': 'شاهد إعلاناً للحصول على هدية',
  'Turn microphone on': 'تشغيل الميكروفون',
  'Back to home': 'عودة للرئيسية',
  'Rocket': 'صاروخ',
  'Trampoline': 'ترامبولين',
  'Automatic extra life': 'حياة إضافية تلقائية',
  'Each fall uses one owned life, until none remain.':
      'كل سقوط يستهلك حياة مملوكة حتى النفاد.',
  'Everyone starts with three attempts. Inventory lives are not spent.':
      'يبدأ الجميع بثلاث محاولات. حيوات المخزون لا تُستهلك.',
  'In bag:': 'في الحقيبة:',
  '10 steps = 1 coin · Land a flip = 10 coins':
      '١٠ درجات = عملة · اقلب وهبوطك سليم = ١٠ عملات',
  'Watch ad · +100 coins': 'شاهد إعلاناً · +١٠٠ عملة',
  'Google test ads · no live revenue': 'إعلانات تجريبية · بدون أرباح حقيقية',
  'Ad privacy choices': 'خيارات خصوصية الإعلانات',
  'Signing in…': 'جارٍ تسجيل الدخول…',
  'Player': 'لاعب',
  'Room invitation copied': 'تم نسخ دعوة الغرفة',
  'STEP {n} · LV {m}': 'خطوة {n} · مستوى {m}',
  'Last standing': 'آخر صامد',
  'Goal {n}': 'الهدف {n}',
  '{n} · Arcade': '{n} · أركيد',
  'Signed in as {n}': 'تم تسجيل الدخول باسم {n}',
  'Microphone is still off. Tap the mic to retry.':
      'الميكروفون ما زال مغلقاً. اضغط على الميكروفون لإعادة المحاولة.',
  'Voice service is not configured yet. You can keep playing.':
      'خدمة الصوت غير مهيأة بعد. يمكنك مواصلة اللعب.',
  'Voice failed: {n}': 'فشل الصوت: {n}',
  'Voice failed: {n}…': 'فشل الصوت: {n}…',
  'TRAMPOLINE!': 'ترامبولين!',
  'SUPER JUMP!': 'قفزة خارقة!',
  'ROCKET FLIGHT!': 'تحليق الصاروخ!',
  'SPRING ON STEP {n}': 'زنبرك على الدرجة {n}',
  'GIFT: ROCKET': 'هدية: صاروخ',
  'GIFT: EXTRA LIFE': 'هدية: حياة إضافية',
  'GIFT: TRAMPOLINE': 'هدية: ترامبولين',
  'GIFT: +25 COINS': 'هدية: +٢٥ عملة',
  'AD GIFT AVAILABLE': 'هدية إعلانية متاحة',
  'FLIP +10 COINS': 'شقلبة +١٠ عملات',
  'LEVEL {n}': 'المستوى {n}',
  'EXTRA LIFE!': 'حياة إضافية!',
  'REVIVED! KEEP CLIMBING': 'تم الإحياء! واصل التسلق',
  'WALL REBOUND!': 'ارتداد عن الحائط!',
  'ROCKET LOST!': 'فُقد الصاروخ!',
  'KNOCKED DOWN!': 'سقط أرضاً!',
  'KNOCKED OFF!': 'أُسقط من الدرجة!',
  'HIT!': 'إصابة!',
  'FINISH! Waiting for the result…': 'النهاية! بانتظار النتيجة…',
  'REMATCH! GET READY': 'إعادة المباراة! استعد',
  'LIVE RACE CONTINUES': 'السباق المباشر مستمر',
  'LAST PLAYER STANDING': 'آخر لاعب صامد',
  'FIRST TO {n} STEPS': 'الأول إلى {n} درجة',
  '100 coins added': 'تمت إضافة ١٠٠ عملة',
  'Gift collected': 'تم جمع الهدية',
  'No reward earned. Ad may still be loading or was closed early.':
      'لم يتم الحصول على مكافأة. قد يكون الإعلان ما زال يُحمَّل أو أُغلق مبكراً.',
  'Leave the race before opening the shop.':
      'غادر السباق قبل فتح المتجر.',
  'Out of rocks — buy them in the shop before the next round':
      'نفدت الصخور — اشترِ من المتجر قبل الجولة التالية',
  'Throw failed. Rock refunded.': 'فشل الرمي. تم استرداد الصخرة.',
  'Challenger found. Starting together…': 'تم العثور على منافس. البدء معاً…',
  'Match failed to start. Playing practice rival.':
      'تعذّر بدء المباراة. اللعب ضد بوت تدريب.',
  'Found {n} player(s) in other modes. Playing practice rival.':
      'وجدنا {n} لاعباً في أوضاع أخرى. اللعب ضد بوت تدريب.',
  'No players searching. Playing practice rival.':
      'لا يوجد لاعبون يبحثون. اللعب ضد بوت تدريب.',
  'Online match unavailable. Playing a practice rival.':
      'المباراة الأونلاين غير متاحة. اللعب ضد بوت تدريب.',
  '{n} Playing a practice rival.': '{n} اللعب ضد بوت تدريب.',
  '{n} wins!': '{n} يفوز!',
  'Rematch started — same room!': 'بدأت مباراة الإعادة — نفس الغرفة!',
  'Rematch requested · waiting for host':
      'تم طلب الإعادة · بانتظار المضيف',
  'Invite Expired': 'انتهت صلاحية الدعوة',
  'Joining room {n}…': 'جارٍ الانضمام للغرفة {n}…',
  'Could not join room {n}.': 'تعذّر الانضمام للغرفة {n}.',
  '{n} is now your friend': 'أصبح {n} صديقك الآن',
  'Could not accept request.': 'تعذّر قبول الطلب.',
};
