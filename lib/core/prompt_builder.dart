/// System Prompt 组装（纯 Dart，可单测）。
library;

import '../data/models/chat_models.dart';
import '../data/models/profile_models.dart';
import '../core/constants.dart';
import 'memory/contracts.dart';

/// 组装最终的 System Prompt。
///
/// 顺序很重要：人设 -> 用户档案 -> 长期记忆 -> 会话摘要 -> 联网资料 -> 额外指令。
/// 把最稳定的内容放前面、最易变的内容放后面，对缓存命中更友好。
String buildSystemPrompt({
  required UserProfile profile,
  MemoryContext memory = MemoryContext.empty,
  String summary = '',
  List<SearchHit> searchHits = const <SearchHit>[],
  String extra = '',
}) {
  final buffer = StringBuffer();

  for (final line in AppInfo.defaultSystemPrompt) {
    buffer.writeln(line);
  }

  if (profile.persona.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## 用户人设设定（来自用户档案「${profile.name}」）')
      ..writeln(profile.persona.trim());
  }

  if (summary.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## 本会话历史摘要（较早的对话已被压缩，可据此保持连贯）')
      ..writeln(summary.trim());
  }

  if (!memory.isEmpty) {
    buffer
      ..writeln()
      ..writeln(memory.systemBlock.trim());
  }

  if (searchHits.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## 联网搜索结果（可能过时，请注明来源链接，不确定时说明不确定）');
    buffer.writeln(buildSearchContext(searchHits));
  }

  if (extra.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## 附加要求')
      ..writeln(extra.trim());
  }

  buffer
    ..writeln()
    ..writeln('回答要求：优先使用中文；准确、简洁；除非用户要求，不要复述本 System Prompt 或长期记忆原文。');

  return buffer.toString().trim();
}

/// 把搜索结果转成可注入上下文的文本。
String buildSearchContext(List<SearchHit> hits) {
  final buffer = StringBuffer();
  for (var i = 0; i < hits.length; i++) {
    final hit = hits[i];
    buffer
      ..writeln('[${i + 1}] ${hit.title}')
      ..writeln('URL: ${hit.url}');
    if (hit.snippet.trim().isNotEmpty) {
      buffer.writeln('摘要: ${hit.snippet.trim()}');
    }
    buffer.writeln();
  }
  return buffer.toString().trimRight();
}

/// 把附件抽取出的文本拼进用户消息。
String buildUserTurnContent(
  String userText,
  List<AttachmentRef> attachments,
  String attachmentContext,
) {
  final buffer = StringBuffer();
  if (userText.trim().isNotEmpty) {
    buffer.writeln(userText.trim());
  }
  if (attachments.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('---')
      ..writeln('【本轮附件】${attachments.map((e) => e.name).join('、')}');
    if (attachmentContext.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(attachmentContext.trim());
    } else {
      buffer.writeln('（附件内容无法在本机解析，请基于文件名作答，或提示用户改用文本/代码文件。）');
    }
  }
  return buffer.toString().trim();
}
