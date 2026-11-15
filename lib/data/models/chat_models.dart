/// 对话领域模型（纯 Dart，可直接在单元测试中使用）。
library;

enum MessageRole {
  user,
  assistant,
  system;

  static MessageRole fromName(String? name) {
    switch (name) {
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.user;
    }
  }

  String get wireName => name;
}

enum MessageStatus {
  streaming,
  done,
  stopped,
  failed;

  static MessageStatus fromName(String? name) =>
      MessageStatus.values.firstWhere(
        (e) => e.name == name,
        orElse: () => MessageStatus.done,
      );
}

enum AttachmentKind {
  image,
  text,
  document;

  static AttachmentKind fromName(String? name) =>
      AttachmentKind.values.firstWhere(
        (e) => e.name == name,
        orElse: () => AttachmentKind.document,
      );
}

/// 附件引用：小文件在本地直接抽出文本，大文件/二进制由模型侧处理。
class AttachmentRef {
  const AttachmentRef({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    this.localPath,
    this.extractedText,
    this.remoteFileId,
  });

  final String id;
  final String name;
  final String mime;
  final int size;
  final AttachmentKind kind;
  final String? localPath;

  /// 文本类文件抽取出的内容（截断后），用于拼进 prompt。
  final String? extractedText;

  /// 如果走服务端文件接口，这里保存 file_id。
  final String? remoteFileId;

  AttachmentRef copyWith({
    String? remoteFileId,
    String? extractedText,
  }) {
    return AttachmentRef(
      id: id,
      name: name,
      mime: mime,
      size: size,
      kind: kind,
      localPath: localPath,
      extractedText: extractedText ?? this.extractedText,
      remoteFileId: remoteFileId ?? this.remoteFileId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'mime': mime,
        'size': size,
        'kind': kind.name,
        'localPath': localPath,
        'extractedText': extractedText,
        'remoteFileId': remoteFileId,
      };

  static AttachmentRef fromJson(Map<String, dynamic> json) => AttachmentRef(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'file',
        mime: json['mime'] as String? ?? 'application/octet-stream',
        size: (json['size'] as num?)?.toInt() ?? 0,
        kind: AttachmentKind.fromName(json['kind'] as String?),
        localPath: json['localPath'] as String?,
        extractedText: json['extractedText'] as String?,
        remoteFileId: json['remoteFileId'] as String?,
      );
}

/// 一条联网搜索结果。
class SearchHit {
  const SearchHit({
    required this.title,
    required this.url,
    required this.snippet,
    this.engine = 'tavily',
    this.publishedAt,
  });

  final String title;
  final String url;
  final String snippet;
  final String engine;
  final String? publishedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'url': url,
        'snippet': snippet,
        'engine': engine,
        'publishedAt': publishedAt,
      };

  static SearchHit fromJson(Map<String, dynamic> json) => SearchHit(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        engine: json['engine'] as String? ?? 'tavily',
        publishedAt: json['publishedAt'] as String?,
      );
}

/// 消息的历史版本（重新生成 / 编辑前的版本）。
class MessageVersion {
  const MessageVersion({
    required this.id,
    required this.content,
    required this.reasoning,
    required this.createdAt,
  });

