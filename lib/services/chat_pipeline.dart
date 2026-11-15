/// 聊天主流水线：检索记忆 -> 组装 Prompt -> 调模型 -> 记忆回写 -> 上下文压缩。
///
/// 这一层是「后端逻辑」的核心，与 UI 解耦，方便替换模型/记忆后端。
library;

import 'dart:async';

import '../core/constants.dart';
import '../core/memory/contracts.dart';
import '../core/prompt_builder.dart';
import '../core/utils/token_estimator.dart';
import '../data/models/chat_models.dart';
import '../data/models/profile_models.dart';
import 'contracts.dart';

/// 一次请求准备好的上下文。
class PreparedTurn {
  const PreparedTurn({
    required this.messages,
    required this.systemPrompt,
    required this.memory,
    required this.searchHits,
    required this.promptTokens,
    this.searchError,
  });

  final List<ChatTurn> messages;
  final String systemPrompt;
  final MemoryContext memory;
  final List<SearchHit> searchHits;
  final int promptTokens;
  final String? searchError;

  bool get hasMemory => !memory.isEmpty;
}

class ChatPipeline {
  ChatPipeline({
    required this.api,
    required this.memory,
    required this.search,
  });

  final ChatApi api;
  final MemoryEngine memory;
  final WebSearchService search;

  /// 准备一轮对话：联网检索（可选）+ 记忆召回 + Prompt 组装。
  Future<PreparedTurn> prepare({
    required UserProfile profile,
    required Conversation conversation,
    required List<ChatMessage> history,
    required String userText,
    required AppSettings settings,
    List<AttachmentRef> attachments = const <AttachmentRef>[],
    String attachmentContext = '',
    bool? searchEnabledOverride,
    bool appendUserTurn = true,
  }) async {
    final useSearch =
        searchEnabledOverride ?? settings.searchEnabled;
    final userId = profile.id;

    // 1) 记忆召回（失败不影响主流程）
    var memoryContext = MemoryContext.empty;
    if (settings.memoryEnabled) {
      try {
        memoryContext = await memory.retrieve(
          userId: userId,
          query: _buildMemoryQuery(userText, history),
          tokenBudget: settings.memoryTokenBudget,
          sessionId: conversation.id,
        );
      } catch (_) {
        memoryContext = MemoryContext.empty;
      }
    }

    // 2) 联网搜索（可选）
    var searchHits = <SearchHit>[];
    String? searchError;
    if (useSearch && search.isConfigured) {
      try {
        searchHits = await search
            .search(userText, maxResults: settings.searchMaxResults)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        searchError = e is ApiException ? e.friendlyMessage : '联网搜索暂不可用';
      }
    } else if (useSearch && !search.isConfigured) {
      searchError = '未配置联网搜索 API Key';
    }

    // 3) 组装 System Prompt
    final systemPrompt = buildSystemPrompt(
      profile: profile,
      memory: memoryContext,
      summary: conversation.summary,
      searchHits: searchHits,
      extra: settings.systemPromptExtra,
    );

    // 4) 历史消息（跳过已被摘要覆盖的部分）
    final historyTurns = <ChatTurn>[];
    for (final msg in history) {
      if (msg.role == MessageRole.system) continue;
      if (msg.status == MessageStatus.failed) continue;
      if (msg.isEmpty && msg.attachments.isEmpty) continue;
      if (_isCompressed(msg, conversation)) continue;
      final content = _messageToWire(msg);
      if (content.trim().isEmpty) continue;
      historyTurns.add(
        ChatTurn(role: msg.role.wireName, content: content),
      );
    }

    final currentContent = buildUserTurnContent(
      userText,
      attachments,
      attachmentContext,
    );

    final messages = <ChatTurn>[
      ChatTurn(role: 'system', content: systemPrompt),
      ...historyTurns.map(
        (turn) => ChatTurn(role: turn.role, content: turn.content),
      ),
      if (appendUserTurn) ChatTurn(role: 'user', content: currentContent),
    ];

    final promptTokens = _estimatePromptTokens(messages);

    return PreparedTurn(
      messages: messages,
      systemPrompt: systemPrompt,
      memory: memoryContext,
      searchHits: searchHits,
      promptTokens: promptTokens,
      searchError: searchError,
    );
  }

