/// 网站图标簇：用域名首字母 + 稳定配色模拟 favicon，离线也能显示。
///
/// 对应 Demo 里搜索结果前的 favicon 叠放（无网络图片依赖，避免国内网络下空白）。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';

class FaviconCluster extends StatelessWidget {
  const FaviconCluster({
    super.key,
    required this.hits,
    this.max = 3,
    this.size = 18,
  });

  final List<SearchHit> hits;
  final int max;
  final double size;

  static const List<Color> _palette = <Color>[
    Color(0xFF3964FE),
    Color(0xFF12A594),
    Color(0xFFF5A623),
    Color(0xFFE5484D),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
  ];

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) return const SizedBox.shrink();
    final hosts = <String>[];
    for (final hit in hits) {
      final host = _hostOf(hit.url);
      if (host.isNotEmpty && !hosts.contains(host)) hosts.add(host);
      if (hosts.length >= max) break;
    }
    if (hosts.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: size + (hosts.length - 1) * (size - 4),
      height: size,
      child: Stack(
        children: <Widget>[
          for (var i = 0; i < hosts.length; i++)
            Positioned(
              left: i * (size - 4),
              child: _Favicon(
                host: hosts[i],
                size: size,
                color: _palette[hosts[i].hashCode.abs() % _palette.length],
              ),
            ),
        ],
      ),
    );
  }

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

class _Favicon extends StatelessWidget {
  const _Favicon({
    required this.host,
    required this.size,
    required this.color,
  });

  final String host;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final letter = host.isEmpty ? '?' : host.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: colors.bgBase, width: 1.5),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}
