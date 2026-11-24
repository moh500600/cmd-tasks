/// Pure validation helpers; each returns a localisation key on error or null.
class Validators {
  static final _email = RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$');

  static String? required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'v_required' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'v_required';
    return _email.hasMatch(v.trim()) ? null : 'v_email';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'v_required';
    if (v.length < 6) return 'v_password_short';
    return null;
  }

  static String? name(String? v) {
    if (v == null || v.trim().isEmpty) return 'v_required';
    if (v.trim().length < 2) return 'v_name_short';
    if (v.trim().length > 60) return 'v_too_long';
    return null;
  }

  static String? title(String? v) {
    if (v == null || v.trim().isEmpty) return 'v_required';
    if (v.trim().length > 200) return 'v_too_long';
    return null;
  }

  static String? optionalNumber(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(normalizeDigits(v.trim()));
    if (n == null || n < 0) return 'v_number';
    return null;
  }

  static String? url(String? v) {
    if (v == null || v.trim().isEmpty) return 'v_required';
    final u = Uri.tryParse(v.trim());
    if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) {
      return 'v_url';
    }
    return null;
  }
}

/// Converts Arabic-Indic and Persian digits to ASCII digits.
String normalizeDigits(String input) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in input.split('')) {
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}