  final String id;
  final String content;
  final String reasoning;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'content': content,
        'reasoning': reasoning,
        'createdAt': createdAt.toIso8601String(),
      };

  static MessageVersion fromJson(Map<String, dynamic> json) => MessageVersion(
        id: json['id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        reasoning: json['reasoning'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// 一条聊天消息。
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    this.content = '',
    this.reasoning = '',
    this.status = MessageStatus.done,
    required this.createdAt,
    this.finishedAt,
    this.tokens = 0,
    this.attachments = const <AttachmentRef>[],
    this.versions = const <MessageVersion>[],
    this.activeVersion = -1,
    this.searchHits = const <SearchHit>[],
    this.citedMemoryIds = const <String>[],
    this.compressed = false,
    this.error,
  });

  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final String reasoning;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final int tokens;
  final List<AttachmentRef> attachments;

  /// 旧版本（当前内容不在此列表中）。
  final List<MessageVersion> versions;

  /// -1 表示展示当前内容；>=0 表示展示 [versions] 中对应版本。
  final int activeVersion;

  final List<SearchHit> searchHits;

  /// 本轮注入过、并被模型实际参考的记忆 ID（用于「引用记忆」展示）。
  final List<String> citedMemoryIds;
  final bool compressed;
  final String? error;

  int get versionCount => versions.length + 1;
  bool get hasVersions => versions.isNotEmpty;
  bool get isStreaming => status == MessageStatus.streaming;
  bool get isFailed => status == MessageStatus.failed;

  String get displayContent =>
      activeVersion >= 0 && activeVersion < versions.length
          ? versions[activeVersion].content
          : content;

  String get displayReasoning =>
      activeVersion >= 0 && activeVersion < versions.length
          ? versions[activeVersion].reasoning
          : reasoning;

  bool get isEmpty => displayContent.trim().isEmpty && displayReasoning.trim().isEmpty;

  ChatMessage copyWith({
    String? content,
    String? reasoning,
    MessageStatus? status,
    DateTime? finishedAt,
    int? tokens,
    List<AttachmentRef>? attachments,
    List<MessageVersion>? versions,
    int? activeVersion,
    List<SearchHit>? searchHits,
    List<String>? citedMemoryIds,
    bool? compressed,
    String? error,
    bool clearError = false,
  }) {
    return ChatMessage(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      status: status ?? this.status,
      createdAt: createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      tokens: tokens ?? this.tokens,
      attachments: attachments ?? this.attachments,
      versions: versions ?? this.versions,
      activeVersion: activeVersion ?? this.activeVersion,
      searchHits: searchHits ?? this.searchHits,
      citedMemoryIds: citedMemoryIds ?? this.citedMemoryIds,
      compressed: compressed ?? this.compressed,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sessionId': sessionId,
        'role': role.name,
        'content': content,
        'reasoning': reasoning,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'tokens': tokens,
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'versions': versions.map((e) => e.toJson()).toList(),
        'activeVersion': activeVersion,
        'searchHits': searchHits.map((e) => e.toJson()).toList(),
        'citedMemoryIds': citedMemoryIds,
        'compressed': compressed,
        'error': error,
      };

  static ChatMessage fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        role: MessageRole.fromName(json['role'] as String?),
        content: json['content'] as String? ?? '',
        reasoning: json['reasoning'] as String? ?? '',
        status: MessageStatus.fromName(json['status'] as String?),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
        tokens: (json['tokens'] as num?)?.toInt() ?? 0,
        attachments: (json['attachments'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AttachmentRef.fromJson)
            .toList(),
        versions: (json['versions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MessageVersion.fromJson)
            .toList(),
        activeVersion: (json['activeVersion'] as num?)?.toInt() ?? -1,
        searchHits: (json['searchHits'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SearchHit.fromJson)
            .toList(),
        citedMemoryIds:
            (json['citedMemoryIds'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
        compressed: json['compressed'] as bool? ?? false,
        error: json['error'] as String?,
      );
}

/// 一个会话（对话）。
class Conversation {
  const Conversation({
    required this.id,
    required this.profileId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.model = 'deepseek-chat',
    this.pinned = false,
    this.archived = false,
    this.summary = '',
    this.summaryTokens = 0,
    this.compressedUntilMessageId,
    this.lastMemoryCount = 0,
    this.titleGenerated = false,
    this.messageCount = 0,
  });

  final String id;
  final String profileId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String model;
  final bool pinned;
  final bool archived;

  /// 滚动压缩出来的历史摘要（会拼进 System Prompt）。
  final String summary;
  final int summaryTokens;

  /// 摘要覆盖到的最后一条消息 ID（用于展示「已压缩」标记）。
  final String? compressedUntilMessageId;

  /// 最近一次对话更新了多少条记忆，侧栏用于展示。
  final int lastMemoryCount;
  final bool titleGenerated;
  final int messageCount;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    String? model,
    bool? pinned,
    bool? archived,
    String? summary,
    int? summaryTokens,
    String? compressedUntilMessageId,
    int? lastMemoryCount,
    bool? titleGenerated,
    int? messageCount,
    String? profileId,
  }) {
    return Conversation(
      id: id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      model: model ?? this.model,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      summary: summary ?? this.summary,
      summaryTokens: summaryTokens ?? this.summaryTokens,
      compressedUntilMessageId: compressedUntilMessageId ??
          this.compressedUntilMessageId,
      lastMemoryCount: lastMemoryCount ?? this.lastMemoryCount,
      titleGenerated: titleGenerated ?? this.titleGenerated,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'profileId': profileId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'model': model,
        'pinned': pinned,
        'archived': archived,
        'summary': summary,
        'summaryTokens': summaryTokens,
        'compressedUntilMessageId': compressedUntilMessageId,
        'lastMemoryCount': lastMemoryCount,
        'titleGenerated': titleGenerated,
        'messageCount': messageCount,
      };

  static Conversation fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String? ?? '',
        profileId: json['profileId'] as String? ?? 'default',
        title: json['title'] as String? ?? '新对话',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
                DateTime.now(),
        model: json['model'] as String? ?? 'deepseek-chat',
        pinned: json['pinned'] as bool? ?? false,
        archived: json['archived'] as bool? ?? false,
        summary: json['summary'] as String? ?? '',
        summaryTokens: (json['summaryTokens'] as num?)?.toInt() ?? 0,
        compressedUntilMessageId: json['compressedUntilMessageId'] as String?,
        lastMemoryCount: (json['lastMemoryCount'] as num?)?.toInt() ?? 0,
        titleGenerated: json['titleGenerated'] as bool? ?? false,
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      );
}
