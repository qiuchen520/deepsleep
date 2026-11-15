/// 联网搜索路由：根据当前设置动态选择 Tavily / Serper（或关闭）。
library;

import '../data/models/chat_models.dart';
import 'contracts.dart';
import 'search_service_impl.dart';

class SearchRouter implements WebSearchService {
  SearchRouter({
    required String Function() backendProvider,
    required String Function() tavilyKeyProvider,
    required String Function() serperKeyProvider,
    int Function()? maxResultsProvider,
  })  : _backendProvider = backendProvider,
        _tavilyKeyProvider = tavilyKeyProvider,
        _serperKeyProvider = serperKeyProvider,
        _maxResultsProvider = maxResultsProvider;

  final String Function() _backendProvider;
  final String Function() _tavilyKeyProvider;
  final String Function() _serperKeyProvider;
  final int Function()? _maxResultsProvider;

  WebSearchService? _serviceFor(String backend) {
    switch (backend) {
      case 'tavily':
        final key = _tavilyKeyProvider();
        if (key.trim().isEmpty) return null;
        return TavilySearchService(apiKeyProvider: () => _tavilyKeyProvider());
      case 'serper':
        final key = _serperKeyProvider();
        if (key.trim().isEmpty) return null;
        return SerperSearchService(apiKeyProvider: () => _serperKeyProvider());
      default:
        return null;
    }
  }

  @override
  bool get isConfigured => _serviceFor(_backendProvider()) != null;

  @override
  Future<List<SearchHit>> search(String query, {int maxResults = 5}) async {
    final service = _serviceFor(_backendProvider());
    if (service == null) {
      throw const ApiException(
        ApiErrorKind.invalidRequest,
        '未配置联网搜索 API Key，请在设置中填写',
      );
    }
    final limit = _maxResultsProvider?.call() ?? maxResults;
    return service.search(query, maxResults: limit);
  }
}
