/// 全局搜索页：会话标题 / 聊天记录 / 记忆三组结果，关键词高亮。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/global_search_service.dart';
import '../../state/app_services.dart';
import '../memory/memory_center_page.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key, required this.services});

  final AppServices services;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  GlobalSearchResult _result = const GlobalSearchResult();
  bool _loading = false;
  int _requestId = 0;

  String get _query => _controller.text.trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _result = const GlobalSearchResult();
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    try {
      final result = await widget.services.globalSearch.search(query);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _result = const GlobalSearchResult();
        _loading = false;
      });
    }
  }

  Future<void> _openHit(GlobalSearchHit hit) async {
    final navigator = Navigator.of(context);
    final services = widget.services;
    final query = _query;
    if (hit.kind == 'memory') {
      navigator.pop();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MemoryCenterPage(
            services: services,
            initialQuery: query,
          ),
        ),
      );
      return;
    }
    final sessionId = hit.sessionId;
    if (sessionId == null) return;
    final messageId = hit.kind == 'message' ? hit.messageId : null;
    navigator.pop();
    await services.conversations.openConversation(sessionId);
    services.conversations.focusMessage(messageId);
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    iconSize: 22,
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: colors.textSecondary,
                    ),
                  ),
                  Expanded(child: _buildSearchField(context)),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.border),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.colors;
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 48,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 15, color: colors.textPrimary),
        cursorHeight: 17,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.bgHover,
          hintText: '搜索对话、聊天记录与记忆',
          hintStyle: TextStyle(fontSize: 14, color: colors.textTertiary),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: colors.textTertiary,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _controller.clear();
                    _onChanged('');
                    setState(() {});
                  },
                  tooltip: '清除',
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.close_rounded, color: colors.textTertiary),
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding: EdgeInsets.zero,
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) return _buildIntro(context);
    if (_loading) return _buildLoading(context);
    if (_result.isEmpty) return _buildNoResult(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        if (_result.conversations.isNotEmpty) ...<Widget>[
          _buildSectionHeader(
            context,
            '对话',
            Icons.chat_bubble_outline_rounded,
            _result.conversations.length,
          ),
          for (final hit in _result.conversations) _buildHit(context, hit),
        ],
        if (_result.messages.isNotEmpty) ...<Widget>[
          _buildSectionHeader(
            context,
            '聊天记录',
            Icons.article_outlined,
            _result.messages.length,
          ),
          for (final hit in _result.messages) _buildHit(context, hit),
        ],
        if (_result.memories.isNotEmpty) ...<Widget>[
          _buildSectionHeader(
            context,
            '记忆',
            Icons.psychology_outlined,
            _result.memories.length,
          ),
          for (final hit in _result.memories) _buildHit(context, hit),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
    int count,
  ) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: colors.textTertiary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 12, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildHit(BuildContext context, GlobalSearchHit hit) {
    final colors = context.colors;
    final query = _query;
    final icon = switch (hit.kind) {
      'conversation' => Icons.chat_bubble_outline_rounded,
      'memory' => Icons.psychology_outlined,
      _ => Icons.article_outlined,
    };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openHit(hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 17, color: colors.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildHighlighted(
                      context,
                      hit.title,
                      query,
                      baseSize: 14,
                      bold: true,
                    ),
                    const SizedBox(height: 2),
                    _buildHighlighted(
                      context,
                      hit.kind == 'conversation'
                          ? (hit.subtitle.isEmpty ? hit.content : hit.subtitle)
                          : hit.content,
                      query,
                      baseSize: 13,
                      maxLines: 2,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlighted(
    BuildContext context,
    String text,
    String query, {
    required double baseSize,
    int maxLines = 1,
    Color? color,
    bool bold = false,
  }) {
    final colors = context.colors;
    final baseStyle = TextStyle(
      fontSize: baseSize,
      height: 1.45,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color: color ?? colors.textPrimary,
    );
    final spans = _highlightSpans(context, text, query, baseStyle);
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  List<TextSpan> _highlightSpans(
    BuildContext context,
    String text,
    String query,
    TextStyle baseStyle,
  ) {
    if (query.isEmpty) return <TextSpan>[TextSpan(text: text, style: baseStyle)];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) break;
      if (index > start) {
        spans.add(
          TextSpan(text: text.substring(start, index), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: baseStyle.copyWith(
            color: context.colors.brand,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = index + query.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return spans;
  }

  Widget _buildIntro(BuildContext context) {
    final colors = context.colors;
    return _IllustrationState(
      icon: Icons.manage_search_rounded,
      title: '搜索所有内容',
      description: '输入关键词，搜索对话标题、聊天记录与长期记忆。',
      color: colors,
    );
  }

  Widget _buildLoading(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: <Widget>[
        for (var i = 0; i < 6; i++)
          Container(
            height: 52,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colors.bgHover,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      ],
    );
  }

  Widget _buildNoResult(BuildContext context) {
    return _IllustrationState(
      icon: Icons.search_off_rounded,
      title: '没有找到相关内容',
      description: '试试换个关键词，或检查搜索范围。',
      color: context.colors,
    );
  }
}

class _IllustrationState extends StatelessWidget {
  const _IllustrationState({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final AppColors color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: color.brandText),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: color.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
