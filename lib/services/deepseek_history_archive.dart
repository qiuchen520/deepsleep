/// DeepSeek 官方历史导出 ZIP（export_format_version = 3）的读写实现。
///
/// 兼容结构（与官方 Web Demo 导出保持一致）：
/// ```
/// manifest.json                       {"export_format_version": 3}
/// chat_session_index.json             [{id,title,pinned,message_count,inserted_at,updated_at}]
/// chat_sessions/<sessionId>.json      {id,title,pinned,current_message_id,inserted_at,updated_at,messages:[...]}
/// chat_sessions/<sessionId>_files/<fileName>_<fileId>
/// ```
/// 消息消息体含 fragments：REQUEST / RESPONSE / TEMPLATE_RESPONSE / THINK /
/// TOOL_SEARCH / READ_LINK / FILE；导出时还原为官方格式，导入时映射回本地模型。
///
/// 本文件只依赖 archive / dart:convert / AppDatabase，不依赖 Flutter UI。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/utils/ids.dart';
import '../data/db/app_database.dart';
import '../data/models/chat_models.dart';

/// 备份 / 历史文件格式不合法时抛出。
class ArchiveFormatException implements Exception {
  const ArchiveFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 历史 ZIP 预览结果。
class ArchivePreview {
  const ArchivePreview({
    required this.ok,
    this.format = 'deepseek-zip',
    this.version = DeepSeekHistoryArchive.formatVersion,
    this.conversations = 0,
    this.messages = 0,
    this.attachments = 0,
    this.conflicts = 0,
    this.error,
  });

  final bool ok;
  final String format;
  final int version;
  final int conversations;
  final int messages;
  final int attachments;

  /// 归档内部的重复项（重复的会话 id / 标题 / 消息 id）数量。
  final int conflicts;
  final String? error;
}

/// 历史 ZIP 导入结果。
class ArchiveImportResult {
  const ArchiveImportResult({
    this.conversations = 0,
    this.messages = 0,
    this.attachments = 0,
    this.skipped = 0,
  });

  final int conversations;
  final int messages;
  final int attachments;

  /// 因 id / 标题已存在而跳过的会话数。
  final int skipped;
}

/// DeepSeek 历史导出的静态读写 API。
class DeepSeekHistoryArchive {
  DeepSeekHistoryArchive._();

  /// 官方导出格式版本。
  static const int formatVersion = 3;

  static const String manifestFileName = 'manifest.json';
  static const String indexFilePath = 'chat_session_index.json';
  static const String _sessionsDir = 'chat_sessions';

  // ---------------------------------------------------------------------------
  // 导出
  // ---------------------------------------------------------------------------

  /// 把本地会话导出为 DeepSeek 官方兼容的 ZIP。
  ///
  /// 只会打包本地真实存在的附件文件；找不到文件的附件会跳过（保证 ZIP 自洽）。
  static Uint8List export({
    required List<Conversation> conversations,
    required Map<String, List<ChatMessage>> messagesBySession,
  }) {
    final archive = Archive();

    void addJson(String name, Object? value) {
      final bytes = utf8.encode(jsonEncode(value));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson(manifestFileName, <String, dynamic>{
      'export_format_version': formatVersion,
    });

    final indexEntries = <Map<String, dynamic>>[];

    for (final conversation in conversations) {
      final messages = (messagesBySession[conversation.id] ??
              const <ChatMessage>[])
          .where((message) => message.role != MessageRole.system)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final messageJson = <Map<String, dynamic>>[];
      String? parentId;
      String? currentMessageId;
      for (final message in messages) {
        messageJson.add(
          _messageToJson(
            message: message,
            sessionId: conversation.id,
            parentId: parentId,
            archive: archive,
          ),
        );
        parentId = message.id;
        currentMessageId = message.id;
      }

      addJson(
        '$_sessionsDir/${conversation.id}.json',
        <String, dynamic>{
          'id': conversation.id,
          'title': conversation.title,
          'pinned': conversation.pinned,
          'current_message_id': currentMessageId,
          'inserted_at': conversation.createdAt.toIso8601String(),
          'updated_at': conversation.updatedAt.toIso8601String(),
          'messages': messageJson,
        },
      );

      indexEntries.add(<String, dynamic>{
        'id': conversation.id,
        'title': conversation.title,
        'pinned': conversation.pinned,
        'message_count': messageJson.length,
        'inserted_at': conversation.createdAt.toIso8601String(),
        'updated_at': conversation.updatedAt.toIso8601String(),
      });
    }

    addJson(indexFilePath, indexEntries);

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const ArchiveFormatException('ZIP 生成失败');
    }
    return Uint8List.fromList(encoded);
  }

