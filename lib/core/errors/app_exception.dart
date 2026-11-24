/// Domain-level error with a localisation key so the UI can show a friendly,
/// translated message instead of a raw exception.
class AppException implements Exception {
  final String code; // localisation key, e.g. 'err_email_taken'
  final Object? cause;

  const AppException(this.code, [this.cause]);

  @override
  String toString() => 'AppException($code${cause != null ? ', $cause' : ''})';
}
