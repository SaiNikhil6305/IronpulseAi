/// Reusable form validators. Each returns an error message or null.
class Validators {
  const Validators._();

  static final _email = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$");

  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(s)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Enter a password.';
    if (s.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  static String? Function(String?) confirm(String Function() original) =>
      (v) => v != original() ? 'Passwords do not match.' : null;

  static String? required(String? v, {String field = 'This field'}) =>
      (v == null || v.trim().isEmpty) ? '$field is required.' : null;

  static String? Function(String?) maxLength(int n) =>
      (v) => (v != null && v.length > n) ? 'Keep it under $n characters.' : null;

  /// Optional numeric field within [min, max]. Accepts comma decimals.
  static String? Function(String?) number({double? min, double? max, bool optional = true, bool integer = false}) {
    return (v) {
      final s = (v ?? '').trim().replaceAll(',', '.');
      if (s.isEmpty) return optional ? null : 'Required.';
      final n = integer ? int.tryParse(s)?.toDouble() : double.tryParse(s);
      if (n == null) return integer ? 'Enter a whole number.' : 'Enter a number.';
      if (min != null && n < min) return 'Must be at least ${_fmt(min)}.';
      if (max != null && n > max) return 'Must be at most ${_fmt(max)}.';
      return null;
    };
  }

  static double? parseNum(String? v) {
    final s = (v ?? '').trim().replaceAll(',', '.');
    return s.isEmpty ? null : double.tryParse(s);
  }

  static String _fmt(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}