  static Map<String, dynamic> _messageToJson({
    required ChatMessage message,
    required String sessionId,
    required String? parentId,
    required Archive archive,
  }) {
    final fragments = <Map<String, dynamic>>[];
    final isUser = message.role == MessageRole.user;

    if (isUser) {
      final request = message.displayContent.trim();
      if (request.isNotEmpty) {
        fragments.add(<String, dynamic>{'type': 'REQUEST', 'content': request});
      }
    } else {
      var hasStepThinking = false;
      var hasStepSearch = false;
      var hasStepBrowse = false;

      for (final step in message.thinkingSteps) {
        if (step.kind == ThinkingStepKind.reasoning) {
          if (step.text.trim().isEmpty) continue;
          hasStepThinking = true;
          fragments.add(<String, dynamic>{
            'type': 'THINK',
            'content': step.text,
            'elapsed_secs': _elapsedSeconds(message),
          });
        } else if (step.kind == ThinkingStepKind.search) {
          hasStepSearch = true;
          fragments.add(<String, dynamic>{
            'type': 'TOOL_SEARCH',
            'queries': step.queries,
            'status': 'FINISHED',
            'results': step.hits.map(_hitToJson).toList(),
          });
        } else if (step.kind == ThinkingStepKind.browse) {
          hasStepBrowse = true;
          fragments.add(<String, dynamic>{
            'type': 'READ_LINK',
            'results': step.hits
                .map(
                  (hit) => <String, dynamic>{
                    'url': hit.url,
                    'title': hit.title,
                    'signature': '',
                  },
                )
                .toList(),
          });
        }
      }

      final reasoning = message.displayReasoning.trim();
      if (!hasStepThinking && reasoning.isNotEmpty) {
        fragments.insert(0, <String, dynamic>{
          'type': 'THINK',
          'content': reasoning,
          'elapsed_secs': _elapsedSeconds(message),
        });
      }
      if (!hasStepSearch && message.searchHits.isNotEmpty) {
        fragments.add(<String, dynamic>{
          'type': 'TOOL_SEARCH',
          'queries': message.searchQueries,
          'status': 'FINISHED',
          'results': message.searchHits.map(_hitToJson).toList(),
        });
      }
      if (!hasStepBrowse && message.visitedPages.isNotEmpty) {
        fragments.add(<String, dynamic>{
          'type': 'READ_LINK',
          'results': message.visitedPages
              .map(
                (hit) => <String, dynamic>{
                  'url': hit.url,
                  'title': hit.title,
                  'signature': '',
                },
              )
              .toList(),
        });
      }

      final response = message.displayContent.trim();
      if (response.isNotEmpty) {
        fragments.add(<String, dynamic>{
          'type': 'RESPONSE',
          'content': response,
        });
      }
    }

    final fileFragment = _fileFragment(
      message: message,
      sessionId: sessionId,
      archive: archive,
    );
    if (fileFragment != null) fragments.add(fileFragment);

    return <String, dynamic>{
      'id': message.id,
      'parent_id': parentId,
      'role': isUser ? 'USER' : 'ASSISTANT',
      'status': _statusName(message),
      'thinking_enabled': message.reasoning.trim().isNotEmpty ||
          message.thinkingSteps.isNotEmpty,
      'search_enabled': message.searchHits.isNotEmpty ||
          message.searchQueries.isNotEmpty ||
          message.visitedPages.isNotEmpty ||
          message.thinkingSteps.any(
            (step) =>
                step.kind == ThinkingStepKind.search ||
                step.kind == ThinkingStepKind.browse,
          ),
      'accumulated_token_usage': message.tokens,
      'inserted_at': message.createdAt.toIso8601String(),
      'fragments': fragments,
    };
  }

