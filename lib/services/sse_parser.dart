/// SSE（Server-Sent Events）行解析器。
///
/// DeepSeek / OpenAI 兼容接口的流式响应是逐行发送的：
///
/// ```
/// data: {"choices":[{"delta":{"content":"你"}}]}
///
/// data: {"choices":[{"delta":{"content":"好"}}]}
///
/// data: [DONE]
/// ```
///
/// 网络层拿到的 chunk 边界与行边界无关，一行可能被拆到两个 chunk，
/// 也可能一个 chunk 里包含多行。因此这里维护一个内部缓冲，
/// 只把「完整的一行」的 `data:` 负载交给调用方。
///
/// 该类不依赖 Flutter，可独立单测：
///
/// ```dart
/// final parser = SseLineParser();
/// parser.feed('data: {"a":1}\n\ndata: [DO');
/// parser.feed('NE]\n'); // => ['{"a":1}', '[DONE]']
/// ```
library;

/// 单次事件（SSE event）的数据负载标记。
const String sseDoneMarker = '[DONE]';

/// SSE 行解析器：把任意切分的文本 chunk 还原成一行行 `data:` 负载。
class SseLineParser {
  /// 尚未凑成完整一行的残留文本。
  String _pending = '';

  /// 当前是否还有未输出的半行数据（主要用于测试断言）。
  bool get hasPending => _pending.isNotEmpty;

  /// 喂入一个（可能不完整的）文本 chunk，返回其中已经完整成行的 data 负载。
  ///
  /// - 空行、注释行（以 `:` 开头）以及非 `data:` 字段会被忽略；
  /// - `data:` 后的第一个空格按 SSE 规范会被去掉；
  /// - `[DONE]` 会作为普通负载返回，由调用方判断结束。
  List<String> feed(String chunk) {
    if (chunk.isEmpty) return const <String>[];
    _pending += chunk;
    final out = <String>[];
    while (true) {
      final newline = _pending.indexOf('\n');
      if (newline < 0) break;
      final line = _pending.substring(0, newline);
      _pending = _pending.substring(newline + 1);
      final data = _dataFromLine(line);
      if (data != null) out.add(data);
    }
    return out;
  }

  /// 流结束时调用：若还有不带换行符的尾行，把它当作一行解析。
  List<String> flush() {
    final rest = _pending;
    _pending = '';
    if (rest.isEmpty) return const <String>[];
    final data = _dataFromLine(rest);
    return data == null ? const <String>[] : <String>[data];
  }

  /// 丢弃未完成的缓冲，准备复用（例如同一实例处理下一次请求）。
  void reset() {
    _pending = '';
  }

  /// 从一行原始文本中提取 `data:` 负载；不是数据行时返回 null。
  String? _dataFromLine(String rawLine) {
    var line = rawLine;
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    line = line.trimLeft();
    if (line.isEmpty) return null; // 空行：事件分隔符
    if (line.startsWith(':')) return null; // 注释行（心跳等）
    if (!line.startsWith('data:')) {
      // event: / id: / retry: 等字段对聊天流无用，直接忽略。
      return null;
    }
    var data = line.substring(5);
    if (data.startsWith(' ')) data = data.substring(1);
    data = data.trim();
    if (data.isEmpty) return null;
    return data;
  }
}

/// 判断一个 data 负载是否为流结束标记。
bool isSseDone(String data) => data.trim() == sseDoneMarker;
