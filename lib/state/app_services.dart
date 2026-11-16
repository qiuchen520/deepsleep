/// 应用服务装配（组合根）+ 依赖注入用的 AppScope。
///
/// 所有单例在这里创建，UI 层通过 `AppScope.of(context)` 或构造参数拿到。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/memory/contracts.dart';
import '../core/memory/local_memory_engine.dart';
import '../core/memory/mem0_engine.dart';
import '../core/memory/memory_engine_router.dart';
import '../data/db/app_database.dart';
import '../data/db/backup_repository_impl.dart';
import '../data/db/sqlite_memory_store.dart';
import '../data/models/profile_models.dart';
import '../services/attachment_service_impl.dart';
import '../services/backup_service_impl.dart';
import '../services/contracts.dart';
import '../services/chat_api_router.dart';
import '../services/deepseek_anthropic_client.dart';
import '../services/deepseek_client.dart';
import '../services/export_service_impl.dart';
import '../services/global_search_service.dart';
import '../services/history_transfer_service.dart';
import '../services/search_router.dart';
import '../services/voice_controller.dart';
import '../state/conversation_controller.dart';
import '../state/memory_controller.dart';
import '../state/settings_controller.dart';

class AppServices {
  AppServices({
    required this.database,
    required this.settings,
    required this.api,
    required this.memoryStore,
    required this.memoryEngine,
    required this.search,
    required this.attachments,
    required this.exports,
    required this.backups,
    required this.conversations,
    required this.memories,
    required this.voice,
    required this.globalSearch,
    required this.historyTransfer,
  });

  final AppDatabase database;
  final SettingsController settings;
  final ChatApi api;
  final MemoryStore memoryStore;
  final MemoryEngine memoryEngine;
  final WebSearchService search;
  final AttachmentService attachments;
  final ExportService exports;
  final BackupService backups;
  final ConversationController conversations;
  final MemoryController memories;
  final VoiceController voice;
  final GlobalSearchService globalSearch;
  final HistoryTransferService historyTransfer;

  static AppServices? _instance;

  static AppServices? get instance => _instance;

  static Future<AppServices> init() async {
    if (_instance != null) return _instance!;

    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final database = await AppDatabase.instance();

    final settings = SettingsController(
      prefs: prefs,
      secure: secure,
      database: database,
    );
    await settings.load();

    final deepSeekClient = DeepSeekClient(
      apiKeyProvider: () => settings.apiKey,
      baseUrlProvider: () => settings.settings.baseUrl,
    );
    final serverSearchClient = DeepSeekAnthropicClient(
      apiKeyProvider: () => settings.apiKey,
      baseUrlProvider: () => settings.settings.baseUrl,
    );
    final chatApi = ChatApiRouter(
      standard: deepSeekClient,
      serverSearch: serverSearchClient,
    );

    final store = SqliteMemoryStore(database);
    final localEngine = LocalMemoryEngine(
      store: store,
      llm: deepSeekClient,
    );
    final mem0Engine = Mem0MemoryEngine(
      apiKeyProvider: () => settings.mem0ApiKey,
      baseUrlProvider: () => settings.settings.mem0ApiUrl,
      llm: deepSeekClient,
    );
    final engine = MemoryEngineRouter(
      local: localEngine,
      mem0: mem0Engine,
      useMem0: () =>
          settings.settings.memoryBackend == MemoryBackend.mem0,
    );

    final search = SearchRouter(
      backendProvider: () => settings.settings.searchBackend.name,
      tavilyKeyProvider: () => settings.searchApiKey,
      serperKeyProvider: () => settings.searchApiKey,
      maxResultsProvider: () => settings.settings.searchMaxResults,
    );

    final attachments = AttachmentServiceImpl();
    final exports = ExportServiceImpl();
    final backupRepository = AppBackupRepository(database);
    final backups = BackupServiceImpl(repository: backupRepository);

    final conversations = ConversationController(
      database: database,
      api: chatApi,
      memoryEngine: engine,
      search: search,
      attachments: attachments,
      settings: settings,
    );
    await conversations.load();

    final memories = MemoryController(
      engine: engine,
      settings: settings,
    );

    final voice = VoiceController(
      apiKeyProvider: () => settings.apiKey,
      baseUrlProvider: () => settings.settings.baseUrl,
    );
    final globalSearch = GlobalSearchService(
      database: database,
      memoryEngine: engine,
      userIdProvider: () => settings.userId,
    );
    final historyTransfer = HistoryTransferService(
      database: database,
      backup: backups,
    );

    final services = AppServices(
      database: database,
      settings: settings,
      api: chatApi,
      memoryStore: store,
      memoryEngine: engine,
      search: search,
      attachments: attachments,
      exports: exports,
      backups: backups,
      conversations: conversations,
      memories: memories,
      voice: voice,
      globalSearch: globalSearch,
      historyTransfer: historyTransfer,
    );
    _instance = services;
    return services;
  }

  Future<void> dispose() async {
    conversations.dispose();
    memories.dispose();
    voice.dispose();
    settings.dispose();
    api.dispose();
    await database.close();
    _instance = null;
  }
}

/// 向下传递 [AppServices] 的 InheritedWidget。
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载：请确认根组件被 AppScope 包裹');
    return scope!.services;
  }

  static AppServices? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>()?.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.services != services;
}