  static Map<String, dynamic>? _fileFragment({
    required ChatMessage message,
    required String sessionId,
    required Archive archive,
  }) {
    final files = <Map<String, dynamic>>[];
    for (final attachment in message.attachments) {
      final localPath = attachment.localPath;
      if (localPath == null || localPath.isEmpty) continue;
      try {
        final file = File(localPath);
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        final entryName = '$_sessionsDir/${sessionId}_files/'
            '${_safeFileName(attachment.name)}_${attachment.id}';
        archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
        files.add(<String, dynamic>{
          'id': attachment.id,
          'file_name': attachment.name,
          'file_size': attachment.size > 0 ? attachment.size : bytes.length,
          'token_usage': 0,
          'inserted_at': message.createdAt.toIso8601String(),
          'export_path': entryName,
          'is_image': attachment.kind == AttachmentKind.image,
          'width': null,
          'height': null,
        });
      } catch (_) {
        // 本地文件读不到就跳过该附件，避免生成指向空文件的 ZIP。
      }
    }
    if (files.isEmpty) return null;
    return <String, dynamic>{'type': 'FILE', 'files': files};
  }

  static String _statusName(ChatMessage message) {
    switch (message.status) {
      case MessageStatus.streaming:
        return 'WIP';
      case MessageStatus.stopped:
        return 'INCOMPLETE';
      case MessageStatus.failed:
        final error = message.error ?? '';
        if (error.contains('过滤') || error.contains('安全')) {
          return 'CONTENT_FILTER';
        }
        return 'FAILED';
      case MessageStatus.done:
        return 'FINISHED';
    }
  }

