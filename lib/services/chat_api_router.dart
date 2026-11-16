/// ChatApi 路由：普通对话走 OpenAI 兼容接口，DeepSeek 内置联网搜索走
/// Anthropic 兼容接口（/anthropic/v1/messages）。
library;

import 'contracts.dart';

class ChatApiRouter implements ChatApi {
  ChatApiRouter({
    required ChatApi standard,
    required ChatApi serverSearch,
  })  : _standard = standard,
        _serverSearch = serverSearch;

  final ChatApi _standard;
  final ChatApi _serverSearch;

  ChatApi _active(ChatRequest request) =>
      request.useServerSearch ? _serverSearch : _standard;

  @override
  Stream<ChatStreamEvent> streamChat(ChatRequest request) =>
      _active(request).streamChat(request);

  @override
  Future<String> completeText({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double temperature = 0.3,
    int maxTokens = 1200,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _standard.completeText(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
    );
  }

  @override
  Future<void> validateApiKey() => _standard.validateApiKey();

  @override
  Future<List<String>> listModels() => _standard.listModels();

  @override
  Future<String> generateTitle({
    required String firstUserMessage,
    String? firstAssistantMessage,
  }) {
    return _standard.generateTitle(
      firstUserMessage: firstUserMessage,
      firstAssistantMessage: firstAssistantMessage,
    );
  }

  @override
  void dispose() {
    _standard.dispose();
    _serverSearch.dispose();
  }
}
