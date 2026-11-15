/// 记忆引擎通用工具（纯 Dart）：
/// - 中英文关键词切分（中文二元组 + 英文小写词干，去停用词）；
/// - 文本相似度（Jaccard + 包含关系），用于记忆去重；
/// - 关键词提取；
/// - 记忆块格式化（拼进 System Prompt 的 Markdown 列表）；
/// - 模型输出的 JSON 容错提取与安全解析。
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../data/models/memory_models.dart';
import '../utils/token_estimator.dart';

/// 记忆块标题：拼进 System Prompt 的第一行。
const String memoryBlockHeader = '【长期记忆】';

/// 重要度达到该阈值时，在记忆块条目末尾标注「（重要）」。
const double importantThreshold = 0.8;

/// 中文停用词（整词）。
const Set<String> zhStopWords = <String>{
  '的',
  '了',
  '是',
  '在',
  '我',
  '你',
  '他',
  '她',
  '它',
  '我们',
  '你们',
  '他们',
  '自己',
  '这',
  '那',
  '这个',
  '那个',
  '这些',
  '那些',
  '这样',
  '那样',
  '什么',
  '怎么',
  '为什么',
  '哪',
  '哪个',
  '可以',
  '应该',
  '需要',
  '然后',
  '因为',
  '所以',
  '如果',
  '但是',
  '已经',
  '现在',
  '时候',
  '一个',
  '一下',
  '一种',
  '这种',
  '那种',
  '以及',
  '等等',
  '只是',
  '就是',
  '还是',
  '还有',
  '没有',
  '不会',
  '不能',
  '不是',
  '一直',
  '一些',
  '有点',
  '非常',
  '比较',
  '可能',
  '觉得',
  '知道',
  '吗',
  '呢',
  '吧',
  '啊',
  '哦',
  '呀',
  '嘛',
  '嗯',
  '哈',
  '着',
  '过',
  '地',
  '得',
};

/// 中文停用「字」：由两个停用字组成的二元组直接丢弃，避免「我的」「就是」这类噪声。
const Set<String> _zhStopChars = <String>{
  '的',
  '了',
  '是',
  '在',
  '我',
  '你',
  '他',
  '她',
  '它',
  '们',
  '这',
  '那',
  '有',
  '和',
  '与',
  '就',
  '都',
  '也',
  '还',
  '把',
  '被',
  '让',
  '给',
  '对',
  '从',
  '到',
  '为',
  '以',
  '及',
  '或',
  '而',
  '但',
  '很',
  '太',
  '更',
  '最',
  '不',
  '没',
  '无',
  '一',
  '个',
  '些',
  '之',
  '其',
  '于',
  '上',
  '下',
  '里',
  '中',
  '并',
  '且',
  '着',
  '过',
  '吗',
  '呢',
  '吧',
  '啊',
  '哦',
  '呀',
  '嘛',
  '嗯',
  '您',
  '咱',
  '会',
  '能',
  '要',
  '想',
  '得',
  '地',
};

/// 英文停用词（已小写、已做轻微词干化）。
const Set<String> enStopWords = <String>{
  'a',
  'an',
  'the',
  'and',
  'or',
  'but',
  'if',
  'then',
  'else',
  'of',
  'in',
  'on',
  'at',
  'to',
  'for',
  'from',
  'by',
  'with',
  'about',
  'into',
  'over',
  'after',
  'before',
  'is',
  'am',
  'are',
  'was',
  'were',
  'be',
  'been',
  'being',
  'do',
  'does',
  'did',
  'have',
  'has',
  'had',
  'will',
  'would',
  'can',
  'could',
  'should',
  'may',
  'might',
  'must',
  'i',
  'you',
  'he',
  'she',
  'it',
  'we',
  'they',
  'me',
  'him',
  'her',
  'us',
  'them',
  'my',
  'your',
  'his',
  'its',
  'our',
  'their',
  'this',
  'that',
  'these',
  'those',
  'there',
  'here',
  'what',
  'which',
  'who',
  'whom',
  'whose',
  'when',
  'where',
  'why',
  'how',
  'not',
  'no',
  'yes',
  'so',
  'very',
  'just',
  'also',
  'than',
  'too',
  's',
  't',
};

final RegExp _latinWordRe = RegExp(r"[A-Za-z][A-Za-z0-9_+#.\-']*");
final RegExp _nonWordRe = RegExp(r'[^\w\u4e00-\u9fff]+');
final RegExp _spaceRe = RegExp(r'\s+');


