/// 聊天会话状态管理：发送、流式接收、重生成、版本切换、记忆回写、上下文压缩。
///
/// 这是界面上「一切聊天行为」的唯一入口。UI 只调用这里的方法、监听这里的状态。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/memory/contracts.dart';
import '../core/utils/ids.dart';
import '../core/utils/time_utils.dart';
import '../core/utils/token_estimator.dart';
import '../data/db/app_database.dart';
import '../data/models/chat_models.dart';
import '../data/models/profile_models.dart';
import '../services/chat_pipeline.dart';
import '../services/contracts.dart';
import 'settings_controller.dart';

class ConversationController extends ChangeNotifier {
  ConversationController({
    required AppDatabase database,
    required ChatApi api,
    required MemoryEngine memoryEngine,
    required WebSearchService search,
    required AttachmentService attachments,
    required SettingsController settings,
  })  : _db = database,
        _api = api,
        _memoryEngine = memoryEngine,
        _search = search,
        _attachments = attachments,
        _settings = settings {
    _pipeline = ChatPipeline(api: api, memory: memoryEngine, search: search);
    _deepThinking = settings.settings.deepThinking;
    _searchOn = settings.settings.searchEnabled;
  }

  final AppDatabase _db;
  final ChatApi _api;
  final MemoryEngine _memoryEngine;
  final WebSearchService _search;
  final AttachmentService _attachments;
  final SettingsController _settings;
  late final ChatPipeline _pipeline;

  // 列表与当前会话
  List<Conversation> _conversations = <Conversation>[];
  String? _activeId;
  List<ChatMessage> _messages = <ChatMessage>[];
  bool _loading = false;

  // 运行状态
  bool _streaming = false;
  bool _compressing = false;
  bool _remembering = false;
  bool _stopRequested = false;
  bool _disposed = false;

  // 会话内开关
  bool _deepThinking = false;
  bool _searchOn = false;

  // 待发送附件
  List<AttachmentRef> _pendingAttachments = <AttachmentRef>[];

  // 结果与提示
  String? _notice;
  String? _lastError;
  MemoryContext _lastMemory = MemoryContext.empty;
  List<SearchHit> _lastSearchHits = <SearchHit>[];
  CompressionResult? _lastCompression;
  IngestResult? _lastIngest;
  int _contextTokens = 0;

  // 流式缓冲
  String _streamContent = '';
  String _streamReasoning = '';
  List<SearchHit> _streamHits = <SearchHit>[];
  List<String> _streamQueries = <String>[];
  List<SearchHit> _streamVisitedPages = <SearchHit>[];
  List<String> _streamMemoryIds = <String>[];
  int? _streamPromptTokens;
  int? _streamCompletionTokens;
  ChatMessage? _streamingMessage;
  Conversation? _streamConv;
  UserProfile? _streamProfile;
  AppSettings? _streamSettings;
  List<AttachmentRef> _streamAttachments = <AttachmentRef>[];
  String _streamUserText = '';

  StreamSubscription<ChatStreamEvent>? _sub;
  Timer? _saveTimer;

  // ---------------------------------------------------------------------------
  // Getter
  // ---------------------------------------------------------------------------

