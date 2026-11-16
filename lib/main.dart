/// 入口：初始化服务（数据库 / 设置 / 记忆引擎）后启动 App。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'state/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式：隐藏系统状态栏与导航栏（从屏幕边缘上滑可临时唤出）。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  // 发布版也把构建异常显示出来，避免只看到灰块无法排查。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _VisibleErrorWidget(
      message: details.exceptionAsString(),
      stack: details.stack?.toString() ?? '',
    );
  };
  runApp(const BootstrapApp());
}

/// 发布版错误占位：显示异常文本，便于用户截图反馈。
class _VisibleErrorWidget extends StatelessWidget {
  const _VisibleErrorWidget({required this.message, required this.stack});

  final String message;
  final String stack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7F7),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '界面渲染出错',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE5484D),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF5E6572),
              ),
            ),
            if (stack.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                stack,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.4,
                  color: Color(0xFF9AA0AA),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<AppServices> _future;

  @override
  void initState() {
    super.initState();
    _future = AppServices.init();
  }

  void _retry() {
    setState(() {
      _future = AppServices.init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: _BootstrapErrorScreen(
              error: snapshot.error,
              onRetry: _retry,
            ),
          );
        }
        final services = snapshot.data;
        if (services == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return AppScope(
          services: services,
          child: DeepSleepApp(services: services),
        );
      },
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: colors.danger),
              const SizedBox(height: 12),
              Text(
                '初始化失败',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