/// 判断一个 rune 是否属于 CJK / 假名 / 韩文范围。
bool isCjkRune(int rune) {
  return (rune >= 0x4E00 && rune <= 0x9FFF) || // 基本汉字
      (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展 A
      (rune >= 0x3040 && rune <= 0x30FF) || // 日文假名
      (rune >= 0xAC00 && rune <= 0xD7AF); // 韩文
}

/// 英文轻量词干化（只处理最常见的复数 / 时态 / 副词后缀，避免引入额外依赖）。
String stemEnglish(String word) {
  var w = word.toLowerCase().trim();
  w = w.replaceAll(RegExp(r"['’]s$"), '');
  w = w.replaceAll(_nonWordRe, '');
  if (w.length <= 3) return w;
  if (w.endsWith('ies') && w.length > 4) {
    return '${w.substring(0, w.length - 3)}y';
  }
  if (w.endsWith('sses')) return w.substring(0, w.length - 2);
  if (w.endsWith('ing') && w.length > 5) {
    return _dropDoubledConsonant(w.substring(0, w.length - 3));
  }
  if (w.endsWith('ed') && w.length > 4) {
    return _dropDoubledConsonant(w.substring(0, w.length - 2));
  }
  if (w.endsWith('ly') && w.length > 5) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss') && w.length > 3) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

String _dropDoubledConsonant(String word) {
  if (word.length < 3) return word;
  final last = word[word.length - 1];
  final prev = word[word.length - 2];
  const vowels = 'aeiou';
  if (last == prev && !vowels.contains(last)) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/// 切分文本得到关键词 token 列表（去重、保序）。
///
/// - 英文按单词切分、小写、去停用词、轻量词干化；
/// - 中文按连续片段切二元组（长度 2~4 的片段额外保留整词）；
/// - [includeStopWords] 为 true 时保留停用词（调试 / 测试用）。
List<String> tokenize(String text, {bool includeStopWords = false}) {
  final tokens = <String>[];
  final seen = <String>{};
  if (text.trim().isEmpty) return tokens;

  void addToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return;
    if (!includeStopWords) {
      if (zhStopWords.contains(t) || enStopWords.contains(t)) return;
      final runes = t.runes.toList();
      if (runes.length == 2 &&
          runes.every((r) => isCjkRune(r)) &&
          _zhStopChars.contains(String.fromCharCode(runes[0])) &&
          _zhStopChars.contains(String.fromCharCode(runes[1]))) {
        return;
      }
    }
    if (seen.add(t)) tokens.add(t);
  }

  // 英文 / 数字 / 技术词。
  for (final match in _latinWordRe.allMatches(text.toLowerCase())) {
    final raw = match.group(0);
    if (raw == null) continue;
    final stem = stemEnglish(raw);
    if (stem.isEmpty) continue;
    if (!includeStopWords && enStopWords.contains(stem)) continue;
    if (seen.add(stem)) tokens.add(stem);
  }

  // 中文连续片段：二元组 + 短整词。
  final run = <int>[];
  void flush() {
    if (run.isEmpty) return;
    final chars = run.map((rune) => String.fromCharCode(rune)).toList();
    if (chars.length == 1) {
      addToken(chars.first);
    } else {
      for (var i = 0; i + 1 < chars.length; i++) {
        addToken(chars[i] + chars[i + 1]);
      }
      if (chars.length <= 4) addToken(chars.join());
    }
    run.clear();
  }

  for (final rune in text.runes) {
    if (isCjkRune(rune)) {
      run.add(rune);
    } else {
      flush();
    }
  }
  flush();
  return tokens;
}

/// 文本 token 集合（便于 Jaccard 计算）。
Set<String> tokenSet(String text) => tokenize(text).toSet();

/// 文本相似度 0~1：Jaccard 相似度 + 包含关系（子串 / 集合包含）。
///
/// 记忆去重依赖该分数：完全相同返回 1；一方包含另一方时至少 0.85；
/// 其他情况按 `0.55 * Jaccard + 0.45 * 重叠系数` 计算。
double textSimilarity(String a, String b) {
  final na = _normalizeForSimilarity(a);
  final nb = _normalizeForSimilarity(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;

  if (na.contains(nb) || nb.contains(na)) {
    final shortLen = math.min(na.length, nb.length);
    final longLen = math.max(na.length, nb.length);
    final ratio = shortLen / longLen;
    return (0.85 + 0.1 * ratio).clamp(0.0, 0.99).toDouble();
  }

  final ta = tokenSet(a);
  final tb = tokenSet(b);
  if (ta.isEmpty || tb.isEmpty) return 0;
  final intersection = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  if (union == 0) return 0;
  final jaccard = intersection / union;
  final containment = intersection / math.min(ta.length, tb.length);
  return (0.55 * jaccard + 0.45 * containment).clamp(0.0, 1.0).toDouble();
}

String _normalizeForSimilarity(String text) =>
    text.trim().toLowerCase().replaceAll(_nonWordRe, '');

/// 关键词与查询 token 的重叠比例 0~1。
///
/// 支持：英文大小写无关、中文包含关系（双向子串，长度 >= 2 才算）。
double keywordOverlap(Set<String> queryTokens, Iterable<String> keywords) {
  if (queryTokens.isEmpty) return 0;
  final normalized = <String>[];
  for (final keyword in keywords) {
    final key = keyword.trim().toLowerCase();
    if (key.isNotEmpty) normalized.add(key);
  }
  if (normalized.isEmpty) return 0;
  var hit = 0;
  for (final token in queryTokens) {
    if (token.isEmpty) continue;
    if (normalized.any((key) => tokenMatchesKey(key, token))) hit++;
  }
  return (hit / queryTokens.length).clamp(0.0, 1.0).toDouble();
}

/// 判断查询 token 是否命中某个关键词 / 文本片段。
bool tokenMatchesKey(String key, String token) {
  if (key == token) return true;
  final keyIsCjk = key.runes.isNotEmpty && isCjkRune(key.runes.first);
  final tokenIsCjk = token.runes.isNotEmpty && isCjkRune(token.runes.first);
  if (keyIsCjk || tokenIsCjk) {
    if (token.length >= 2 && key.contains(token)) return true;
    if (key.length >= 2 && token.contains(key)) return true;
    return false;
  }
  // 纯英文：词干化后相等即可（已由词干化处理复数 / 时态），避免 "art" 命中 "dart"。
  return stemEnglish(key) == stemEnglish(token);
}

/// 判断一段文本是否命中某个 token（英文大小写无关 / 中文包含）。
bool textMatchesToken(String text, String token) {
  final t = token.trim().toLowerCase();
  if (t.isEmpty) return false;
  final lower = text.toLowerCase();
  if (lower.contains(t)) return true;
  final isCjk = t.runes.isNotEmpty && isCjkRune(t.runes.first);
  if (isCjk) return false;
  final stem = stemEnglish(t);
  for (final match in _latinWordRe.allMatches(lower)) {
    final word = match.group(0);
    if (word != null && stemEnglish(word) == stem) return true;
  }
  return false;
}

/// 从一段文本中提取关键词（按词频 + 长度加权排序，最多 [maxKeywords] 个）。
///
/// [extra] 中的词（例如实体名）会被直接加入候选并加权，保证专有名词不丢。
List<String> extractKeywords(
  String text, {
  int maxKeywords = 10,
  Iterable<String> extra = const <String>[],
}) {
  if (maxKeywords <= 0) return const <String>[];
  final lower = text.toLowerCase();
  final scores = <String, double>{};
  for (final token in tokenize(text)) {
    final count = _countOccurrences(lower, token);
    final lengthBonus = 1 + 0.12 * math.min(token.length, 6);
    scores[token] = (scores[token] ?? 0) + count * lengthBonus;
  }
  final extras = <String>{};
  for (final item in extra) {
    final normalized = item.trim().toLowerCase();
    if (normalized.isEmpty) continue;
    extras.add(normalized);
    scores[normalized] = (scores[normalized] ?? 0) + 2.0;
  }
  final entries = scores.entries.toList()
    ..sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      final byLength = b.key.length.compareTo(a.key.length);
      if (byLength != 0) return byLength;
      return a.key.compareTo(b.key);
    });
  final result = <String>[];
  for (final entry in entries) {
    if (result.length >= maxKeywords) break;
    result.add(entry.key);
  }
  for (final extraWord in extras) {
    if (result.length >= maxKeywords) break;
    if (!result.contains(extraWord)) result.add(extraWord);
  }
  return result;
}

int _countOccurrences(String text, String token) {
  if (token.isEmpty) return 0;
  var count = 0;
  var index = 0;
  while (true) {
    final found = text.indexOf(token, index);
    if (found < 0) break;
    count++;
    index = found + token.length;
  }
  return count;
}

/// 单条记忆格式化为 Markdown 列表项：
/// `- (偏好) 用户偏好用 Dart 写客户端（重要）`
String formatMemoryLine(MemoryItem item) {
  final marker = item.importance >= importantThreshold ? '（重要）' : '';
  return '- (${item.kind.label}) ${item.content.trim()}$marker';
}

/// 把一组记忆格式化成可直接拼进 System Prompt 的 Markdown 块。
///
/// 固定格式（UI 会据此做引用展示）：
/// ```
/// 【长期记忆】
/// - (偏好) 用户偏好用 Dart 写客户端
/// - (事实) 用户在做 DeepSleep 项目
/// ```
/// 按 [MemoryKind] 分组（同 kind 相邻），组内按重要度、更新时间倒序；
/// 没有记忆时返回空字符串。import 了 token_estimator 供调用方复用（见 [memoryBlockTokenEstimate]）。
String formatMemoryBlock(
  Iterable<MemoryItem> items, {
  String header = memoryBlockHeader,
}) {
  final list = items.toList();
  if (list.isEmpty) return '';
  final groups = <MemoryKind, List<MemoryItem>>{};
  for (final item in list) {
    groups.putIfAbsent(item.kind, () => <MemoryItem>[]).add(item);
  }
  final lines = <String>[];
  for (final kind in MemoryKind.values) {
    final group = groups[kind];
    if (group == null || group.isEmpty) continue;
    group.sort((a, b) {
      final byImportance = b.importance.compareTo(a.importance);
      if (byImportance != 0) return byImportance;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    for (final item in group) {
      lines.add(formatMemoryLine(item));
    }
  }
  if (lines.isEmpty) return '';
  return '$header\n${lines.join('\n')}';
}

/// 估算记忆块的 token 数（含标题）。
int memoryBlockTokenEstimate(
  Iterable<MemoryItem> items, {
  String header = memoryBlockHeader,
}) {
  final block = formatMemoryBlock(items, header: header);
  if (block.isEmpty) return 0;
  return estimateTokens(block);
}

/// 归一化实体 key：小写、去标点、压缩空白，用于实体合并与关系去重。
String normalizeEntityKey(String name) {
  var key = name.trim().toLowerCase();
  key = key.replaceAll(RegExp(r'[\s_\-·]+'), ' ');
  key = key.replaceAll(RegExp(r'[^\w\u4e00-\u9fff ]+'), '');
  return key.replaceAll(_spaceRe, ' ').trim();
}

/// 归一化实体展示名：去首尾空白、压缩连续空白。
String normalizeEntityName(String name) => name.trim().replaceAll(_spaceRe, ' ');

/// 归一化空白（换行 / 制表符 / 多空格 -> 单空格）。
String normalizeWhitespace(String text) => text.replaceAll(_spaceRe, ' ').trim();

/// 把数值限制在 0~1。
double clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

// ---------------------------------------------------------------------------
// JSON 容错解析：模型经常返回 ```json 围栏、前后解释文字、尾逗号等。
// ---------------------------------------------------------------------------

/// 从模型输出中提取第一段完整的 JSON（对象或数组），失败返回 null。
///
/// 处理：```json 围栏、前后废话、字符串内的括号与转义。
String? extractJsonBlock(String raw) {
  if (raw.trim().isEmpty) return null;
  final fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```').firstMatch(raw);
  final candidate = (fence?.group(1) ?? raw).trim();
  final start = _firstJsonStart(candidate);
  if (start < 0) return null;
  final end = _balancedJsonEnd(candidate, start);
  if (end <= start) return null;
  return candidate.substring(start, end + 1);
}

int _firstJsonStart(String text) {
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '{' || ch == '[') return i;
  }
  return -1;
}

int _balancedJsonEnd(String text, int start) {
  final open = text[start];
  if (open != '{' && open != '[') return -1;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{' || ch == '[') {
      depth++;
    } else if (ch == '}' || ch == ']') {
      depth--;
      if (depth == 0) return i;
      if (depth < 0) return -1;
    }
  }
  return -1;
}

/// 宽松解析模型输出：先提取 JSON 块，再尝试去掉尾逗号后重试。
dynamic decodeJsonLoosely(String raw) {
  final block = extractJsonBlock(raw);
  if (block == null) return null;
  try {
    return jsonDecode(block);
  } on FormatException {
    final cleaned = block.replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (match) => match.group(1) ?? '',
    );
    try {
      return jsonDecode(cleaned);
    } on FormatException {
      return null;
    }
  }
}

/// 宽松解析为 JSON 对象；不是对象（例如数组 / 垃圾文本）时返回 null。
Map<String, dynamic>? safeParseJsonObject(String raw) {
  final decoded = decodeJsonLoosely(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return null;
}

/// 读取字符串字段（非字符串时返回 [fallback]）。
String jsonString(dynamic value, {String fallback = ''}) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

/// 读取 double 字段（int / String 数字均兼容）。
double jsonDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// 读取 int 字段。
int jsonInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// 读取字符串数组字段（过滤非字符串、去空白）。
List<String> jsonStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item is String ? item.trim() : '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(RegExp(r'[,，、;；\s]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

/// 读取数组字段；不是数组时返回空列表。
List<dynamic> jsonList(dynamic value) => value is List ? value : const <dynamic>[];
