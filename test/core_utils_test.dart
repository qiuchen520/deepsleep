import 'package:flutter_test/flutter_test.dart';

import 'package:deepsleep/core/utils/time_utils.dart';
import 'package:deepsleep/core/utils/token_estimator.dart';

void main() {
  group('token estimator', () {
    test('空字符串为 0', () {
      expect(estimateTokens(''), 0);
    });

    test('中文约 1 token/字', () {
      final tokens = estimateTokens('今天有什么可以帮到你');
      expect(tokens, greaterThanOrEqualTo(9));
      expect(tokens, lessThanOrEqualTo(14));
    });

    test('英文按 4 字符约 1 token', () {
      final tokens = estimateTokens('hello world this is a test');
      expect(tokens, inInclusiveRange(5, 12));
    });

    test('消息有结构开销', () {
      final content = estimateTokens('你好');
      final message = estimateMessageTokens('你好');
      expect(message, content + perMessageOverhead);
    });

    test('reasoning 计入 token', () {
      final withoutReasoning = estimateMessageTokens('答案');
      final withReasoning = estimateMessageTokens('答案', reasoning: '先分析一下这个问题');
      expect(withReasoning, greaterThan(withoutReasoning));
    });

    test('truncateToTokens 不超预算', () {
      final text = '这是一段很长的中文内容，' * 100;
      final result = truncateToTokens(text, 50);
      expect(estimateTokens(result), lessThanOrEqualTo(50));
      expect(result.length, lessThan(text.length));
    });

    test('对话 token 汇总包含额外开销', () {
      final total = estimateConversationTokens(['你好', '世界'], extra: 10);
      expect(total, greaterThan(10));
    });
  });

  group('time utils', () {
    final now = DateTime(2026, 11, 15, 20, 0);

    test('会话分组', () {
      expect(conversationGroupLabel(DateTime(2026, 11, 15, 8), now: now), '今天');
      expect(conversationGroupLabel(DateTime(2026, 11, 14, 8), now: now), '昨天');
      expect(conversationGroupLabel(DateTime(2026, 11, 11, 8), now: now), '7 天内');
      expect(conversationGroupLabel(DateTime(2026, 10, 25, 8), now: now), '30 天内');
      expect(conversationGroupLabel(DateTime(2026, 9, 1, 8), now: now), '更早');
    });

    test('标题兜底', () {
      expect(fallbackTitle('  你好世界  '), '你好世界');
      expect(fallbackTitle('', ), '新对话');
      final long = '一' * 50;
      expect(fallbackTitle(long).endsWith('…'), isTrue);
    });

    test('相对时间', () {
      expect(formatRelative(now, now: now), '刚刚');
      expect(
        formatRelative(now.subtract(const Duration(minutes: 5)), now: now),
        '5 分钟前',
      );
    });
  });
}
