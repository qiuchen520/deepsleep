/// 会话导出实现：Markdown / JSON 字符串，以及写入临时文件后系统分享。
///
/// Markdown 结构参考 DeepSeek 官方导出的可读形态：
/// 标题 + 元信息 + 对话摘要 + 逐条消息（思考过程折叠）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/utils/time_utils.dart';
import '../data/models/chat_models.dart';
import 'contracts.dart';

/// 导出服务实现。
class ExportServiceImpl implements ExportService {
  @override
  String conversationToMarkdown(
    Conversation conversation,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer();
    final title = conversation.title.trim().isEmpty
        ? '未命名对话'
        : conversation.title.trim();

    buffer.writeln('# $title');
    buffer.writeln();
    buffer.writeln('- 模型：`${conversation.model}`');
    buffer.writeln('- 创建时间：${_formatDateTime(conversation.createdAt)}');
    buffer.writeln('- 更新时间：${_formatDateTime(conversation.updatedAt)}');
    buffer.writeln('- 消息数：${messages.length}');
    if (conversation.pinned) buffer.writeln('- 已置顶');
    buffer.writeln();

    final summary = conversation.summary.trim();
    if (summary.isNotEmpty) {
      buffer.writeln('## 对话摘要');
      buffer.writeln();
      buffer.writeln(summary);
      buffer.writeln();
    }

    buffer.writeln('## 对话记录');
    buffer.writeln();
    for (final message in messages) {
      _writeMessage(buffer, message);
    }

    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('由 ${AppInfo.appName}（${AppInfo.appNameCn}）导出');
    return buffer.toString();
  }

  @override
  String conversationToJson(
    Conversation conversation,
    List<ChatMessage> messages,
  ) {
    final payload = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'conversation': conversation.toJson(),
      'messages': messages.map((message) => message.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  @override
  Future<void> shareTextFile({
    required String fileName,
    required String content,
    String? mimeType,
  }) async {
    final directory = await getTemporaryDirectory();
    final safeName = _safeFileName(fileName);
    final file = File('${directory.path}/$safeName');
    await file.writeAsString(content, encoding: utf8, flush: true);
    final xfile = XFile(
      file.path,
      mimeType: mimeType ?? _guessMimeType(safeName),
    );
    await Share.shareXFiles(<XFile>[xfile], subject: safeName);
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  void _writeMessage(StringBuffer buffer, ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;
    final label = isUser ? '我' : (isSystem ? '系统' : AppInfo.appName);
    final statusSuffix = switch (message.status) {
      MessageStatus.stopped => '（已停止）',
      MessageStatus.failed => '（生成失败）',
      _ => '',
    };

    buffer.writeln('### $label$statusSuffix');
    buffer.writeln();
    buffer.writeln('> ${_formatDateTime(message.createdAt)}');
    buffer.writeln();

    if (message.attachments.isNotEmpty) {
      buffer.writeln('**附件：**');
      for (final attachment in message.attachments) {
        buffer.writeln(
          '- ${attachment.name}（${attachment.kind.name}，${_formatSize(attachment.size)}）',
        );
      }
      buffer.writeln();
    }

    if (message.searchHits.isNotEmpty) {
      buffer.writeln('**联网搜索来源：**');
      for (final hit in message.searchHits) {
        final hitTitle = hit.title.trim().isEmpty ? hit.url : hit.title.trim();
        buffer.writeln('- [$hitTitle](${hit.url})');
      }
      buffer.writeln();
    }

    final reasoning = message.displayReasoning.trim();
    if (reasoning.isNotEmpty) {
      buffer.writeln('<details>');
      buffer.writeln('<summary>思考过程</summary>');
      buffer.writeln();
      buffer.writeln(reasoning);
      buffer.writeln();
      buffer.writeln('</details>');
      buffer.writeln();
    }

    final content = message.displayContent.trim();
    if (content.isNotEmpty) {
      buffer.writeln(content);
    } else if (message.status == MessageStatus.streaming) {
      buffer.writeln('_（内容未生成完）_');
    } else {
      buffer.writeln('_（空消息）_');
    }
    buffer.writeln();

    if (message.tokens > 0) {
      buffer.writeln('> tokens: ${message.tokens}');
      buffer.writeln();
    }
    buffer.writeln('---');
    buffer.writeln();
  }

  String _formatDateTime(DateTime time) {
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()}KB';
    return '${bytes}B';
  }

  /// 去掉文件名里的路径分隔符与非法字符，并保证有扩展名。
  String _safeFileName(String fileName) {
    var name = fileName.trim();
    if (name.isEmpty) name = 'deepsleep-export.md';
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_');
    if (!name.contains('.')) name = '$name.txt';
    if (name.length > 120) {
      final dot = name.lastIndexOf('.');
      final extension = dot >= 0 ? name.substring(dot) : '';
      final base = dot >= 0 ? name.substring(0, dot) : name;
      final keep = 120 - extension.length;
      final cut = base.isEmpty ? 0 : keep.clamp(1, base.length).toInt();
      name = '${base.substring(0, cut)}$extension';
    }
    return name;
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'text/plain';
  }
}