  /// 真正发起流式请求。
  Stream<ChatStreamEvent> stream(
    PreparedTurn turn, {
    required String model,
    double temperature = 1.0,
    int maxTokens = 4096,
  }) {
    return api.streamChat(
      ChatRequest(
        model: model,
        messages: turn.messages,
        temperature: temperature,
        maxTokens: maxTokens,
        searchHits: turn.searchHits,
      ),
    );
  }

  /// 对话结束后回写记忆（后台执行，失败只记录）。
  Future<IngestResult> remember({
    required String userId,
    required String sessionId,
    required String userMessage,
    required String assistantMessage,
    required bool enabled,
    String? userMessageId,
    String? assistantMessageId,
  }) async {
    if (!enabled || assistantMessage.trim().isEmpty) {
      return const IngestResult(skippedByUser: true);
    }
    try {
      return await memory.ingest(
        userId: userId,
        sessionId: sessionId,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        userMessageId: userMessageId,
        assistantMessageId: assistantMessageId,
      );
    } catch (e) {
      return IngestResult(errors: <String>['记忆更新失败：$e']);
    }
  }

  /// 上下文超过阈值时压缩前半段。
  Future<CompressionResult> maybeCompress({
    required Conversation conversation,
    required List<ChatMessage> messages,
    required int threshold,
  }) async {
    if (messages.length <= AppInfo.keepRecentMessages + 1) {
      return CompressionResult.notNeeded;
    }
    return memory.compress(
      sessionId: conversation.id,
      existingSummary: conversation.summary,
      messages: messages,
      threshold: threshold,
      keepRecent: AppInfo.keepRecentMessages,
    );
  }

  /// AI 生成会话标题（失败返回空串，由 UI 兜底）。
  Future<String> suggestTitle({
    required String firstUserMessage,
    String? firstAssistantMessage,
  }) async {
    try {
      return (await api.generateTitle(
        firstUserMessage: firstUserMessage,
        firstAssistantMessage: firstAssistantMessage,
      ))
          .trim();
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  String _buildMemoryQuery(String userText, List<ChatMessage> history) {
    final buffer = StringBuffer(userText.trim());
    // 带上最近两条用户消息，帮助消解「它/这个」之类指代。
    final recentUserMessages = history.reversed
        .where((m) => m.role == MessageRole.user)
        .take(2)
        .toList();
    for (final msg in recentUserMessages) {
      final text = msg.content.trim();
      if (text.isEmpty) continue;
      buffer
        ..writeln()
        ..write(text.length > 200 ? text.substring(0, 200) : text);
    }
    return buffer.toString();
  }

  String _messageToWire(ChatMessage msg) {
    final buffer = StringBuffer(msg.displayContent.trim());
    if (msg.attachments.isNotEmpty) {
      buffer.writeln();
      for (final a in msg.attachments) {
        final text = a.extractedText?.trim();
        if (text != null && text.isNotEmpty) {
          buffer
            ..writeln()
            ..writeln('【附件：${a.name}】')
            ..writeln(text);
        } else {
          buffer.writeln('【附件：${a.name}（内容未解析）】');
        }
      }
    }
    return buffer.toString();
  }

  bool _isCompressed(ChatMessage msg, Conversation conversation) {
    if (conversation.compressedUntilMessageId == null) return false;
    // 压缩标记由控制器在生成摘要后同步写入消息的 compressed 字段。
    return msg.compressed;
  }

  int _estimatePromptTokens(List<ChatTurn> messages) {
    var total = 0;
    for (final m in messages) {
      total += estimateTokens(m.content) + 4;
    }
    return total;
  }
}