  bool get loading => _loading;
  bool get streaming => _streaming;
  bool get compressing => _compressing;
  bool get remembering => _remembering;
  bool get deepThinking => _deepThinking;
  bool get searchOn => _searchOn;
  String? get notice => _notice;
  String? get lastError => _lastError;
  MemoryContext get lastMemory => _lastMemory;
  List<SearchHit> get lastSearchHits => _lastSearchHits;
  CompressionResult? get lastCompression => _lastCompression;
  IngestResult? get lastIngest => _lastIngest;
  int get contextTokens => _contextTokens;
  String? get activeId => _activeId;
  List<AttachmentRef> get pendingAttachments =>
      List<AttachmentRef>.unmodifiable(_pendingAttachments);
  List<Conversation> get conversations =>
      List<Conversation>.unmodifiable(_conversations);
  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);

  Conversation? get activeConversation {
    final id = _activeId;
    if (id == null) return null;
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  ChatMessage? get lastAssistantMessage {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == MessageRole.assistant) return _messages[i];
    }
    return null;
  }

  bool get canSend => !_streaming;

  void consumeNotice() {
    _notice = null;
  }

  void clearLastError() {
    _lastError = null;
  }

  // ---------------------------------------------------------------------------
  // 会话管理
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _notify();
    await _refreshConversations();
    _loading = false;
    _notify();
  }

  Future<void> reloadForProfile() async {
    _activeId = null;
    _messages = <ChatMessage>[];
    await _refreshConversations();
    _notify();
  }

  Future<void> _refreshConversations() async {
    final profileId = _settings.activeProfile.id;
    _conversations = await _db.listConversations(profileId: profileId);
    if (_activeId != null &&
        !_conversations.any((c) => c.id == _activeId)) {
      _activeId = null;
      _messages = <ChatMessage>[];
    }
  }

  Future<Conversation> createConversation({String? title}) async {
    final profile = _settings.activeProfile;
    final now = DateTime.now();
    final conversation = Conversation(
      id: Ids.newId('chat'),
      profileId: profile.id,
      title: (title == null || title.trim().isEmpty) ? '新对话' : title.trim(),
      createdAt: now,
      updatedAt: now,
      model: _settings.settings.effectiveModel,
    );
    await _db.saveConversation(conversation);
    _conversations = <Conversation>[conversation, ..._conversations];
    _activeId = conversation.id;
    _messages = <ChatMessage>[];
    _lastMemory = MemoryContext.empty;
    _lastSearchHits = <SearchHit>[];
    _lastCompression = null;
    _lastIngest = null;
    _pendingAttachments = <AttachmentRef>[];
    _notify();
    return conversation;
  }

  Future<void> openConversation(String id) async {
    if (_activeId == id && _messages.isNotEmpty) return;
    _activeId = id;
    _messages = await _db.listMessages(id);
    final conv = activeConversation;
    if (conv != null) {
      _contextTokens = estimateConversationTokens(
        _messages.map((m) => m.displayContent),
        extra: estimateTokens(conv.summary),
      );
    }
    _notify();
  }

  Future<void> closeActiveConversation() async {
    await stop();
    _activeId = null;
    _messages = <ChatMessage>[];
    _notify();
  }

  Future<void> deleteConversation(String id) async {
    if (_activeId == id) {
      await stop();
    }
    await _db.deleteConversation(id);
    _conversations = _conversations.where((c) => c.id != id).toList();
    if (_activeId == id) {
      _activeId = null;
      _messages = <ChatMessage>[];
    }
    _notify();
  }

  Future<void> renameConversation(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    for (var i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == id) {
        final next = _conversations[i].copyWith(
          title: trimmed,
          titleGenerated: true,
          updatedAt: DateTime.now(),
        );
        _conversations[i] = next;
        await _db.saveConversation(next);
        break;
      }
    }
    _notify();
  }

  Future<void> togglePin(String id) async {
    for (var i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == id) {
        final next = _conversations[i].copyWith(
          pinned: !_conversations[i].pinned,
          updatedAt: DateTime.now(),
        );
        _conversations[i] = next;
        await _db.saveConversation(next);
        break;
      }
    }
    _sortConversations();
    _notify();
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  // ---------------------------------------------------------------------------
  // 会话内开关
  // ---------------------------------------------------------------------------

  void setDeepThinking(bool value) {
    _deepThinking = value;
    _notify();
  }

  void setSearchEnabled(bool value) {
    _searchOn = value;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 附件
  // ---------------------------------------------------------------------------

  Future<void> pickAttachments() async {
    if (_streaming) return;
    try {
      final picked = await _attachments.pickFiles();
      if (picked.isEmpty) return;
      _pendingAttachments = <AttachmentRef>[..._pendingAttachments, ...picked];
      _notify();
    } catch (e) {
      _notice = '附件读取失败：$e';
      _notify();
    }
  }

  void removeAttachment(String id) {
    _pendingAttachments =
        _pendingAttachments.where((a) => a.id != id).toList();
    _notify();
  }

  void clearAttachments() {
    _pendingAttachments = <AttachmentRef>[];
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 发送
  // ---------------------------------------------------------------------------

  Future<void> sendMessage(String text) async {
    if (_streaming) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && _pendingAttachments.isEmpty) return;
    if (!_settings.hasApiKey) {
      _notice = '请先在「设置」里填写 DeepSeek API Key';
      _notify();
      return;
    }

    final conversation = activeConversation ?? await createConversation();
    final profile = _settings.activeProfile;
    final settings = _settings.settings;
    final now = DateTime.now();
    final attachments = List<AttachmentRef>.from(_pendingAttachments);

    final userMessage = ChatMessage(
      id: Ids.newId('msg'),
      sessionId: conversation.id,
      role: MessageRole.user,
      content: trimmed,
      createdAt: now,
      attachments: attachments,
      tokens: estimateMessageTokens(trimmed),
    );

    final assistant = ChatMessage(
      id: Ids.newId('msg'),
      sessionId: conversation.id,
      role: MessageRole.assistant,
      status: MessageStatus.streaming,
      createdAt: now.add(const Duration(milliseconds: 1)),
    );

    _messages = <ChatMessage>[..._messages, userMessage, assistant];
    _pendingAttachments = <AttachmentRef>[];
    await _db.saveMessage(userMessage);
    await _db.saveMessage(assistant);

    final isFirst = conversation.messageCount == 0 && !conversation.titleGenerated;
    var updatedConv = conversation.copyWith(
      updatedAt: now,
      messageCount: conversation.messageCount + 2,
      model: settings.effectiveModel,
      title: isFirst ? fallbackTitle(trimmed) : conversation.title,
    );
    await _persistConversation(updatedConv);
    _notify();

    await _runTurn(
      conversation: updatedConv,
      profile: profile,
      settings: settings,
      history: _messages.sublist(0, _messages.length - 1),
      userText: trimmed,
      assistant: assistant,
      attachments: attachments,
      appendUserTurn: true,
    );
  }

  Future<void> _runTurn({
    required Conversation conversation,
    required UserProfile profile,
    required AppSettings settings,
    required List<ChatMessage> history,
    required String userText,
    required ChatMessage assistant,
    required List<AttachmentRef> attachments,
    required bool appendUserTurn,
  }) async {
    _streaming = true;
    _stopRequested = false;
    _lastError = null;
    _streamContent = '';
    _streamReasoning = '';
    _streamHits = <SearchHit>[];
    _streamQueries = <String>[];
    _streamVisitedPages = <SearchHit>[];
    _streamMemoryIds = <String>[];
    _streamPromptTokens = null;
    _streamCompletionTokens = null;
    _streamingMessage = assistant;
    _streamConv = conversation;
    _streamProfile = profile;
    _streamSettings = settings;
    _streamAttachments = attachments;
    _streamUserText = userText;
    _notify();

    PreparedTurn prepared;
    try {
      var attachmentContext = '';
      if (attachments.isNotEmpty) {
        attachmentContext =
            await _attachments.buildContext(attachments);
      }
      prepared = await _pipeline.prepare(
        profile: profile,
        conversation: conversation,
        history: history,
        userText: userText,
        settings: settings,
        attachments: attachments,
        attachmentContext: attachmentContext,
        searchEnabledOverride: _searchOn,
        appendUserTurn: appendUserTurn,
      );
    } catch (e) {
      _failTurn(e is ApiException ? e.friendlyMessage : '准备请求失败：$e');
      return;
    }

    _lastMemory = prepared.memory;
    _lastSearchHits = prepared.searchHits;
    _streamHits = prepared.searchHits;
    _streamMemoryIds =
        prepared.memory.items.map((e) => e.id).toList(growable: false);
    _streamPromptTokens = prepared.promptTokens;
    _contextTokens = prepared.promptTokens;
    if (prepared.searchError != null) {
      _notice = prepared.searchError;
    }
    _updateStreamingMessage();
    _notify();

    final serverSearch = _searchOn &&
        settings.searchBackend == SearchBackend.deepseek;
    _sub = _pipeline
        .stream(
          prepared,
          model: serverSearch
              ? 'deepseek-flash'
              : (_deepThinking
                  ? settings.reasonerModel
                  : settings.chatModel),
          temperature: settings.temperature,
          maxTokens: settings.maxTokens,
          useServerSearch: serverSearch,
          deepThinking: _deepThinking,
        )
        .listen(
      _onStreamEvent,
      onError: (Object error, StackTrace stack) {
        _failTurn(error is ApiException ? error.friendlyMessage : '请求失败：$error');
      },
      onDone: () async {
        if (_stopRequested) return;
        await _finishTurn(stopped: false);
      },
      cancelOnError: false,
    );
  }

  void _onStreamEvent(ChatStreamEvent event) {
    switch (event.type) {
      case StreamEventType.content:
        _streamContent += event.text;
        _updateStreamingMessage();
        _scheduleNotify();
        break;
      case StreamEventType.reasoning:
        _streamReasoning += event.text;
        _updateStreamingMessage();
        _scheduleNotify();
        break;
      case StreamEventType.searchResults:
        _streamHits = event.searchHits;
        _updateStreamingMessage();
        _notify();
        break;
      case StreamEventType.searchQuery:
        for (final q in event.queries) {
          if (!_streamQueries.contains(q)) _streamQueries.add(q);
        }
        _updateStreamingMessage();
        _notify();
        break;
      case StreamEventType.pagesVisited:
        for (final page in event.visitedPages) {
          if (!_streamVisitedPages.any((e) => e.url == page.url)) {
            _streamVisitedPages.add(page);
          }
        }
        _updateStreamingMessage();
        _notify();
        break;
      case StreamEventType.usage:
        _streamPromptTokens = event.promptTokens ?? _streamPromptTokens;
        _streamCompletionTokens = event.completionTokens;
        break;
      case StreamEventType.title:
        _applyAiTitle(event.title);
        break;
      case StreamEventType.error:
        _failTurn(event.errorMessage ?? '生成失败');
        break;
      case StreamEventType.done:
        break;
    }
  }

  void _updateStreamingMessage() {
    final current = _streamingMessage;
    if (current == null) return;
    final updated = current.copyWith(
      content: _streamContent,
      reasoning: _streamReasoning,
      status: MessageStatus.streaming,
      searchHits: _streamHits,
      searchQueries: _streamQueries,
      visitedPages: _streamVisitedPages,
      citedMemoryIds: _streamMemoryIds,
    );
    _streamingMessage = updated;
    _replaceMessage(updated);
  }

  Future<void> stop() async {
    if (!_streaming) return;
    _stopRequested = true;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    await _finishTurn(stopped: true);
  }

  Future<void> _finishTurn({required bool stopped}) async {
    if (!_streaming) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;

    final conv = _streamConv;
    final assistant = _streamingMessage;
    final settings = _streamSettings;
    if (conv == null || assistant == null) {
      _streaming = false;
      _notify();
      return;
    }

    final content = _streamContent;
    final failed = content.trim().isEmpty && _streamReasoning.trim().isEmpty;
    final finished = assistant.copyWith(
      content: content,
      reasoning: _streamReasoning,
      status: stopped
          ? MessageStatus.stopped
          : (failed ? MessageStatus.failed : MessageStatus.done),
      finishedAt: DateTime.now(),
      tokens: _streamCompletionTokens ??
          estimateMessageTokens(content, reasoning: _streamReasoning),
      searchHits: _streamHits,
      searchQueries: _streamQueries,
      visitedPages: _streamVisitedPages,
      citedMemoryIds: _streamMemoryIds,
      error: failed && !stopped ? '没有收到有效回复，请重试' : null,
    );
    _replaceMessage(finished);
    await _db.saveMessage(finished);

    var updatedConv = conv.copyWith(
      updatedAt: DateTime.now(),
      summary: conv.summary,
    );
    if (updatedConv.titleGenerated == false && content.trim().isNotEmpty) {
      final aiTitle = await _pipeline.suggestTitle(
        firstUserMessage: _firstUserText(),
        firstAssistantMessage: content,
      );
      if (aiTitle.isNotEmpty) {
        updatedConv = updatedConv.copyWith(
          title: aiTitle,
          titleGenerated: true,
        );
      }
    }
    await _persistConversation(updatedConv);
    _streamConv = null;
    _streamingMessage = null;
    _streaming = false;
    if (_streamPromptTokens != null && _streamCompletionTokens != null) {
      _contextTokens = _streamPromptTokens! + _streamCompletionTokens!;
    }
    _notify();

    if (stopped || failed) {
      if (stopped) _notice = '已停止生成';
      return;
    }

    // 1) 压缩过长上下文
    await _maybeCompress(updatedConv);

    // 2) 记忆回写
    if (settings != null && settings.autoExtractMemory && settings.memoryEnabled) {
      _remembering = true;
      _notify();
      final profile = _streamProfile;
      final userText = _streamUserText;
      final result = await _pipeline.remember(
        userId: profile?.id ?? _settings.userId,
        sessionId: updatedConv.id,
        userMessage: userText,
        assistantMessage: content,
        enabled: true,
        assistantMessageId: finished.id,
      );
      _lastIngest = result;
      _remembering = false;
      final current = activeConversation;
      if (current != null && result.totalTouched > 0) {
        final next = current.copyWith(
          lastMemoryCount: result.totalTouched,
          updatedAt: DateTime.now(),
        );
        await _persistConversation(next);
      }
      _notify();
    }
  }

  Future<void> _maybeCompress(Conversation conversation) async {
    final settings = _settings.settings;
    // 已压缩的消息不再进入上下文，也不重复参与压缩。
    final localMessages = _messages
        .where((m) => m.role != MessageRole.system && !m.compressed)
        .toList(growable: false);
    final estimated = estimateConversationTokens(
      localMessages.map((m) => m.displayContent),
      extra: estimateTokens(conversation.summary),
    );
    if (estimated <= settings.compressThreshold) return;

    _compressing = true;
    _notify();
    try {
      final result = await _pipeline.maybeCompress(
        conversation: conversation,
        messages: localMessages,
        threshold: settings.compressThreshold,
      );
      if (result.applied) {
        final uptoId = result.uptoMessageId;
        if (uptoId != null) {
          for (var i = 0; i < _messages.length; i++) {
            final msg = _messages[i];
            if (msg.id == uptoId) {
              _messages[i] = msg.copyWith(compressed: true);
              await _db.saveMessage(_messages[i]);
              break;
            }
            if (!msg.compressed) {
              _messages[i] = msg.copyWith(compressed: true);
              await _db.saveMessage(_messages[i]);
            }
          }
        }
        final next = conversation.copyWith(
          summary: result.summary,
          summaryTokens: estimateTokens(result.summary),
          compressedUntilMessageId: uptoId,
          updatedAt: DateTime.now(),
        );
        await _persistConversation(next);
        _lastCompression = result;
        _notice = '上下文已自动压缩，节省约 ${result.tokensBefore - result.tokensAfter} tokens';
      }
    } catch (e) {
      _lastError = '上下文压缩失败：$e';
    } finally {
      _compressing = false;
      _notify();
    }
  }

  void _applyAiTitle(String? title) {
    final trimmed = title?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final conv = activeConversation;
    if (conv == null || conv.titleGenerated) return;
    final next = conv.copyWith(title: trimmed, titleGenerated: true);
    _persistConversation(next);
    _notify();
  }

  Future<void> _failTurn(String message) async {
    _lastError = message;
    _notice = message;
    final assistant = _streamingMessage;
    if (assistant != null) {
      final failed = assistant.copyWith(
        content: _streamContent,
        reasoning: _streamReasoning,
        status: MessageStatus.failed,
        finishedAt: DateTime.now(),
        error: message,
      );
      _replaceMessage(failed);
      await _db.saveMessage(failed);
    }
    _streaming = false;
    _streamingMessage = null;
    _streamConv = null;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 重新生成 / 继续 / 编辑 / 版本切换
  // ---------------------------------------------------------------------------

  Future<void> regenerateLast() async {
    if (_streaming) return;
    final conversation = activeConversation;
    if (conversation == null) return;
    var index = -1;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == MessageRole.assistant) {
        index = i;
        break;
      }
    }
    if (index < 0) return;
    final old = _messages[index];
    final versions = <MessageVersion>[
      ...old.versions,
      MessageVersion(
        id: Ids.newId('ver'),
        content: old.content,
        reasoning: old.reasoning,
        createdAt: old.createdAt,
      ),
    ];
    final assistant = old.copyWith(
      content: '',
      reasoning: '',
      status: MessageStatus.streaming,
      versions: versions,
      activeVersion: -1,
      clearError: true,
      tokens: 0,
      searchHits: const <SearchHit>[],
    );
    _messages[index] = assistant;
    await _db.saveMessage(assistant);

    final history = _messages.sublist(0, index);
    await _runTurn(
      conversation: conversation,
      profile: _settings.activeProfile,
      settings: _settings.settings,
      history: history,
      userText: '',
      assistant: assistant,
      attachments: const <AttachmentRef>[],
      appendUserTurn: false,
    );
  }

  Future<void> continueGeneration() async {
    if (_streaming) return;
    final conversation = activeConversation;
    if (conversation == null) return;
    final last = lastAssistantMessage;
    if (last == null) return;
    final index = _messages.indexWhere((m) => m.id == last.id);
    if (index < 0) return;

    final assistant = last.copyWith(
      status: MessageStatus.streaming,
      clearError: true,
    );
    _messages[index] = assistant;
    await _db.saveMessage(assistant);

    final history = _messages.sublist(0, index + 1);
    final partial = last.displayContent;
    await _runTurn(
      conversation: conversation,
      profile: _settings.activeProfile,
      settings: _settings.settings,
      history: history,
      userText: partial.isEmpty
          ? '请继续输出。'
          : '请从中断处继续输出，不要重复以上内容。',
      assistant: assistant,
      attachments: const <AttachmentRef>[],
      appendUserTurn: true,
    );
  }

  Future<void> editUserMessage(String messageId, String newText) async {
    if (_streaming) return;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    final conversation = activeConversation;
    if (conversation == null) return;

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || _messages[index].role != MessageRole.user) return;

    final updatedUser = _messages[index].copyWith(
      content: trimmed,
      tokens: estimateMessageTokens(trimmed),
    );
    // 删除这条消息之后的所有消息（含助手回复）。
    final removed = _messages.sublist(index + 1);
    for (final msg in removed) {
      await _db.deleteMessage(msg.id);
    }
    _messages = _messages.sublist(0, index + 1);
    _messages[index] = updatedUser;
    await _db.saveMessage(updatedUser);

    final assistant = ChatMessage(
      id: Ids.newId('msg'),
      sessionId: conversation.id,
      role: MessageRole.assistant,
      status: MessageStatus.streaming,
      createdAt: DateTime.now(),
    );
    _messages.add(assistant);
    await _db.saveMessage(assistant);

    final next = conversation.copyWith(
      title: conversation.titleGenerated
          ? conversation.title
          : fallbackTitle(trimmed),
      updatedAt: DateTime.now(),
      messageCount: _messages.length,
    );
    await _persistConversation(next);
    _notify();

    await _runTurn(
      conversation: next,
      profile: _settings.activeProfile,
      settings: _settings.settings,
      history: _messages.sublist(0, index),
      userText: trimmed,
      assistant: assistant,
      attachments: _messages[index].attachments,
      appendUserTurn: true,
    );
  }

  Future<void> selectVersion(String messageId, int index) async {
    final position = _messages.indexWhere((m) => m.id == messageId);
    if (position < 0) return;
    final message = _messages[position];
    if (index < 0 || index > message.versions.length) return;
    final updated = message.copyWith(activeVersion: index);
    _messages[position] = updated;
    await _db.saveMessage(updated);
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  Future<void> _persistConversation(Conversation conversation) async {
    await _db.saveConversation(conversation);
    for (var i = 0; i < _conversations.length; i++) {
      if (_conversations[i].id == conversation.id) {
        _conversations[i] = conversation;
        break;
      }
    }
    _sortConversations();
  }

  void _replaceMessage(ChatMessage message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    _messages[index] = message;
  }

  String _firstUserText() {
    for (final msg in _messages) {
      if (msg.role == MessageRole.user) {
        return msg.displayContent;
      }
    }
    return '';
  }

  void _scheduleNotify() {
    _saveTimer ??= Timer(const Duration(milliseconds: 120), () {
      _saveTimer = null;
      _notify();
    });
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
