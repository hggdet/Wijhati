import Foundation

/// App language: "ar" (default), "en", "ku" (Kurdish Sorani).
/// UI strings are written in Arabic in the code; `String.loc` swaps in the
/// English/Kurdish text from the table when the user picks another language.
/// Strings missing from the table simply stay Arabic.
enum L10n {
    static var lang: String {
        UserDefaults.standard.string(forKey: "wijhati.language") ?? "ar"
    }

    static let table: [String: (en: String, ku: String)] = [
        // Settings list
        "الإعدادات": ("Settings", "ڕێکخستنەکان"),
        "الخريطة والطبقات": ("Map & Layers", "نەخشە و چینەکان"),
        "خرائط بدون إنترنت": ("Offline Maps", "نەخشە بەبێ ئینتەرنێت"),
        "أماكني المحفوظة": ("My Saved Places", "شوێنە پارێزراوەکانم"),
        "الإشعارات": ("Notifications", "ئاگادارکردنەوەکان"),
        "الموقع": ("Location", "شوێن"),
        "اللغة": ("Language", "زمان"),
        "مساعدة وملاحظات": ("Help & Feedback", "یارمەتی و تێبینییەکان"),
        "حول وجهتي": ("About Wijhati", "دەربارەی وجهتي"),
        "إغلاق": ("Close", "داخستن"),
        // Map settings
        "نمط الخريطة": ("Map Style", "شێوازی نەخشە"),
        "النمط": ("Style", "شێواز"),
        "وحدة الحرارة": ("Temperature Unit", "یەکەی گەرمی"),
        "الوحدة": ("Unit", "یەکە"),
        "المظهر": ("Appearance", "ڕووخسار"),
        "شريط التحكم بالزجاج": ("Glass Control Bar", "شریتی کۆنترۆڵی شووشە"),
        "مصمت": ("Solid", "ڕەق"),
        "زجاجي": ("Glassy", "شووشەیی"),
        "وحدة المسافة": ("Distance Unit", "یەکەی مەودا"),
        "المسافة": ("Distance", "مەودا"),
        "طبقات": ("Layers", "چینەکان"),
        "أبنية ثلاثية الأبعاد": ("3D Buildings", "بینا سێ ڕەھەندییەکان"),
        "رادار المطر الحي": ("Live Rain Radar", "ڕاداری بارانی زیندوو"),
        "منطقة الوصول من موقعي": ("Reachable Area From Me", "ناوچەی گەیشتن لە شوێنەکەمەوە"),
        "المدة": ("Duration", "ماوە"),
        // Help page
        "تعليمات الاستخدام": ("How to Use", "ڕێنمایی بەکارھێنان"),
        "أسئلة شائعة": ("Frequently Asked Questions", "پرسیارە دووبارەکان"),
        "ليش بعض أسماء الأماكن خطأ أو ناقصة؟": ("Why are some place names wrong or missing?", "بۆچی ھەندێک ناوی شوێن ھەڵەیە یان کەمە؟"),
        "شلون أبدّل نمط الخريطة؟": ("How do I change the map style?", "چۆن شێوازی نەخشە بگۆڕم؟"),
        "هل يشتغل التطبيق بدون إنترنت؟": ("Does the app work without internet?", "ئایا ئەپەکە بەبێ ئینتەرنێت کار دەکات؟"),
        "شلون أضيف مكاناً مو موجود بالخريطة؟": ("How do I add a place that is not on the map?", "چۆن شوێنێک زیاد بکەم کە لە نەخشەدا نییە؟"),
        "شلون أوصل للبيت أو الشغل بسرعة؟": ("How do I get home or to work quickly?", "چۆن بە خێرایی بگەمە ماڵەوە یان بۆ کار؟"),
        "ليش ما تغيّر وقت المسار بين السيارة والمشي؟": ("Why doesn't the route time change between car and walking?", "بۆچی کاتی ڕێگا لە نێوان ئۆتۆمبێل و پیاسەدا ناگۆڕێت؟"),
        "تواصل ومشاركة": ("Contact & Share", "پەیوەندی و ھاوبەشکردن"),
        "إرسال ملاحظات للمطوّر": ("Send Feedback to the Developer", "تێبینی بنێرە بۆ گەشەپێدەر"),
        "مشاركة التطبيق مع صديق": ("Share the App with a Friend", "ئەپەکە لەگەڵ ھاوڕێیەک ھاوبەش بکە"),
        "من تطوير": ("Developed by", "لە گەشەپێدانی"),
        "عبدالباسط خضير": ("Abdulbasit Khudair", "عبدالباسط خضير"),
        "© 2026 عبدالباسط خضير — جميع الحقوق محفوظة": ("© 2026 Abdulbasit Khudair — All rights reserved", "© 2026 عبدالباسط خضير — ھەموو مافەکان پارێزراون"),
        // About
        "خرائط وملاحة عربية للعالم كله": ("Maps & navigation for the whole world", "نەخشە و ڕێنیشاندان بۆ ھەموو جیھان"),
        "الإصدار": ("Version", "وەشان"),
        "المطوّر": ("Developer", "گەشەپێدەر"),
        "المحرك": ("Engine", "بزوێنەر"),
        "مؤثرات بصرية": ("Visual Effects", "کاریگەرییە بینراوەکان"),
        // Offline
        "تنزيل المنطقة حول موقعي": ("Download the Area Around Me", "ناوچەکەی دەوروبەری شوێنەکەم دابگرە"),
        "المناطق المحمّلة": ("Downloaded Areas", "ناوچە داگیراوەکان"),
        "لا توجد مناطق محمّلة بعد": ("No downloaded areas yet", "ھێشتا ھیچ ناوچەیەک دانەگیراوە"),
        // Location page
        "موقعك الحالي": ("Your Current Location", "شوێنی ئێستات"),
        "خط العرض": ("Latitude", "ھێڵی پانی"),
        "خط الطول": ("Longitude", "ھێڵی درێژی"),
        "الدقة": ("Accuracy", "وردی"),
        "فعّل خدمات الموقع حتى يظهر موقعك هنا": ("Turn on location services so your location appears here", "خزمەتگوزاری شوێن چالاک بکە تا شوێنەکەت لێرە دەربکەوێت"),
        "ركّز الخريطة على موقعي": ("Centre the Map on My Location", "نەخشە لەسەر شوێنەکەم چەق بکە"),
        "فتح إعدادات موقع النظام": ("Open System Location Settings", "ڕێکخستنەکانی شوێنی سیستم بکەوە"),
        // Notifications page
        "كل التنبيهات": ("All Notifications", "ھەموو ئاگادارکردنەوەکان"),
        "تنبيه عند الاقتراب من مكان محفوظ (300م)": ("Alert when near a saved place (300 m)", "ئاگادارکردنەوە کاتێک لە شوێنێکی پارێزراو نزیک دەبیتەوە (٣٠٠م)"),
        "الصوت": ("Sound", "دەنگ"),
        "علوّ صوت المرشد": ("Guide Voice Volume", "بەرزی دەنگی ڕێنیشاندەر"),
        "تجربة الصوت": ("Test the Sound", "دەنگەکە تاقی بکەوە"),
        "فتح إعدادات إشعارات النظام": ("Open System Notification Settings", "ڕێکخستنەکانی ئاگادارکردنەوەی سیستم بکەوە"),
        // Main chrome
        "ابحث عن مكان أو عنوان": ("Search for a place or address", "بگەڕێ بۆ شوێنێک یان ناونیشانێک"),
        "تم": ("Done", "تەواو"),
        "أماكنك المحفوظة": ("Your Saved Places", "شوێنە پارێزراوەکانت"),
        "مسح": ("Clear", "پاککردنەوە"),
        "الاتجاهات": ("Directions", "ڕێنیشاندان"),
        "اتجاهات": ("Directions", "ڕێنیشاندان"),
        "حفظ الموقع": ("Save Place", "شوێنەکە بپارێزە"),
        "محفوظ": ("Saved", "پارێزراوە"),
        "نشر محلي": ("Add Locally", "بە ناوخۆیی زیاد بکە"),
        "توقف": ("Stop", "وەستان"),
        "مشاركة": ("Share", "ھاوبەشکردن"),
        "نسخ الإحداثيات": ("Copy Coordinates", "پۆتانەکان کۆپی بکە"),
        "فتح في خرائط آبل": ("Open in Apple Maps", "لە نەخشەکانی ئەپڵ بکەوە"),
        "ملاحة بالكاميرا": ("Camera Navigation", "ڕێنیشاندان بە کامێرا"),
        "إيقاف الملاحة": ("Stop Navigation", "ڕێنیشاندان بوەستێنە"),
        "أماكن سريعة": ("Quick Places", "شوێنە خێراکان"),
        "البيت": ("Home", "ماڵ"),
        "الشغل": ("Work", "کار"),
        "لا توجد أماكن محفوظة بعد": ("No saved places yet", "ھێشتا ھیچ شوێنێکی پارێزراو نییە"),
        "مفضلة": ("Favourites", "دڵخوازەکان"),
        "حذف": ("Delete", "سڕینەوە"),
        "الطقس عند موقعك": ("Weather at Your Location", "کەشوھەوا لە شوێنەکەت"),
        "خرائط وملاحة عربية أنيقة": ("Elegant maps & navigation", "نەخشە و ڕێنیشاندانی جوان"),
        "من تطوير عبدالباسط خضير": ("Developed by Abdulbasit Khudair", "لە گەشەپێدانی عبدالباسط خضير"),
        // Add-place sheet
        "نشر مكان محلي": ("Add a Local Place", "شوێنێکی ناوخۆیی زیاد بکە"),
        "اسم المكان": ("Place Name", "ناوی شوێن"),
        "مثال: مخبز التنور": ("Example: Al-Tannour Bakery", "نموونە: نانەوای تەنوور"),
        "النوع": ("Type", "جۆر"),
        "معلومة إضافية (اختياري)": ("Extra Info (optional)", "زانیاری زیاتر (ئارەزوومەندانە)"),
        "ساعات الفتح، رقم، وصف قصير…": ("Opening hours, number, short description…", "کاتەکانی کردنەوە، ژمارە، وەسفێکی کورت…"),
        "ينشر لكل مستخدمي وجهتي وينحفظ بجهازك.": ("Shared with all Wijhati users and saved on your device.", "لەگەڵ ھەموو بەکارھێنەرانی وجهتي ھاوبەش دەکرێت و لە ئامێرەکەت دەپارێزرێت."),
        "ينحفظ بجهازك هسه، وينشر للكل من يشتغل السيرفر المشترك.": ("Saved on your device now, and shared with everyone once the shared server is live.", "ئێستا لە ئامێرەکەت دەپارێزرێت، و کاتێک سێرڤەری ھاوبەش کارا بوو لەگەڵ ھەمووان ھاوبەش دەکرێت."),
        "الخريطة": ("Map", "نەخشە"),
        "الوضع العادي": ("Light Mode", "دۆخی ڕووناک"),
        "الوضع الداكن": ("Dark Mode", "دۆخی تاریک"),
        "تلقائي": ("Automatic", "خۆکار"),
        "إلغاء": ("Cancel", "ھەڵوەشاندنەوە"),
        "نشر": ("Post", "بڵاوکردنەوە"),
    ]
}

extension String {
    /// Localized version of this (Arabic) UI string for the chosen app language.
    var loc: String {
        guard let entry = L10n.table[self] else { return self }
        switch L10n.lang {
        case "en": return entry.en
        case "ku": return entry.ku
        default: return self
        }
    }
}
