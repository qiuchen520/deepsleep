/// 用户档案与应用设置模型。
library;

import '../../core/constants.dart';

/// 一个用户档案（对应 mem0 里的 user_id 概念）。
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.emoji = '🙂',
    this.persona = '',
    required this.createdAt,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String emoji;

  /// 该用户的专属人设 / 额外 System Prompt。
  final String persona;
  final DateTime createdAt;
  final bool isDefault;

  UserProfile copyWith({
    String? name,
    String? emoji,
    String? persona,
    bool? isDefault,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      persona: persona ?? this.persona,
      createdAt: createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'emoji': emoji,
        'persona': persona,
        'createdAt': createdAt.toIso8601String(),
        'isDefault': isDefault,
      };

  static UserProfile fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String? ?? 'default',
        name: json['name'] as String? ?? '我',
        emoji: json['emoji'] as String? ?? '🙂',
        persona: json['persona'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

enum ThemePreference {
  system,
  light,
  dark;

  static ThemePreference fromName(String? name) =>
      ThemePreference.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ThemePreference.system,
      );
}

/// 记忆后端：本地知识网（默认）或 mem0 云平台。
enum MemoryBackend {
  local,
  mem0;

  static MemoryBackend fromName(String? name) =>
      MemoryBackend.values.firstWhere(
        (e) => e.name == name,
        orElse: () => MemoryBackend.local,
      );
}

/// 联网搜索服务商。
enum SearchBackend {
  off,
  deepseek,
  tavily,
  serper;

  static SearchBackend fromName(String? name) =>
      SearchBackend.values.firstWhere(
        (e) => e.name == name,
        orElse: () => SearchBackend.off,
      );
}

/// 应用设置（持久化在 SharedPreferences，JSON 格式）。
class AppSettings {
  const AppSettings({
    this.baseUrl = AppInfo.defaultBaseUrl,
    this.chatModel = AppInfo.defaultChatModel,
    this.reasonerModel = AppInfo.defaultReasonerModel,
    this.deepThinking = false,
    this.searchBackend = SearchBackend.deepseek,
    this.searchMaxResults = 5,
    this.memoryEnabled = true,
    this.autoExtractMemory = true,
    this.memoryBackend = MemoryBackend.local,
    this.mem0ApiUrl = 'https://api.mem0.ai',
    this.compressThreshold = AppInfo.defaultCompressThreshold,
    this.memoryTokenBudget = AppInfo.memoryTokenBudget,
    this.theme = ThemePreference.system,
    this.fontScale = 1.0,
    this.showTokenUsage = true,
    this.sendWithEnter = true,
    this.systemPromptExtra = '',
    this.temperature = 1.0,
    this.maxTokens = 4096,
    this.activeProfileId = 'default',
    this.onboardingDone = false,
  });

  final String baseUrl;
  final String chatModel;
  final String reasonerModel;

  /// 是否默认开启「深度思考」（走 reasoner 模型 + 展示思考过程）。
  final bool deepThinking;

  final SearchBackend searchBackend;
  final int searchMaxResults;

  final bool memoryEnabled;
  final bool autoExtractMemory;
  final MemoryBackend memoryBackend;
  final String mem0ApiUrl;

  /// 上下文 token 超过该值就压缩前半段。
  final int compressThreshold;
  final int memoryTokenBudget;

  final ThemePreference theme;
  final double fontScale;
  final bool showTokenUsage;
  final bool sendWithEnter;
  final String systemPromptExtra;
  final double temperature;
  final int maxTokens;
  final String activeProfileId;
  final bool onboardingDone;

  bool get searchEnabled => searchBackend != SearchBackend.off;

  String get effectiveModel => deepThinking ? reasonerModel : chatModel;

  AppSettings copyWith({
    String? baseUrl,
    String? chatModel,
    String? reasonerModel,
    bool? deepThinking,
    SearchBackend? searchBackend,
    int? searchMaxResults,
    bool? memoryEnabled,
    bool? autoExtractMemory,
    MemoryBackend? memoryBackend,
    String? mem0ApiUrl,
    int? compressThreshold,
    int? memoryTokenBudget,
    ThemePreference? theme,
    double? fontScale,
    bool? showTokenUsage,
    bool? sendWithEnter,
    String? systemPromptExtra,
    double? temperature,
    int? maxTokens,
    String? activeProfileId,
    bool? onboardingDone,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      chatModel: chatModel ?? this.chatModel,
      reasonerModel: reasonerModel ?? this.reasonerModel,
      deepThinking: deepThinking ?? this.deepThinking,
      searchBackend: searchBackend ?? this.searchBackend,
      searchMaxResults: searchMaxResults ?? this.searchMaxResults,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      autoExtractMemory: autoExtractMemory ?? this.autoExtractMemory,
      memoryBackend: memoryBackend ?? this.memoryBackend,
      mem0ApiUrl: mem0ApiUrl ?? this.mem0ApiUrl,
      compressThreshold: compressThreshold ?? this.compressThreshold,
      memoryTokenBudget: memoryTokenBudget ?? this.memoryTokenBudget,
      theme: theme ?? this.theme,
      fontScale: fontScale ?? this.fontScale,
      showTokenUsage: showTokenUsage ?? this.showTokenUsage,
      sendWithEnter: sendWithEnter ?? this.sendWithEnter,
      systemPromptExtra: systemPromptExtra ?? this.systemPromptExtra,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      activeProfileId: activeProfileId ?? this.activeProfileId,
      onboardingDone: onboardingDone ?? this.onboardingDone,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'baseUrl': baseUrl,
        'chatModel': chatModel,
        'reasonerModel': reasonerModel,
        'deepThinking': deepThinking,
        'searchBackend': searchBackend.name,
        'searchMaxResults': searchMaxResults,
        'memoryEnabled': memoryEnabled,
        'autoExtractMemory': autoExtractMemory,
        'memoryBackend': memoryBackend.name,
        'mem0ApiUrl': mem0ApiUrl,
        'compressThreshold': compressThreshold,
        'memoryTokenBudget': memoryTokenBudget,
        'theme': theme.name,
        'fontScale': fontScale,
        'showTokenUsage': showTokenUsage,
        'sendWithEnter': sendWithEnter,
        'systemPromptExtra': systemPromptExtra,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'activeProfileId': activeProfileId,
        'onboardingDone': onboardingDone,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        baseUrl: json['baseUrl'] as String? ?? AppInfo.defaultBaseUrl,
        chatModel: json['chatModel'] as String? ?? AppInfo.defaultChatModel,
        reasonerModel:
            json['reasonerModel'] as String? ?? AppInfo.defaultReasonerModel,
        deepThinking: json['deepThinking'] as bool? ?? false,
        searchBackend:
            SearchBackend.fromName(json['searchBackend'] as String?),
        searchMaxResults:
            (json['searchMaxResults'] as num?)?.toInt() ?? 5,
        memoryEnabled: json['memoryEnabled'] as bool? ?? true,
        autoExtractMemory: json['autoExtractMemory'] as bool? ?? true,
        memoryBackend:
            MemoryBackend.fromName(json['memoryBackend'] as String?),
        mem0ApiUrl: json['mem0ApiUrl'] as String? ?? 'https://api.mem0.ai',
        compressThreshold:
            (json['compressThreshold'] as num?)?.toInt() ??
                AppInfo.defaultCompressThreshold,
        memoryTokenBudget: (json['memoryTokenBudget'] as num?)?.toInt() ??
            AppInfo.memoryTokenBudget,
        theme: ThemePreference.fromName(json['theme'] as String?),
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        showTokenUsage: json['showTokenUsage'] as bool? ?? true,
        sendWithEnter: json['sendWithEnter'] as bool? ?? true,
        systemPromptExtra: json['systemPromptExtra'] as String? ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 1.0,
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 4096,
        activeProfileId: json['activeProfileId'] as String? ?? 'default',
        onboardingDone: json['onboardingDone'] as bool? ?? false,
      );
}
