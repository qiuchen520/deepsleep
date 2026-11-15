/// 记忆检索打分（纯 Dart）。
///
/// 综合分公式（权重固定，便于单测与调参对照）：
/// ```
/// score = 0.42 * keywordOverlap
///       + 0.18 * graphBoost
///       + 0.18 * importance
///       + 0.22 * freshness
/// ```
/// 额外规则：`pinned` 记忆加 [pinnedBoost]（置顶是显式偏好，应该压过普通排序）。
library;

import '../../data/models/memory_models.dart';
import 'memory_utils.dart';

/// 关键词重叠权重。
const double keywordWeight = 0.42;

/// 知识图扩展权重。
const double graphWeight = 0.18;

/// 重要度权重。
const double importanceWeight = 0.18;

/// 时间新鲜度权重。
const double freshnessWeight = 0.22;

/// 置顶记忆的额外加分。
const double pinnedBoost = 0.12;

/// 一条记忆的打分明细。
class ScoredMemory {
  const ScoredMemory({
    required this.item,
    required this.score,
    this.keywordScore = 0,
    this.graphScore = 0,
    this.importanceScore = 0,
    this.freshnessScore = 0,
  });

  final MemoryItem item;

  /// 最终综合分。
  final double score;

  /// 关键词重叠 0~1。
  final double keywordScore;

  /// 图扩展命中 0~1。
  final double graphScore;

  /// 重要度 0~1。
  final double importanceScore;

  /// 时间新鲜度 0~1（由 [MemoryItem.freshness] 计算）。
  final double freshnessScore;

  @override
  String toString() =>
      'ScoredMemory(${item.id}, score=$score, kw=$keywordScore, '
      'graph=$graphScore, imp=$importanceScore, fresh=$freshnessScore)';
}

/// 计算综合分（纯函数，单测可直接校验公式）。
double computeMemoryScore({
  required double keywordOverlap,
  required double graphBoost,
  required double importance,
  required double freshness,
  bool pinned = false,
}) {
  var score = keywordWeight * clamp01(keywordOverlap) +
      graphWeight * clamp01(graphBoost) +
      importanceWeight * clamp01(importance) +
      freshnessWeight * clamp01(freshness);
  if (pinned) score += pinnedBoost;
  return score;
}

/// 计算单条记忆的关键词重叠分 0~1。
///
/// 匹配来源：记忆 keywords、实体名、以及从 content 现抽的关键词；
/// 关键词匹配支持中文包含、英文大小写无关与轻量词干化。
double keywordScoreForItem(MemoryItem item, Set<String> queryTokens) {
  if (queryTokens.isEmpty) return 0;
  final keys = <String>{};
  for (final keyword in item.keywords) {
    final key = keyword.trim().toLowerCase();
    if (key.isNotEmpty) keys.add(key);
  }
  for (final entity in item.entities) {
    final key = entity.trim().toLowerCase();
    if (key.isNotEmpty) keys.add(key);
  }
  keys.addAll(extractKeywords(item.content, maxKeywords: 8));

  var hit = 0;
  for (final token in queryTokens) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) continue;
    if (keys.any((key) => tokenMatchesKey(key, t)) ||
        textMatchesToken(item.content, t)) {
      hit++;
    }
  }
  return (hit / queryTokens.length).clamp(0.0, 1.0).toDouble();
}

/// 计算单条记忆的知识图扩展分 0~1。
///
/// [graphEntityKeys] 是查询命中的实体及其 1 跳邻居（已归一化），
/// 记忆自身实体命中其中任意一个即获得基础分，覆盖越全分越高。
double graphScoreForItem(MemoryItem item, Set<String> graphEntityKeys) {
  if (graphEntityKeys.isEmpty) return 0;
  final keys = <String>{};
  for (final entity in item.entities) {
    final key = normalizeEntityKey(entity);
    if (key.isNotEmpty) keys.add(key);
  }
  if (keys.isEmpty) return 0;
  final matched = keys.where(graphEntityKeys.contains).length;
  if (matched == 0) return 0;
  final coverage = matched / keys.length;
  return (0.6 + 0.4 * coverage).clamp(0.0, 1.0).toDouble();
}

/// 对候选记忆打分并按综合分降序排序。
///
/// 排序打平规则依次为：综合分、重要度、更新时间、id（保证结果稳定可测）。
List<ScoredMemory> rankMemories({
  required List<MemoryItem> memories,
  required Set<String> queryTokens,
  Set<String> graphEntityKeys = const <String>{},
  DateTime? now,
}) {
  final scored = <ScoredMemory>[];
  for (final item in memories) {
    final keywordScore = keywordScoreForItem(item, queryTokens);
    final graphScore = graphScoreForItem(item, graphEntityKeys);
    final freshness = item.freshness(now: now);
    final score = computeMemoryScore(
      keywordOverlap: keywordScore,
      graphBoost: graphScore,
      importance: item.importance,
      freshness: freshness,
      pinned: item.pinned,
    );
    scored.add(
      ScoredMemory(
        item: item,
        score: score,
        keywordScore: keywordScore,
        graphScore: graphScore,
        importanceScore: item.importance,
        freshnessScore: freshness,
      ),
    );
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byImportance = b.item.importance.compareTo(a.item.importance);
    if (byImportance != 0) return byImportance;
    final byUpdated = b.item.updatedAt.compareTo(a.item.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return a.item.id.compareTo(b.item.id);
  });
  return scored;
}
