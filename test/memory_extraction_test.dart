/// 记忆抽取 JSON 解析与合并决策单测。
library;

import 'package:deepsleep/core/memory/extraction.dart';
import 'package:deepsleep/data/models/memory_models.dart';
import 'package:flutter_test/flutter_test.dart';

MemoryItem existingItem({
  String id = 'm1',
  String content = '用户偏好用 Python',
  MemoryKind kind = MemoryKind.preference,
  List<String> keywords = const <String>[],
  List<String> entities = const <String>[],
  double importance = 0.5,
  double confidence = 0.8,
  String? subject,
  String? predicate,
  String? object,
  MemoryStatus status = MemoryStatus.active,
  String fingerprint = '',
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
    status: status,
    subject: subject,
    predicate: predicate,
    object: object,
    fingerprint: fingerprint,
    createdAt: time,
    updatedAt: time,
  );
}

void main() {
  group('ParsedExtraction.parse 容错解析', () {
    test('带 ```json 围栏与前后废话', () {
      const raw = '好的，抽取结果如下：\n'
          '```json\n'
          '{"memories":[{"kind":"preference","content":"用户偏好用 Dart 写客户端",'
          '"keywords":["dart"],"entities":["Dart"],"importance":0.9,'
          '"confidence":0.9,"subject":"用户","predicate":"偏好技术栈",'
          '"object":"Dart","action":"add"}],'
          '"entities":[{"name":"Dart","type":"technology"}],'
          '"relations":[{"source":"用户","relation":"偏好","target":"Dart"}]}\n'
          '```\n'
          '以上。';
      final parsed = ParsedExtraction.parse(raw);
      expect(parsed.errors, isEmpty);
      expect(parsed.memories, hasLength(1));
      final memory = parsed.memories.single;
      expect(memory.kind, MemoryKind.preference);
      expect(memory.content, contains('Dart'));
      expect(memory.importance, closeTo(0.9, 1e-9));
      expect(memory.subject, '用户');
      expect(memory.action, MemoryAction.add);
      expect(parsed.entities.single.name, 'Dart');
      expect(parsed.entities.single.type, 'technology');
      expect(parsed.relations.single.relation, '偏好');
    });

    test('单条记忆失败只跳过该条，整体成功', () {
      const raw = '{"memories":[{"content":""},'
          '{"content":"用户在做 DeepSleep 项目","kind":"fact"}],'
          '"entities":[],"relations":[]}';
      final parsed = ParsedExtraction.parse(raw);
      expect(parsed.memories, hasLength(1));
      expect(parsed.memories.single.content, '用户在做 DeepSleep 项目');
      expect(parsed.errors, isNotEmpty);
    });

    test('顶层直接数组也能解析', () {
      final parsed = ParsedExtraction.parse('[{"content":"用户喜欢咖啡"}]');
      expect(parsed.memories, hasLength(1));
      expect(parsed.memories.single.content, '用户喜欢咖啡');
      expect(parsed.memories.single.kind, MemoryKind.fact);
    });

    test('尾逗号容错', () {
      const raw = '{"memories":[{"content":"用户喜欢咖啡"},],'
          '"entities":[],"relations":[]}';
      final parsed = ParsedExtraction.parse(raw);
      expect(parsed.memories, hasLength(1));
    });

    test('完全非 JSON 时返回错误而不抛异常', () {
      final parsed = ParsedExtraction.parse('抱歉，我无法抽取。');
      expect(parsed.isEmpty, isTrue);
      expect(parsed.errors, isNotEmpty);
    });

    test('非法实体 / 关系被跳过', () {
      const raw = '{"memories":[],'
          '"entities":[{"type":"concept"},{"name":"Flutter"}],'
          '"relations":[{"source":"A","target":"B"},{"source":"A"}]}';
      final parsed = ParsedExtraction.parse(raw);
      expect(parsed.entities, hasLength(1));
      expect(parsed.entities.single.name, 'Flutter');
      expect(parsed.relations, hasLength(1));
      expect(parsed.errors, hasLength(2));
    });
  });

  group('buildMergeDecision 合并决策', () {
    test('全新记忆 -> added，并补齐 id / fingerprint / keywords', () {
      final extraction = ParsedExtraction.parse(
        '{"memories":[{"kind":"preference",'
        '"content":"用户偏好用 Dart 写客户端","keywords":["dart"],'
        '"entities":["Dart"],"importance":0.8}]}',
      );
      final decision = buildMergeDecision(
        userId: 'u1',
        extraction: extraction,
        existingMemories: const <MemoryItem>[],
      );
      expect(decision.added, 1);
      expect(decision.updated, 0);
      expect(decision.superseded, 0);
      expect(decision.toSave, hasLength(1));
      final item = decision.toSave.single;
      expect(item.id, isNotEmpty);
      expect(item.fingerprint, isNotEmpty);
      expect(item.keywords, contains('dart'));
      expect(item.entities, contains('Dart'));
      expect(item.status, MemoryStatus.active);
      expect(item.importance, closeTo(0.8, 1e-9));
      expect(decision.touched, hasLength(1));
      expect(decision.entityNames, contains('Dart'));
    });

    test('相同内容 / 相似度超阈值 -> 更新已有记忆而不是新增', () {
      final existing = existingItem(
        content: '用户偏好用 Dart 写客户端',
        keywords: <String>['dart'],
      );
      final extraction = ParsedExtraction.parse(
        '{"memories":[{"kind":"preference",'
        '"content":"用户偏好用 Dart 写客户端","keywords":["客户端"],'
        '"importance":0.9}]}',
      );
      final decision = buildMergeDecision(
        userId: 'u1',
        extraction: extraction,
        existingMemories: <MemoryItem>[existing],
      );
      expect(decision.added, 0);
      expect(decision.updated, 1);
      expect(decision.toSave, hasLength(1));
      final updated = decision.toSave.single;
      expect(updated.id, 'm1');
      expect(updated.importance, closeTo(0.9, 1e-9));
      expect(updated.keywords, containsAll(<String>['dart', '客户端']));
    });

    test('同一 subject+predicate、不同 object -> 旧记忆 superseded', () {
      final existing = existingItem(
        content: '用户偏好用 Python 写脚本',
        subject: '用户',
        predicate: '偏好语言',
        object: 'Python',
      );
      final extraction = ParsedExtraction.parse(
        '{"memories":[{"kind":"preference",'
        '"content":"用户偏好用 Dart 写客户端",'
        '"subject":"用户","predicate":"偏好语言","object":"Dart",'
        '"action":"supersede"}]}',
      );
      final decision = buildMergeDecision(
        userId: 'u1',
        extraction: extraction,
        existingMemories: <MemoryItem>[existing],
      );
      expect(decision.added, 1);
      expect(decision.superseded, 1);
      expect(decision.toSave, hasLength(2));
      final oldOne =
          decision.toSave.firstWhere((item) => item.id == 'm1');
      expect(oldOne.status, MemoryStatus.superseded);
      expect(oldOne.supersededBy, isNotNull);
      final active =
          decision.toSave.where((item) => item.status == MemoryStatus.active);
      expect(active, hasLength(1));
      expect(active.single.content, contains('Dart'));
      expect(oldOne.supersededBy, active.single.id);
      expect(decision.touched.single.id, active.single.id);
    });

    test('同一批抽取中的重复内容只保留一条', () {
      final extraction = ParsedExtraction.parse(
        '{"memories":[{"content":"用户喜欢喝美式咖啡"},'
        '{"content":"用户喜欢喝美式咖啡"}]}',
      );
      final decision = buildMergeDecision(
        userId: 'u1',
        extraction: extraction,
        existingMemories: const <MemoryItem>[],
      );
      expect(decision.added, 1);
      expect(decision.skipped, 1);
      expect(decision.toSave, hasLength(1));
    });

    test('action=update 但找不到已有记忆时退化为新增', () {
      final extraction = ParsedExtraction.parse(
        '{"memories":[{"content":"用户喜欢喝美式咖啡","action":"update"}]}',
      );
      final decision = buildMergeDecision(
        userId: 'u1',
        extraction: extraction,
        existingMemories: const <MemoryItem>[],
      );
      expect(decision.added, 1);
      expect(decision.updated, 0);
    });
  });
}
