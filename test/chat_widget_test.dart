import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepsleep/core/theme/app_theme.dart';
import 'package:deepsleep/data/models/chat_models.dart';
import 'package:deepsleep/features/chat/widgets/search_hits_card.dart';
import 'package:deepsleep/features/chat/widgets/thinking_panel.dart';
import 'package:deepsleep/widgets/chart_block.dart';
import 'package:deepsleep/widgets/code_block.dart';
import 'package:deepsleep/widgets/markdown_view.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[child],
      ),
    ),
  );
}

void main() {
  testWidgets('Markdown 混合内容可以渲染（标题/表格/代码块）', (tester) async {
    const sample = '# 标题\n\n'
        '中文段落，包含 **粗体**、*斜体* 和 `inline code`。\n\n'
        '```dart\nvoid main() {\n  debugPrint("hi");\n}\n```\n\n'
        '| 列1 | 列2 |\n| --- | --- |\n| a | b |\n\n'
        '- 列表项一\n- 列表项二\n\n> 引用内容\n\n[链接](https://example.com)\n';
    await tester.pumpWidget(_host(const MarkdownView(data: sample)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Markdown 带 chart 代码块可以渲染', (tester) async {
    const sample = '下面是图表：\n\n'
        '```chart\n'
        '{"type":"bar","labels":["一","二"],"values":[3,5]}\n'
        '```\n\n结束。';
    await tester.pumpWidget(_host(const MarkdownView(data: sample)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Markdown 以代码块结尾也能渲染', (tester) async {
    const sample = '看代码：\n\n```dart\nvoid main() {}\n```';
    await tester.pumpWidget(_host(const MarkdownView(data: sample)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });



  testWidgets('思考面板可以渲染', (tester) async {
    await tester.pumpWidget(
      _host(
        ThinkingPanel(
          reasoning: '先分析问题，再给出答案。',
          streaming: false,
          startedAt: DateTime(2026, 1, 1, 12, 0, 0),
          finishedAt: DateTime(2026, 1, 1, 12, 0, 3),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索结果卡片可以渲染', (tester) async {
    await tester.pumpWidget(
      _host(
        const SearchHitsCard(
          hits: <SearchHit>[
            SearchHit(
              title: '北京时间',
              url: 'https://example.com/time',
              snippet: '当前北京时间',
              engine: 'deepseek',
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
