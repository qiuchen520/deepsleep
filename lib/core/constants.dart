/// 全局常量与默认配置。
library;

class AppInfo {
  AppInfo._();

  static const String appName = 'DeepSleep';
  static const String appNameCn = '记忆对话';
  static const String version = '1.0.0';
  static const String repoUrl = 'https://github.com/deepsleep-app/deepsleep';

  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultChatModel = 'deepseek-chat';
  static const String defaultReasonerModel = 'deepseek-reasoner';

  /// 上下文超过该 token 数时，把前半段压缩成摘要。
  static const int defaultCompressThreshold = 4000;

  /// 单次注入 System Prompt 的记忆预算。
  static const int memoryTokenBudget = 600;

  /// 压缩摘要允许占用的 token 预算。
  static const int summaryTokenBudget = 700;

  /// 最近若干条消息永远不会被压缩掉。
  static const int keepRecentMessages = 6;

  /// 记忆抽取/压缩使用的模型（用便宜快的模型即可）。
  static const String memoryModel = 'deepseek-chat';

  static const String disclaimer = '内容由 AI 生成，请仔细甄别';
  static const String welcomeTitle = '今天有什么可以帮到你？';

  static const List<String> welcomeSuggestions = <String>[
    '帮我用三句话解释量子纠缠',
    '写一个 Python 脚本批量重命名文件',
    '总结一下我们之前聊过的技术栈偏好',
    '把这段话润色得更专业一些',
  ];

  static const List<String> defaultSystemPrompt = <String>[
    'You are DeepSleep, a helpful, accurate and friendly AI assistant.',
    'Answer in the same language the user writes in. Use Markdown when it improves readability.',
    'If the user attaches files, ground your answer on their content and say so when the content is insufficient.',
  ];
}

class StorageKeys {
  StorageKeys._();

  static const String settings = 'deepsleep.settings.v1';
  static const String activeProfile = 'deepsleep.profile.active';
  static const String lastConversation = 'deepsleep.conversation.last';
  static const String onboardingDone = 'deepsleep.onboarding.done';
  static const String apiKey = 'deepsleep.api.key';
  static const String searchApiKey = 'deepsleep.search.key';
  static const String mem0ApiKey = 'deepsleep.mem0.key';
}