  static int _elapsedSeconds(ChatMessage message) {
    final finishedAt = message.finishedAt;
    if (finishedAt == null) return 0;
    final seconds = finishedAt.difference(message.createdAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  static Map<String, dynamic> _hitToJson(SearchHit hit) {
    final uri = Uri.tryParse(hit.url);
    return <String, dynamic>{
      'url': hit.url,
      'title': hit.title,
      'snippet': hit.snippet,
      'published_at': hit.publishedAt,
      'site_name': uri?.host ?? '',
      'site_icon': null,
    };
  }

  static String _safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_')
        .trim();
    if (cleaned.isEmpty) return 'file';
    if (cleaned.length > 80) return cleaned.substring(0, 80);
    return cleaned;
  }

  // ---------------------------------------------------------------------------
  // 预览
  // ---------------------------------------------------------------------------

  /// 校验并统计 ZIP 内容；失败时返回 `ok = false` 与错误信息，不抛异常。
  static ArchivePreview preview(Uint8List zipBytes) {
    try {
      final parsed = _parse(zipBytes);
      return ArchivePreview(
        ok: true,
        version: parsed.version,
        conversations: parsed.sessions.length,
        messages: parsed.messageCount,
        attachments: parsed.attachments,
        conflicts: parsed.conflicts,
      );
    } on ArchiveFormatException catch (error) {
      return ArchivePreview(ok: false, error: error.message);
    } catch (error) {
      return ArchivePreview(ok: false, error: '解析历史文件失败：$error');
    }
  }

  // ---------------------------------------------------------------------------
  // 导入
  // ---------------------------------------------------------------------------

  /// 把 DeepSeek 历史 ZIP 导入本地数据库。
  ///
  /// [replace] 为 true 时先清空所有会话；为 false 时按会话 id / 标题合并去重。
  static Future<ArchiveImportResult> importInto({
    required AppDatabase database,
    required Uint8List zipBytes,
    required bool replace,
  }) async {
    final parsed = _parse(zipBytes);

    final existingIds = <String>{};
    final existingTitles = <String>{};

    if (replace) {
      await database.deleteAllConversations();
    } else {
      final rows = await database.dumpTable('conversations');
      for (final row in rows) {
        final payload = row['payload'];
        if (payload is! Map) continue;
        try {
          final conversation =
              Conversation.fromJson(Map<String, dynamic>.from(payload));
          existingIds.add(conversation.id);
          final title = conversation.title.trim();
          if (title.isNotEmpty) existingTitles.add(title);
        } catch (_) {
          // 损坏的历史数据跳过，不影响导入。
        }
      }
    }

    var importedConversations = 0;
    var importedMessages = 0;
    var importedAttachments = 0;
    var skipped = 0;

    for (final session in parsed.sessions) {
      final converted = _toConversation(session, DateTime.now());
      if (converted == null) continue;

      final titleKey = converted.conversation.title.trim();
      if (existingIds.contains(converted.conversation.id) ||
          (titleKey.isNotEmpty && existingTitles.contains(titleKey))) {
        skipped++;
        continue;
      }

      await database.saveConversation(converted.conversation);
      for (final message in converted.messages) {
        await database.saveMessage(message);
      }

      existingIds.add(converted.conversation.id);
      if (titleKey.isNotEmpty) existingTitles.add(titleKey);
      importedConversations++;
      importedMessages += converted.messages.length;
      importedAttachments += converted.attachmentCount;
    }

    return ArchiveImportResult(
      conversations: importedConversations,
      messages: importedMessages,
      attachments: importedAttachments,
      skipped: skipped,
    );
  }

  static _ConvertedConversation? _toConversation(
    _ParsedSession session,
    DateTime fallbackNow,
  ) {
    final id = _asString(session.data['id']).trim().isNotEmpty
        ? _asString(session.data['id']).trim()
        : _asString(session.index['id']).trim();
    if (id.isEmpty) return null;

    final title = _asString(session.data['title']).trim().isNotEmpty
        ? _asString(session.data['title']).trim()
        : _asString(session.index['title']).trim();
    final createdAt = _parseIso(session.data['inserted_at']) ??
        _parseIso(session.index['inserted_at']) ??
        fallbackNow;
    final updatedAt = _parseIso(session.data['updated_at']) ??
        _parseIso(session.index['updated_at']) ??
        createdAt;
    final pinned = session.data['pinned'] == true ||
        session.index['pinned'] == true;

    final messages = <ChatMessage>[];
    for (var i = 0; i < session.messages.length; i++) {
      final message = _toMessage(
        raw: session.messages[i],
        sessionId: id,
        fallbackTime: createdAt,
        index: i,
      );
      if (message != null) messages.add(message);
    }

    return _ConvertedConversation(
      conversation: Conversation(
        id: id,
        profileId: 'default',
        title: title.isEmpty ? '导入的对话' : title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        pinned: pinned,
        model: 'deepseek-chat',
        messageCount: messages.length,
        titleGenerated: true,
      ),
      messages: messages,
      attachmentCount: session.attachmentCount,
    );
  }

  static ChatMessage? _toMessage({
    required Map<String, dynamic> raw,
    required String sessionId,
    required DateTime fallbackTime,
    required int index,
  }) {
    final roleName = _asString(raw['role']).toUpperCase();
    final MessageRole role;
    if (roleName == 'USER') {
      role = MessageRole.user;
    } else if (roleName == 'ASSISTANT') {
      role = MessageRole.assistant;
    } else {
      // 官方格式只有 USER / ASSISTANT；未知角色不导入，避免污染对话。
      return null;
    }

    final id = _asString(raw['id']).trim();
    final fragments = <Map<String, dynamic>>[];
    final rawFragments = raw['fragments'];
    if (rawFragments is List) {
      for (final item in rawFragments) {
        final fragment = _asMap(item);
        if (fragment != null) fragments.add(fragment);
      }
    }

    final requestParts = <String>[];
    final responseParts = <String>[];
    final thinkingParts = <String>[];
    final searchHits = <SearchHit>[];
    final searchQueries = <String>[];
    final visitedPages = <SearchHit>[];
    final thinkingSteps = <ThinkingStep>[];
    final attachments = <AttachmentRef>[];

    for (final fragment in fragments) {
      final type = _asString(fragment['type']).toUpperCase();
      switch (type) {
        case 'REQUEST':
          final requestContent = _asString(fragment['content']).trim();
          if (requestContent.isNotEmpty) requestParts.add(requestContent);
          break;
        case 'RESPONSE':
        case 'TEMPLATE_RESPONSE':
          final responseContent = _asString(fragment['content']).trim();
          if (responseContent.isNotEmpty) responseParts.add(responseContent);
          break;
        case 'THINK':
          final thinkContent = _asString(fragment['content']).trim();
          if (thinkContent.isNotEmpty) {
            thinkingParts.add(thinkContent);
            thinkingSteps.add(
              ThinkingStep(kind: ThinkingStepKind.reasoning, text: thinkContent),
            );
          }
          break;
        case 'TOOL_SEARCH':
          final toolQueries = _stringList(fragment['queries']);
          final toolHits = _parseHits(fragment['results']);
          thinkingSteps.add(
            ThinkingStep(
              kind: ThinkingStepKind.search,
              queries: toolQueries,
              hits: toolHits,
            ),
          );
          searchQueries.addAll(toolQueries);
          searchHits.addAll(toolHits);
          break;
        case 'READ_LINK':
          final browseHits = _parseHits(fragment['results']);
          thinkingSteps.add(
            ThinkingStep(kind: ThinkingStepKind.browse, hits: browseHits),
          );
          visitedPages.addAll(browseHits);
          break;
        case 'FILE':
          attachments.addAll(_parseAttachments(fragment));
          break;
        default:
          break;
      }
    }

    final normalizedStatus = _messageStatus(raw);
    String? error;
    if (normalizedStatus == MessageStatus.failed) {
      error = _asString(raw['status']).toUpperCase() == 'CONTENT_FILTER'
          ? '内容被安全策略过滤'
          : '生成失败';
    }

    final createdAt =
        _parseIso(raw['inserted_at']) ?? fallbackTime.add(Duration(milliseconds: index));

    final content = role == MessageRole.user
        ? requestParts.join('\n\n')
        : responseParts.join('\n\n');
    final reasoning = role == MessageRole.assistant
        ? thinkingParts.join('\n\n')
        : '';

    return ChatMessage(
      id: id.isEmpty ? Ids.newId('msg') : id,
      sessionId: sessionId,
      role: role,
      content: content,
      reasoning: reasoning,
      status: normalizedStatus,
      createdAt: createdAt,
      finishedAt: normalizedStatus == MessageStatus.done ? createdAt : null,
      tokens: _asInt(raw['accumulated_token_usage']),
      attachments: attachments,
      searchHits: searchHits,
      searchQueries: searchQueries,
      visitedPages: visitedPages,
      thinkingSteps: thinkingSteps,
      error: error,
    );
  }

  static MessageStatus _messageStatus(Map<String, dynamic> message) {
    switch (_asString(message['status']).toUpperCase()) {
      case 'FINISHED':
        return MessageStatus.done;
      case 'INCOMPLETE':
        return MessageStatus.stopped;
      case 'WIP':
        return MessageStatus.stopped;
      case 'CONTENT_FILTER':
      case 'FAILED':
        return MessageStatus.failed;
      default:
        return MessageStatus.done;
    }
  }

  static List<AttachmentRef> _parseAttachments(
    Map<String, dynamic> fragment,
  ) {
    final rawFiles = fragment['files'];
    if (rawFiles is! List) return const <AttachmentRef>[];
    final attachments = <AttachmentRef>[];
    for (final item in rawFiles) {
      final file = _asMap(item);
      if (file == null) continue;
      final fileName = _asString(file['file_name']).trim();
      final fileId = _asString(file['id']).trim();
      final isImage = file['is_image'] == true;
      final name = fileName.isEmpty ? '附件' : fileName;
      attachments.add(
        AttachmentRef(
          id: fileId.isEmpty ? Ids.newId('att') : fileId,
          name: name,
          mime: _guessMime(name, isImage),
          size: _asInt(file['file_size']),
          kind: isImage ? AttachmentKind.image : AttachmentKind.document,
        ),
      );
    }
    return attachments;
  }

  static List<SearchHit> _parseHits(Object? raw) {
    if (raw is! List) return const <SearchHit>[];
    final hits = <SearchHit>[];
    for (final item in raw) {
      final map = _asMap(item);
      if (map == null) continue;
      final url = _asString(map['url']).trim();
      final title = _asString(map['title']).trim();
      if (url.isEmpty && title.isEmpty) continue;
      hits.add(
        SearchHit(
          title: title,
          url: url,
          snippet: _asString(map['snippet']).trim(),
          engine: 'deepseek',
          publishedAt: _nonEmpty(map['published_at']),
        ),
      );
    }
    return hits;
  }

  static String _guessMime(String fileName, bool isImage) {
    final lower = fileName.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final extension = dot >= 0 ? lower.substring(dot + 1) : '';
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return isImage ? 'image/*' : 'application/octet-stream';
    }
  }

