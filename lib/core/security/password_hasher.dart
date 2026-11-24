import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 password hashing with a per-user random salt.
class PasswordHasher {
  final int iterations;
  const PasswordHasher({this.iterations = 12000});

  static String newSalt([int length = 16]) {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(length, (_) => r.nextInt(256)));
  }

  /// Human-friendly recovery code like "K7QM-2XPA-9TRB".
  static String newRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String block() =>
        List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return '${block()}-${block()}-${block()}';
  }

  String hash(String secret, String salt) {
    final key =
        _pbkdf2(utf8.encode(secret), utf8.encode(salt), iterations, 32);
    return base64UrlEncode(key);
  }

  bool verify(String secret, String salt, String expected) =>
      _constantTimeEquals(hash(secret, salt), expected);

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Uint8List _pbkdf2(
      List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength / 32).ceil();
    final out = BytesBuilder();
    for (var i = 1; i <= blocks; i++) {
      final blockIndex = Uint8List(4)
        ..buffer.asByteData().setUint32(0, i, Endian.big);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, keyLength));
  }
}
