/// 时间显示与分组工具。
library;

String two(int n) => n.toString().padLeft(2, '0');

/// 对话列表的分组标题：今天 / 昨天 / 7 天内 / 30 天内 / 更早。
String conversationGroupLabel(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff < 7) return '7 天内';
  if (diff < 30) return '30 天内';
  return '更早';
}

/// 消息时间：HH:mm。
String formatClock(DateTime time) => '${two(time.hour)}:${two(time.minute)}';

/// 相对时间：刚刚 / N 分钟前 / N 小时前 / M 月 d 日。
String formatRelative(DateTime time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${time.month} 月 ${time.day} 日';
}

/// 导出文件名使用的时间戳：yyyyMMdd-HHmmss。
String fileTimestamp(DateTime time) =>
    '${time.year}${two(time.month)}${two(time.day)}-'
    '${two(time.hour)}${two(time.minute)}${two(time.second)}';

/// 对话标题兜底：取首条用户消息的第一行，最多 24 个字。
String fallbackTitle(String firstUserMessage) {
  final line = firstUserMessage
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .trim();
  final cleaned = line.replaceAll(RegExp(r'[#>*`~]'), '').trim();
  if (cleaned.isEmpty) return '新对话';
  final runes = cleaned.runes.toList();
  if (runes.length <= 24) return cleaned;
  return '${String.fromCharCodes(runes.take(24))}…';
}