  // ---------------------------------------------------------------------------
  // ZIP 解析
  // ---------------------------------------------------------------------------

  static _ParsedArchive _parse(Uint8List zipBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const ArchiveFormatException('不是有效的 ZIP 文件');
    }

    final manifest = _readJsonObject(archive, manifestFileName);
    final rawVersion = manifest['export_format_version'];
    final version = rawVersion is num ? rawVersion.toInt() : 0;
    if (version != formatVersion) {
      throw ArchiveFormatException(
        '不支持的导出格式版本：$rawVersion（仅支持 $formatVersion）',
      );
    }

    final rawIndex = _readJson(archive, indexFilePath);
    if (rawIndex is! List) {
      throw const ArchiveFormatException('chat_session_index.json 格式不正确');
    }

    final sessions = <_ParsedSession>[];
    final seenSessionIds = <String>{};
    final seenTitles = <String>{};
    final seenMessageIds = <String>{};
    var conflicts = 0;
    var attachments = 0;
    var messageCount = 0;

    for (final item in rawIndex) {
      final index = _asMap(item);
      if (index == null) {
        conflicts++;
        continue;
      }
      final id = _asString(index['id']).trim();
      if (id.isEmpty) {
        conflicts++;
        continue;
      }
      final title = _asString(index['title']).trim();
      if (!seenSessionIds.add(id)) conflicts++;
      if (title.isNotEmpty && !seenTitles.add(title)) conflicts++;

      final sessionData =
          _readJsonObject(archive, '$_sessionsDir/$id.json');
      final rawMessages = sessionData['messages'];
      final messages = <Map<String, dynamic>>[];
      var sessionAttachments = 0;
      if (rawMessages is List) {
        for (final rawMessage in rawMessages) {
          final message = _asMap(rawMessage);
          if (message == null) continue;
          final messageId = _asString(message['id']).trim();
          if (messageId.isNotEmpty && !seenMessageIds.add(messageId)) {
            conflicts++;
          }
          sessionAttachments += _countFiles(message);
          messages.add(message);
        }
      }
      attachments += sessionAttachments;
      messageCount += messages.length;
      sessions.add(
        _ParsedSession(
          index: index,
          data: sessionData,
          messages: messages,
          attachmentCount: sessionAttachments,
        ),
      );
    }

