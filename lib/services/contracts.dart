/// 网络 / 搜索 / 附件 / 导出服务的抽象契约。
library;

import '../data/models/chat_models.dart';

/// API 错误分类，用于给出友好的中文提示（对应 Demo 里的错误文案）。
enum ApiErrorKind {
  network,
  auth,
  insufficientBalance,
  rateLimited,
  serverBusy,
  invalidRequest,
  contentFiltered,
  protocol,
  cancelled,
  unknown,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  String get friendlyMessage {
    switch (kind) {
      case ApiErrorKind.network:
        return '网络异常，请检查你的网络状况';
      case ApiErrorKind.auth:
        return 'API Key 无效或已过期，请在设置中更换';
      case ApiErrorKind.insufficientBalance:
        return '账户余额不足，请充值后重试';
      case ApiErrorKind.rateLimited:
        return '请求过于频繁，请稍后再试';
      case ApiErrorKind.serverBusy:
        return '服务器繁忙，请稍后再试';
      case ApiErrorKind.invalidRequest:
        return message.isEmpty ? '请求参数有误，请稍后再试' : message;
      case ApiErrorKind.contentFiltered:
        return '你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。';
      case ApiErrorKind.protocol:
        return '响应解析失败，请稍后再试';
      case ApiErrorKind.cancelled:
        return '已停止生成';
      case ApiErrorKind.unknown:
        return message.isEmpty ? '未知错误，请稍后再试' : message;
    }
  }

  @override
  String toString() => 'ApiException(${kind.name}, $message)';
}

/// 流式聊天事件。
enum StreamEventType {
  reasoning,
  content,
  searchResults,
  usage,
  title,
  error,
  done,
}

class ChatStreamEvent {
  const ChatStreamEvent({
    required this.type,
    this.text = '',
    this.searchHits = const <SearchHit>[],
    this.promptTokens,
    this.completionTokens,
    this.title,
    this.errorMessage,
    this.errorKind,
  });

  final StreamEventType type;
  final String text;
  final List<SearchHit> searchHits;
  final int? promptTokens;
  final int? completionTokens;
  final String? title;
  final String? errorMessage;
  final ApiErrorKind? errorKind;

  static const ChatStreamEvent done = ChatStreamEvent(type: StreamEventType.done);
}

/// 一条发给模型的对话（wire 层）。
class ChatTurn {
  const ChatTurn({required this.role, required this.content});

  final String role; // system / user / assistant
  final String content;
}

class ChatRequest {
  const ChatRequest({
    required this.model,
    required this.messages,
    this.temperature = 1.0,
    this.maxTokens = 4096,
    this.searchHits = const <SearchHit>[],
  });

  final String model;
  final List<ChatTurn> messages;
  final double temperature;
  final int maxTokens;
  final List<SearchHit> searchHits;
}

/// DeepSeek（OpenAI 兼容）API 抽象。
abstract class ChatApi {
  Stream<ChatStreamEvent> streamChat(ChatRequest request);

  /// 非流式补全，用于记忆抽取 / 摘要 / 标题。
  Future<String> completeText({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.3,
    int maxTokens = 1200,
    Duration timeout = const Duration(seconds: 60),
  });

  /// 校验 Key 是否可用（GET /models）。
  Future<void> validateApiKey();

  Future<String> generateTitle({
    required String firstUserMessage,
    String? firstAssistantMessage,
  });

  void dispose();
}

/// 联网搜索抽象。
abstract class WebSearchService {
  bool get isConfigured;

  Future<List<SearchHit>> search(String query, {int maxResults = 5});
}

/// 附件选择与解析抽象。
abstract class AttachmentService {
  Future<List<AttachmentRef>> pickFiles();

  /// 把附件内容拼成可注入提示词的文本（过长会截断）。
  Future<String> buildContext(List<AttachmentRef> attachments);

  bool isSupported(String fileName);
}

/// 会话导出。
abstract class ExportService {
  String conversationToMarkdown(Conversation conversation, List<ChatMessage> messages);

  String conversationToJson(Conversation conversation, List<ChatMessage> messages);

  /// 写入应用文档目录并调起系统分享。
  Future<void> shareTextFile({
    required String fileName,
    required String content,
    String? mimeType,
  });
}

/// 全量备份 / 恢复。
class BackupSummary {
  const BackupSummary({
    required this.conversations,
    required this.messages,
    required this.memories,
    required this.profiles,
    this.version = 1,
  });

  final int conversations;
  final int messages;
  final int memories;
  final int profiles;
  final int version;
}

abstract class BackupService {
  Future<String> exportAll();

  Future<BackupSummary> importAll(String json, {bool replace = false});
}

/// 备份数据的读写抽象（由数据层实现，备份服务只负责序列化与分享）。
abstract class BackupRepository {
  /// 导出所有表的数据（payload 已展开为 Map）。
  Future<Map<String, dynamic>> exportData();

  /// 导入备份数据，返回导入条数统计。
  Future<BackupSummary> importData(
    Map<String, dynamic> data, {
    bool replace = false,
  });
}
