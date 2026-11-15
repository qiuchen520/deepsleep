import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// ID 与哈希工具。
class Ids {
  Ids._();

  static final Random _random = Random.secure();

  /// 生成一个短小、可排序的本地 ID：<前缀>_<毫秒时间戳 base36><随机 6 位>。
  static String newId([String prefix = 'id']) {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rnd = _random.nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
    return '${prefix}_$ts$rnd';
  }

  /// 生成记忆内容指纹，用于快速去重。
  static String fingerprint(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？、；：,.!?;:（）()\[\]【】"“”\'’]'), '');
    return sha1.convert(utf8.encode(normalized)).toString().substring(0, 16);
  }
}