    return _ParsedArchive(
      version: version,
      sessions: sessions,
      conflicts: conflicts,
      attachments: attachments,
      messageCount: messageCount,
    );
  }

  static int _countFiles(Map<String, dynamic> message) {
    final fragments = message['fragments'];
    if (fragments is! List) return 0;
    var count = 0;
    for (final item in fragments) {
      final fragment = _asMap(item);
      if (fragment == null || _asString(fragment['type']).toUpperCase() != 'FILE') {
        continue;
      }
      final files = fragment['files'];
      if (files is List) count += files.length;
    }
    return count;
  }

  static Object? _readJson(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) {
      throw ArchiveFormatException('缺少文件：$name');
    }
    final dynamic content;
    try {
      content = file.content;
    } catch (_) {
      throw ArchiveFormatException('无法解压文件：$name');
    }
    final List<int> bytes = content is List<int> ? content : const <int>[];
    if (bytes.isEmpty) {
      throw ArchiveFormatException('文件内容为空：$name');
    }
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      throw ArchiveFormatException('$name 不是合法的 JSON');
    }
  }

  static Map<String, dynamic> _readJsonObject(Archive archive, String name) {
    final decoded = _readJson(archive, name);
    final map = _asMap(decoded);
    if (map == null) {
      throw ArchiveFormatException('$name 格式不正确');
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String _asString(Object? value) => value is String ? value : '';

  static String? _nonEmpty(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList();
  }

  static DateTime? _parseIso(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }
}

/// 解析后的归档。
class _ParsedArchive {
  _ParsedArchive({
    required this.version,
    required this.sessions,
    required this.conflicts,
    required this.attachments,
    required this.messageCount,
  });

  final int version;
  final List<_ParsedSession> sessions;
  final int conflicts;
  final int attachments;
  final int messageCount;
}

/// 单个会话（index 条目 + session JSON + 消息列表）。
class _ParsedSession {
  _ParsedSession({
    required this.index,
    required this.data,
    required this.messages,
    required this.attachmentCount,
  });

  final Map<String, dynamic> index;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> messages;
  final int attachmentCount;
}

/// 导入前的本地模型转换结果。
class _ConvertedConversation {
  _ConvertedConversation({
    required this.conversation,
    required this.messages,
    required this.attachmentCount,
  });

  final Conversation conversation;
  final List<ChatMessage> messages;
  final int attachmentCount;
}
