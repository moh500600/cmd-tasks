import 'package:flutter/widgets.dart';

import 'strings_ar.dart';
import 'strings_en.dart';

/// Lightweight key-based localisation (Arabic / English).
class L10n {
  static const supported = [Locale('ar'), Locale('en')];

  static String of(String languageCode, String key) {
    final map = languageCode == 'ar' ? stringsAr : stringsEn;
    return map[key] ?? stringsEn[key] ?? key;
  }
}

extension L10nX on BuildContext {
  bool get isAr => Localizations.localeOf(this).languageCode == 'ar';
  String get lang => Localizations.localeOf(this).languageCode;
  String tr(String key) => L10n.of(lang, key);

  /// Replaces {name} placeholders.
  String trf(String key, Map<String, Object> args) {
    var s = tr(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}
