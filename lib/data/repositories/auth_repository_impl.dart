import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/security/password_hasher.dart';
import '../../core/utils/validators.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/repositories.dart';
import '../datasources/app_database.dart';

class AuthRepositoryImpl implements AuthRepository {
  final Database db;
  final PasswordHasher hasher;

  AuthRepositoryImpl(this.db, {this.hasher = const PasswordHasher()});

  static String _normAnswer(String a) =>
      normalizeDigits(a).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static String _normCode(String c) =>
      c.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  AppUser _map(Map<String, Object?> r) => AppUser(
        id: r['id'] as int,
        name: r['name'] as String,
        email: r['email'] as String,
        avatarPath: r['avatar_path'] as String?,
        securityQuestion: r['security_question'] as String,
        createdAt: fromMillis(r['created_at'])!,
      );

  void _validate(String? Function(String?) v, String? value) {
    final e = v(value);
    if (e != null) throw AppException(e);
  }

  Future<Map<String, Object?>?> _rowByEmail(String email) async {
    final rows = await db.query('users',
        where: 'email = ?', whereArgs: [email.trim()], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>> _rowById(int id) async {
    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const AppException('err_user_not_found');
    return rows.first;
  }

  @override
  Future<SignUpResult> signUp({
    required String name,
    required String email,
    required String password,
    required String securityQuestion,
    required String securityAnswer,
  }) async {
    _validate(Validators.name, name);
    _validate(Validators.email, email);
    _validate(Validators.password, password);
    _validate(Validators.required, securityQuestion);
    _validate(Validators.required, securityAnswer);
    if (await _rowByEmail(email) != null) {
      throw const AppException('err_email_taken');
    }
    final salt = PasswordHasher.newSalt();
    final code = PasswordHasher.newRecoveryCode();
    final now = DateTime.now();
    final id = await db.insert('users', {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password_hash': hasher.hash(password, salt),
      'salt': salt,
      'security_question': securityQuestion.trim(),
      'security_answer_hash': hasher.hash(_normAnswer(securityAnswer), salt),
      'recovery_code_hash': hasher.hash(_normCode(code), salt),
      'created_at': toMillis(now),
    });
    return SignUpResult(_map(await _rowById(id)), code);
  }

  @override
  Future<AppUser> login(String email, String password) async {
    _validate(Validators.email, email);
    _validate(Validators.required, password);
    final r = await _rowByEmail(email);
    if (r == null ||
        !hasher.verify(password, r['salt'] as String, r['password_hash'] as String)) {
      throw const AppException('err_invalid_credentials');
    }
    return _map(r);
  }

  @override
  Future<AppUser?> getUser(int id) async {
    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<AppUser> updateProfile(int userId,
      {String? name, String? email, String? avatarPath}) async {
    final values = <String, Object?>{};
    if (name != null) {
      _validate(Validators.name, name);
      values['name'] = name.trim();
    }
    if (email != null) {
      _validate(Validators.email, email);
      final existing = await _rowByEmail(email);
      if (existing != null && existing['id'] != userId) {
        throw const AppException('err_email_taken');
      }
      values['email'] = email.trim().toLowerCase();
    }
    if (avatarPath != null) values['avatar_path'] = avatarPath;
    if (values.isNotEmpty) {
      await db.update('users', values, where: 'id = ?', whereArgs: [userId]);
    }
    return _map(await _rowById(userId));
  }

  @override
  Future<void> changePassword(
      int userId, String current, String newPassword) async {
    _validate(Validators.password, newPassword);
    final r = await _rowById(userId);
    final salt = r['salt'] as String;
    if (!hasher.verify(current, salt, r['password_hash'] as String)) {
      throw const AppException('err_wrong_password');
    }
    await db.update('users', {'password_hash': hasher.hash(newPassword, salt)},
        where: 'id = ?', whereArgs: [userId]);
  }

  @override
  Future<String> securityQuestionFor(String email) async {
    _validate(Validators.email, email);
    final r = await _rowByEmail(email);
    if (r == null) throw const AppException('err_user_not_found');
    return r['security_question'] as String;
  }

  @override
  Future<void> resetPassword({
    required String email,
    String? securityAnswer,
    String? recoveryCode,
    required String newPassword,
  }) async {
    _validate(Validators.password, newPassword);
    final r = await _rowByEmail(email);
    if (r == null) throw const AppException('err_user_not_found');
    final salt = r['salt'] as String;
    var ok = false;
    if (securityAnswer != null && securityAnswer.trim().isNotEmpty) {
      ok = hasher.verify(_normAnswer(securityAnswer), salt,
          r['security_answer_hash'] as String);
    }
    if (!ok && recoveryCode != null && recoveryCode.trim().isNotEmpty) {
      ok = hasher.verify(
          _normCode(recoveryCode), salt, r['recovery_code_hash'] as String);
    }
    if (!ok) throw const AppException('err_recovery_failed');
    await db.update('users', {'password_hash': hasher.hash(newPassword, salt)},
        where: 'id = ?', whereArgs: [r['id']]);
  }

  @override
  Future<String> regenerateRecoveryCode(int userId, String password) async {
    final r = await _rowById(userId);
    final salt = r['salt'] as String;
    if (!hasher.verify(password, salt, r['password_hash'] as String)) {
      throw const AppException('err_wrong_password');
    }
    final code = PasswordHasher.newRecoveryCode();
    await db.update('users', {'recovery_code_hash': hasher.hash(_normCode(code), salt)},
        where: 'id = ?', whereArgs: [userId]);
    return code;
  }

  @override
  Future<void> deleteAccount(int userId, String password) async {
    final r = await _rowById(userId);
    if (!hasher.verify(password, r['salt'] as String, r['password_hash'] as String)) {
      throw const AppException('err_wrong_password');
    }
    // ON DELETE CASCADE removes projects, tasks, subtasks, tags, attachments,
    // habits and habit logs that belong to this user.
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }
}
