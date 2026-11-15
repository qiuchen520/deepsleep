/// 记忆流水线提示词（纯 Dart）：
/// - 记忆抽取（严格 JSON 输出）；
/// - 会话摘要（上下文压缩）；
/// - 标题生成。
///
/// 所有提示词要求模型「只输出 JSON / 只输出标题」，解析侧仍做容错。
library;

import '../../data/models/chat_models.dart';
import '../../data/models/memory_models.dart';
import '../constants.dart';
import '../utils/token_estimator.dart';

/// 记忆抽取 System Prompt：要求输出严格 JSON。
const String memoryExtractionSystemPrompt = '''
你是 DeepSleep 的长期记忆抽取器。你的任务是从一轮对话中抽取值得跨会话长期记住的信息，并只输出一个 JSON 对象。

输出格式（严格按此结构，只输出 JSON，不要解释、不要 Markdown 围栏）：
{
  "memories": [
    {
      "kind": "fact",
      "content": "用户偏好用 Dart 写客户端",
      "keywords": ["dart", "客户端", "偏好"],
      "entities": ["Dart"],
      "importance": 0.6,
      "confidence": 0.8,
      "subject": "用户",
      "predicate": "偏好技术栈",
      "object": "Dart",
      "action": "add"
    }
  ],
  "entities": [
    {"name": "Dart", "type": "technology"}
  ],
  "relations": [
    {"source": "用户", "relation": "偏好", "target": "Dart"}
  ]
}

字段说明：
- kind：只能是 fact（客观事实）、preference（偏好）、profile（档案/身份）、event（事件）、task（任务/待办）、relation（实体关系）之一；
- content：一句简洁的中文陈述，尽量以「用户」为主语，一条只表达一个事实；
- keywords：2~6 个检索关键词，小写英文或中文词；
- entities：该记忆涉及的实体名称（人名、项目、技术、地点、组织等）；
- importance：0~1，长期稳定的偏好/档案给 0.7~0.9，临时信息给 0.3~0.5；
- confidence：0~1，对抽取结果的确信程度；
- subject / predicate / object：简短的结构化三元组，用于冲突检测（同一 subject+predicate 但 object 不同视为冲突）；
- action：add（新增）、update（补充/修正已有记忆）、supersede（新信息推翻旧信息）。

抽取规则：
1. 只抽取有长期价值、跨会话仍然成立的信息（偏好、身份、长期目标、重要事实、关系、待办）；
2. 不要记录寒暄、一次性闲聊、临时数字、对本次回答无长期意义的细节；
3. 不要把助手的推测当成用户事实；不确定时降低 confidence；
4. 已有记忆列表仅用于去重与冲突判断，不要原样重复输出已有记忆；
5. 若新信息与已有记忆冲突（同一 subject+predicate、object 不同），action 用 supersede；
6. 若只是补充或修正已有记忆，action 用 update；
7. 没有可记录内容时输出 {"memories":[],"entities":[],"relations":[]}。

只输出 JSON，不要输出任何其它文字。''';

/// 会话摘要 System Prompt（上下文压缩用）。
const String conversationSummarySystemPrompt = '''
你是 DeepSleep 的对话压缩器。你会收到一段较早的对话记录（可能还有上一轮摘要），请把它压缩成一段简洁的中文摘要。

要求：
1. 只输出摘要正文，不要输出 JSON、标题、Markdown 围栏或任何解释；
2. 保留：用户的目标与需求、已达成的结论与决定、重要的技术细节与约束、未完成的待办、用户的偏好；
3. 丢弃：寒暄、重复内容、无关紧要的过程细节；
4. 使用第三人称、信息密度高的短句，可以分条（用「- 」开头），总长度不超过 700 字；
5. 如果提供了「已有摘要」，请把它和新对话合并成一段完整摘要，不要丢掉旧摘要里的关键信息；
6. 不要编造对话中没有出现的信息。''';

/// 标题生成 System Prompt。
const String titleSystemPrompt = '''
你是对话标题生成器。请根据用户的第一条消息和助手的回复，生成一个简短的中文标题。

要求：
1. 只输出标题本身，不要引号、不要标点结尾、不要解释；
2. 不超过 18 个汉字（英文按单词计），概括对话主题；
3. 不要出现「对话」「聊天」「关于」等无信息量的词。''';

/// 构造记忆抽取的 User Prompt。
String buildMemoryExtractionPrompt({
  required String userMessage,
  required String assistantMessage,
  List<MemoryItem> existingMemories = const <MemoryItem>[],
  int maxExisting = 20,
}) {
  final buffer = StringBuffer();
  buffer.writeln('## 已有记忆（用于去重与冲突判断，按重要度排序）');
  if (existingMemories.isEmpty) {
    buffer.writeln('（暂无）');
  } else {
    final list = existingMemories.take(maxExisting).toList();
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      final triple = _formatTriple(item);
      buffer.writeln(
        '${i + 1}. [${item.kind.name}] ${item.content.trim()}$triple',
      );
    }
  }
  buffer.writeln();
  buffer.writeln('## 本轮对话');
  buffer.writeln('用户：${truncateToTokens(userMessage.trim(), 1400)}');
  buffer.writeln('助手：${truncateToTokens(assistantMessage.trim(), 1400)}');
  buffer.writeln();
  buffer.writeln('请严格按约定 JSON 格式输出抽取结果。只输出 JSON。');
  return buffer.toString();
}

String _formatTriple(MemoryItem item) {
  final subject = item.subject?.trim() ?? '';
  final predicate = item.predicate?.trim() ?? '';
  final object = item.object?.trim() ?? '';
  if (subject.isEmpty || predicate.isEmpty || object.isEmpty) return '';
  return '（$subject | $predicate | $object）';
}

/// 构造会话摘要的 User Prompt。
///
/// [messages] 为待压缩的较早消息（调用方已按 keepRecent 切好）；
/// [existingSummary] 是上一轮摘要，会与本次摘要合并。
String buildConversationSummaryPrompt({
  required String existingSummary,
  required List<ChatMessage> messages,
  int budgetTokens = AppInfo.summaryTokenBudget,
}) {
  final buffer = StringBuffer();
  buffer.writeln('## 已有摘要（若为空说明这是第一次压缩）');
  final summary = existingSummary.trim();
  if (summary.isEmpty) {
    buffer.writeln('（无）');
  } else {
    buffer.writeln(truncateToTokens(summary, budgetTokens ~/ 2));
  }
  buffer.writeln();
  buffer.writeln('## 待压缩的对话记录');
  if (messages.isEmpty) {
    buffer.writeln('（无）');
  } else {
    for (final message in messages) {
      final role = _roleLabel(message.role);
      final content = message.content.trim();
      if (content.isEmpty) continue;
      buffer.writeln('$role：${truncateToTokens(content, 500)}');
    }
  }
  buffer.writeln();
  buffer.writeln('请输出合并后的中文摘要（纯文本，不要 JSON）。');
  return buffer.toString();
}

String _roleLabel(MessageRole role) => switch (role) {
      MessageRole.user => '用户',
      MessageRole.assistant => '助手',
      MessageRole.system => '系统',
    };

/// 构造标题生成的 User Prompt。
String buildTitlePrompt({
  required String userMessage,
  required String assistantMessage,
  int maxChars = 18,
}) {
  return '用户的第一条消息：\n'
      '${truncateToTokens(userMessage.trim(), 400)}\n\n'
      '助手的回复：\n'
      '${truncateToTokens(assistantMessage.trim(), 400)}\n\n'
      '请生成不超过 $maxChars 个汉字的标题，只输出标题本身。';
}
