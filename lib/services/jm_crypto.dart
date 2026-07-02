import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

/// JM API 加密解密工具
class JmCrypto {
  /// MD5 哈希
  static String md5Hash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  static Uint8List md5HexBytes(String input) {
    return Uint8List.fromList(utf8.encode(md5Hash(input)));
  }

  /// AES-ECB-PKCS7 解密 (Base64 输入)
  static String? aesEcbDecrypt(String encryptedBase64, Uint8List keyBytes) {
    try {
      // 清理 Base64 字符串
      final cleanBase64 = encryptedBase64
          .trim()
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');

      // 补齐 padding
      final paddingLength = (4 - cleanBase64.length % 4) % 4;
      final paddedBase64 = cleanBase64 + ('=' * paddingLength);

      final key = encrypt.Key(keyBytes);

      // 解密
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.ecb, padding: 'PKCS7'),
      );

      final encrypted = encrypt.Encrypted.fromBase64(paddedBase64);
      final decrypted = encrypter.decrypt(encrypted);

      return decrypted;
    } catch (e) {
      developer.log('AES 解密失败', error: e, name: 'JmCrypto');
      return null;
    }
  }

  /// 尝试用多个种子解密
  static String? tryDecryptWithSeeds(
    String encryptedBase64,
    String timestamp,
    List<String> seeds,
  ) {
    for (final seed in seeds) {
      final key = md5HexBytes('$timestamp$seed');
      final decrypted = aesEcbDecrypt(encryptedBase64, key);
      if (decrypted != null && decrypted.isNotEmpty) {
        try {
          // 尝试解析 JSON 验证解密是否成功
          json.decode(decrypted);
          return decrypted;
        } catch (e) {
          continue;
        }
      }
    }
    return null;
  }
}
