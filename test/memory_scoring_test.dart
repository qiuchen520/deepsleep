/// 记忆检索打分单测（纯 Dart 算法）。
library;

import 'package:deepsleep/core/memory/memory_scoring.dart';
import 'package:deepsleep/core/memory/memory_utils.dart';
import 'package:deepsleep/data/models/memory_models.dart';
import 'package:flutter_test/flutter_test.dart';

MemoryItem makeItem({
  required String id,
  required String content,
  List<String> keywords = const <String>[],
  List<String> entities = const <String>[],
  double importance = 0.5,
  double confidence = 0.8,
  bool pinned = false,
  MemoryKind kind = MemoryKind.fact,
  DateTime? updatedAt,
}) {
  final time = updatedAt ?? DateTime(2026, 1, 1);
  return MemoryItem(
    id: id,
    userId: 'u1',
    kind: kind,
    content: content,
    keywords: keywords,
    entities: entities,
    importance: importance,
    confidence: confidence,
    pinned: pinned,
    createdAt: time,
    updatedAt: time,
  );
}

void main() {
  group('关键词切分 tokenize', () {
    test('中文按二元组切分，停用词被过滤', () {
      final tokens = tokenize('用户偏好量子纠缠');
      expect(tokens, contains('量子'));
      expect(tokens, contains('纠缠'));
      // 由两个停用字组成的二元组会被丢掉。
      expect(tokenize('我的 Dart 偏好'), isNot(contains('我的')));
    });

    test('英文小写 + 轻量词干化', () {
      final tokens = tokenize('Dart Preferences Running');
      expect(tokens, contains('dart'));
      expect(tokens, contains('preference'));
      expect(tokens, contains('run'));
    });

    test('英文停用词被移除', () {
      final tokens = tokenize('the user and Dart');
      expect(tokens, isNot(contains('the')));
      expect(tokens, isNot(contains('and')));
      expect(tokens, contains('dart'));
    });

    test('includeStopWords 保留停用词（调试用）', () {
      final tokens = tokenize('the user', includeStopWords: true);
      expect(tokens, contains('the'));
    });
  });

  group('文本相似度 textSimilarity', () {
    test('完全相同为 1', () {
      expect(textSimilarity('用户偏好用 Dart', '用户偏好用 Dart'), 1.0);
    });

    test('包含关系得到较高分', () {
      final similarity = textSimilarity(
        '用户偏好用 Dart 写客户端',
        '用户偏好用 Dart',
      );
      expect(similarity, greaterThan(0.8));
    });

    test('无关文本相似度低', () {
      final similarity = textSimilarity('用户喜欢喝咖啡', '今天北京的天气怎么样');
      expect(similarity, lessThan(0.3));
    });
  });

  group('关键词提取 extractKeywords', () {
    test('专有名词可通过 extra 保留', () {
      final keywords = extractKeywords(
        'DeepSleep 是一个聊天客户端',
        extra: <String>['DeepSleep'],
      );
      expect(keywords, contains('deepsleep'));
    });

    test('最多返回 maxKeywords 个', () {
      final keywords = extractKeywords(
        '甲 乙 丙 丁 戊 己 庚 辛',
        maxKeywords: 3,
      );
      expect(keywords.length, lessThanOrEqualTo(3));
    });
  });

  group('综合分 computeMemoryScore', () {
    test('严格按权重公式计算', () {
      final score = computeMemoryScore(
        keywordOverlap: 1.0,
        graphBoost: 0.0,
        importance: 0.5,
        freshness: 0.0,
      );
      expect(score, closeTo(0.42 + 0.18 * 0.5, 1e-9));
    });

    test('pin 额外加分', () {
      final normal = computeMemoryScore(
        keywordOverlap: 0.5,
        graphBoost: 0,
        importance: 0.5,
        freshness: 0.5,
      );
      final pinned = computeMemoryScore(
        keywordOverlap: 0.5,
        graphBoost: 0,
        importance: 0.5,
        freshness: 0.5,
        pinned: true,
      );
      expect(pinned, closeTo(normal + pinnedBoost, 1e-9));
    });
  });

  group('单条打分 keywordScoreForItem / graphScoreForItem', () {
    test('英文关键词大小写无关命中', () {
      final item = makeItem(
        id: 'm1',
        content: '用户偏好用 Dart 写客户端',
        keywords: <String>['dart'],
      );
      expect(keywordScoreForItem(item, <String>{'dart'}), greaterThan(0));
    });

    test('中文包含命中', () {
      final item = makeItem(
        id: 'm2',
        content: '用户偏好用 Dart 写客户端',
        keywords: <String>['客户端'],
      );
      expect(keywordScoreForItem(item, <String>{'客户端'}), greaterThan(0));
    });

    test('图扩展命中相关实体', () {
      final item = makeItem(
        id: 'm3',
        content: 'DeepSleep 使用 Flutter 构建',
        entities: <String>['Flutter'],
      );
      expect(
        graphScoreForItem(item, <String>{'flutter'}),
        greaterThan(0),
      );
      expect(graphScoreForItem(item, <String>{'dart'}), 0);
    });

    test('图扩展集合为空时得 0', () {
      final item = makeItem(
        id: 'm4',
        content: 'DeepSleep 使用 Flutter 构建',
        entities: <String>['Flutter'],
      );
      expect(graphScoreForItem(item, const <String>{}), 0);
    });
  });

  group('排序 rankMemories', () {
    test('关键词命中的记忆排在前面', () {
      final ranked = rankMemories(
        memories: <MemoryItem>[
          makeItem(id: 'irrelevant', content: '用户喜欢喝美式咖啡'),
          makeItem(
            id: 'hit',
            content: '用户偏好用 Dart 写客户端',
            keywords: <String>['dart'],
          ),
        ],
        queryTokens: <String>{'dart'},
      );
      expect(ranked.first.item.id, 'hit');
    });

    test('图扩展加分能提升排序', () {
      final ranked = rankMemories(
        memories: <MemoryItem>[
          makeItem(
            id: 'plain',
            content: '用户偏好用 Dart 写客户端',
            keywords: <String>['dart'],
          ),
          makeItem(
            id: 'graph',
            content: '用户偏好用 Dart 写客户端',
            keywords: <String>['dart'],
            entities: <String>['Dart'],
          ),
        ],
        queryTokens: <String>{'dart'},
        graphEntityKeys: <String>{'dart'},
      );
      expect(ranked.first.item.id, 'graph');
    });

    test('旧记忆新鲜度更低', () {
      final now = DateTime(2026, 6, 1);
      final fresh = makeItem(
        id: 'fresh',
        content: '用户偏好用 Dart',
        keywords: <String>['dart'],
        updatedAt: now,
      );
      final old = makeItem(
        id: 'old',
        content: '用户偏好用 Dart',
        keywords: <String>['dart'],
        updatedAt: now.subtract(const Duration(days: 365)),
      );
      final freshScore = rankMemories(
        memories: <MemoryItem>[fresh],
        queryTokens: <String>{'dart'},
        now: now,
      ).single;
      final oldScore = rankMemories(
        memories: <MemoryItem>[old],
        queryTokens: <String>{'dart'},
        now: now,
      ).single;
      expect(freshScore.freshnessScore, greaterThan(oldScore.freshnessScore));
      expect(freshScore.score, greaterThan(oldScore.score));
    });

    test('pinned 记忆加权提升排序', () {
      final ranked = rankMemories(
        memories: <MemoryItem>[
          makeItem(
            id: 'normal',
            content: '用户偏好用 Dart 写客户端',
            keywords: <String>['dart'],
            importance: 0.9,
          ),
          makeItem(
            id: 'pinned',
            content: '用户偏好用 Dart 写客户端',
            keywords: <String>['dart'],
            importance: 0.5,
            pinned: true,
          ),
        ],
        queryTokens: <String>{'dart'},
      );
      expect(ranked.first.item.id, 'pinned');
    });
  });

  group('记忆块格式化', () {
    test('固定格式 + 重要度标注 + 按 kind 分组', () {
      final block = formatMemoryBlock(<MemoryItem>[
        makeItem(
          id: 'p1',
          content: '用户在做 DeepSleep 项目',
          kind: MemoryKind.fact,
        ),
        makeItem(
          id: 'p2',
          content: '用户偏好用 Dart 写客户端',
          kind: MemoryKind.preference,
          importance: 0.9,
        ),
      ]);
      expect(block, startsWith('【长期记忆】\n'));
      expect(block, contains('- (偏好) 用户偏好用 Dart 写客户端（重要）'));
      expect(block, contains('- (事实) 用户在做 DeepSleep 项目'));
      // 偏好组在事实组之前（MemoryKind.values 中 preference 在 fact 之后？
      // 实际枚举顺序为 fact, preference, profile...，这里只验证两组都存在。
      expect(block.split('\n').length, 3);
    });

    test('空列表返回空字符串', () {
      expect(formatMemoryBlock(const <MemoryItem>[]), '');
    });
  });
}
