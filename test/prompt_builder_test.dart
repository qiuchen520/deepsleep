import 'package:flutter_test/flutter_test.dart';

import 'package:deepsleep/core/memory/contracts.dart';
import 'package:deepsleep/core/prompt_builder.dart';
import 'package:deepsleep/data/models/chat_models.dart';
import 'package:deepsleep/data/models/memory_models.dart';
import 'package:deepsleep/data/models/profile_models.dart';

MemoryItem _memory({
  required String id,
  required String content,
  MemoryKind kind = MemoryKind.fact,
}) {
  final now = DateTime(2026, 1, 1);
  return MemoryItem(
    id: id,
    userId: 'u1',
    kind: kind,
    content: content,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final profile = UserProfile(
    id: 'u1',
    name: '小林',
    createdAt: DateTime(2026, 1, 1),
  );

  group('buildSystemPrompt', () {
    test('包含基础人设与回答要求', () {
      final prompt = buildSystemPrompt(profile: profile);
      expect(prompt, contains('DeepSleep'));
      expect(prompt, contains('回答要求'));
    });

    test('注入人设、摘要、记忆、搜索结果与附加要求', () {
      final memory = MemoryContext(
        systemBlock: '【长期记忆】\n- (偏好) 用户喜欢 Dart',
        items: <MemoryItem>[
          _memory(id: 'm1', content: '用户喜欢 Dart', kind: MemoryKind.preference),
        ],
        tokens: 20,
      );
      final prompt = buildSystemPrompt(
        profile: profile.copyWith(persona: '说话简短'),
        memory: memory,
        summary: '之前聊过 Flutter 项目',
        searchHits: <SearchHit>[
          const SearchHit(
            title: 'Flutter 官网',
            url: 'https://flutter.dev',
            snippet: 'Flutter 是 UI 工具包',
          ),
        ],
        extra: '不要使用表情符号',
      );

      expect(prompt, contains('说话简短'));
      expect(prompt, contains('Flutter 项目'));
      expect(prompt, contains('用户喜欢 Dart'));
      expect(prompt, contains('Flutter 官网'));
      expect(prompt, contains('https://flutter.dev'));
      expect(prompt, contains('不要使用表情符号'));
    });

    test('没有记忆时不输出长期记忆标题', () {
      final prompt = buildSystemPrompt(profile: profile);
      expect(prompt, isNot(contains('长期记忆')));
    });
  });

  group('buildUserTurnContent', () {
    test('无附件时原样返回', () {
      expect(
        buildUserTurnContent('你好', const <AttachmentRef>[], ''),
        '你好',
      );
    });

    test('有附件时附带解析内容', () {
      final refs = <AttachmentRef>[
        const AttachmentRef(
          id: 'a1',
          name: 'notes.txt',
          mime: 'text/plain',
          size: 10,
          kind: AttachmentKind.text,
          extractedText: '文件里的内容',
        ),
      ];
      final content = buildUserTurnContent('请总结', refs, '文件里的内容');
      expect(content, contains('请总结'));
      expect(content, contains('notes.txt'));
      expect(content, contains('文件里的内容'));
    });

    test('附件无法解析时给出提示', () {
      final refs = <AttachmentRef>[
        const AttachmentRef(
          id: 'a2',
          name: 'scan.pdf',
          mime: 'application/pdf',
          size: 1024,
          kind: AttachmentKind.document,
        ),
      ];
      final content = buildUserTurnContent('看看这个', refs, '');
      expect(content, contains('无法在本机解析'));
    });
  });
}
