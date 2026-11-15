/// 联网搜索服务实现：Tavily 与 Serper（Google）。
///
/// 只依赖 `http` 与领域模型，不依赖 Flutter。
/// 未配置 API Key 时 [isConfigured] 为 false，调用 [search] 会抛出
/// [ApiException]（UI 可据此提示用户去设置页填写 Key）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/chat_models.dart';
import 'contracts.dart';

/// 联网搜索的通用超时。
const Duration _searchTimeout = Duration(seconds: 25);

/// Tavily 搜索（https://tavily.com）。
///
/// 请求：
/// ```json
/// {"api_key":"...","query":"...","max_results":5,"search_depth":"basic"}
/// ```
class TavilySearchService implements WebSearchService {
  TavilySearchService({
    required String Function() apiKeyProvider,
    http.Client? httpClient,
    Duration timeout = _searchTimeout,
  })  : _apiKeyProvider = apiKeyProvider,
        _httpClient = httpClient,
        _timeout = timeout;

  final String Function() _apiKeyProvider;
  final http.Client? _httpClient;
  final Duration _timeout;

  static const String _endpoint = 'https://api.tavily.com/search';

  @override
  bool get isConfigured => _apiKeyProvider().trim().isNotEmpty;

  @override
  Future<List<SearchHit>> search(String query, {int maxResults = 5}) async {
    final apiKey = _requireApiKey();
    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    try {
      final http.Response response;
      try {
        response = await client
            .post(
              Uri.parse(_endpoint),
              headers: const <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
              },
              body: jsonEncode(<String, dynamic>{
                'api_key': apiKey,
                'query': query,
                'max_results': maxResults,
                'search_depth': 'basic',
              }),
            )
            .timeout(_timeout);
      } catch (error) {
        throw _mapError(error);
      }

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        throw _httpError(response.statusCode, body);
      }

      final root = _decodeObject(body);
      final results = root['results'];
      final hits = <SearchHit>[];
      if (results is List) {
        for (final item in results) {
          final map = _asMap(item);
          if (map == null) continue;
          final url = _asText(map['url']);
          if (url.isEmpty) continue;
          hits.add(
            SearchHit(
              title: _asText(map['title']),
              url: url,
              snippet: _asText(map['content']),
              engine: 'tavily',
            ),
          );
          if (hits.length >= maxResults) break;
        }
      }
      return hits;
    } finally {
      if (ownsClient) client.close();
    }
  }

  String _requireApiKey() {
    final key = _apiKeyProvider().trim();
    if (key.isEmpty) {
      throw const ApiException(
        ApiErrorKind.invalidRequest,
        '未配置联网搜索 API Key',
      );
    }
    return key;
  }
}

/// Serper 搜索（https://serper.dev，Google 结果）。
class SerperSearchService implements WebSearchService {
  SerperSearchService({
    required String Function() apiKeyProvider,
    http.Client? httpClient,
    Duration timeout = _searchTimeout,
  })  : _apiKeyProvider = apiKeyProvider,
        _httpClient = httpClient,
        _timeout = timeout;

  final String Function() _apiKeyProvider;
  final http.Client? _httpClient;
  final Duration _timeout;

  static const String _endpoint = 'https://google.serper.dev/search';

  @override
  bool get isConfigured => _apiKeyProvider().trim().isNotEmpty;

  @override
  Future<List<SearchHit>> search(String query, {int maxResults = 5}) async {
    final apiKey = _requireApiKey();
    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    try {
      final http.Response response;
      try {
        response = await client
            .post(
              Uri.parse(_endpoint),
              headers: <String, String>{
                'X-API-KEY': apiKey,
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
              },
              body: jsonEncode(<String, dynamic>{
                'q': query,
                'num': maxResults,
              }),
            )
            .timeout(_timeout);
      } catch (error) {
        throw _mapError(error);
      }

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        throw _httpError(response.statusCode, body);
      }

      final root = _decodeObject(body);
      final organic = root['organic'];
      final hits = <SearchHit>[];
      if (organic is List) {
        for (final item in organic) {
          final map = _asMap(item);
          if (map == null) continue;
          final url = _asText(map['link']);
          if (url.isEmpty) continue;
          hits.add(
            SearchHit(
              title: _asText(map['title']),
              url: url,
              snippet: _asText(map['snippet']),
              engine: 'serper',
            ),
          );
          if (hits.length >= maxResults) break;
        }
      }
      return hits;
    } finally {
      if (ownsClient) client.close();
    }
  }

  String _requireApiKey() {
    final key = _apiKeyProvider().trim();
    if (key.isEmpty) {
      throw const ApiException(
        ApiErrorKind.invalidRequest,
        '未配置联网搜索 API Key',
      );
    }
    return key;
  }
}

// -----------------------------------------------------------------------------
// 共用小工具（私有，两个实现共享同一套错误映射）
// -----------------------------------------------------------------------------

Map<String, dynamic> _decodeObject(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const ApiException(ApiErrorKind.protocol, '搜索服务返回了无法解析的响应');
  }
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const ApiException(ApiErrorKind.protocol, '搜索服务返回格式不正确');
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

String _asText(Object? value) => value is String ? value.trim() : '';

ApiException _httpError(int statusCode, String body) {
  String? message;
  final root = _tryObject(body);
  if (root != null) {
    final error = _asMap(root['error']);
    final raw = error?['message'] ?? root['message'] ?? root['detail'];
    if (raw is String && raw.trim().isNotEmpty) message = raw.trim();
  }
  if (message != null && message.length > 300) {
    message = message.substring(0, 300);
  }
  if (statusCode == 401 || statusCode == 403) {
    return ApiException(
      ApiErrorKind.auth,
      message ?? '联网搜索 API Key 无效或已过期',
      statusCode: statusCode,
    );
  }
  if (statusCode == 402) {
    return ApiException(
      ApiErrorKind.insufficientBalance,
      message ?? '联网搜索账户余额不足',
      statusCode: statusCode,
    );
  }
  if (statusCode == 429) {
    return ApiException(
      ApiErrorKind.rateLimited,
      message ?? '联网搜索请求过于频繁',
      statusCode: statusCode,
    );
  }
  if (statusCode >= 500) {
    return ApiException(
      ApiErrorKind.serverBusy,
      message ?? '联网搜索服务暂时不可用',
      statusCode: statusCode,
    );
  }
  return ApiException(
    ApiErrorKind.invalidRequest,
    message ?? '联网搜索请求失败（HTTP $statusCode）',
    statusCode: statusCode,
  );
}

Map<String, dynamic>? _tryObject(String body) {
  try {
    final decoded = jsonDecode(body);
    return _asMap(decoded);
  } on FormatException {
    return null;
  }
}

ApiException _mapError(Object error) {
  if (error is ApiException) return error;
  if (error is TimeoutException) {
    return const ApiException(ApiErrorKind.network, '联网搜索超时，请稍后重试');
  }
  if (error is SocketException || error is http.ClientException) {
    return const ApiException(ApiErrorKind.network, '联网搜索失败，请检查网络');
  }
  return ApiException(ApiErrorKind.unknown, '联网搜索失败：$error');
}
