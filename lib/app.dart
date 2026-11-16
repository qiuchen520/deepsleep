/// 应用根组件与主框架（响应式：宽屏常驻侧栏，窄屏抽屉）。
library;

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/models/profile_models.dart';
import 'features/chat/chat_view.dart';
import 'features/memory/memory_center_page.dart';
import 'features/settings/settings_page.dart';
import 'features/sidebar/session_sidebar.dart';
import 'state/app_services.dart';

class DeepSleepApp extends StatelessWidget {
  const DeepSleepApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final preference = services.settings.settings.theme;
        return MaterialApp(
          title: 'DeepSleep',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: switch (preference) {
            ThemePreference.light => ThemeMode.light,
            ThemePreference.dark => ThemeMode.dark,
            ThemePreference.system => ThemeMode.system,
          },
          home: RootShell(services: services),
        );
      },
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.services});

  final AppServices services;

  static const double sideBarWidth = 261;
  static const double wideBreakpoint = 860;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(services: widget.services),
      ),
    );
    setState(() {});
  }

  Future<void> _openMemory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryCenterPage(services: widget.services),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= RootShell.wideBreakpoint;

    final chatView = ChatView(
      services: widget.services,
      showSidebarButton: !isWide,
      onOpenSidebar: isWide
          ? null
          : () => _scaffoldKey.currentState?.openDrawer(),
      onOpenSettings: _openSettings,
      onOpenMemory: _openMemory,
    );

    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(
                width: RootShell.sideBarWidth,
                child: SessionSidebar(
                  services: widget.services,
                  onOpenSettings: _openSettings,
                  onOpenMemory: _openMemory,
                ),
              ),
              Expanded(child: chatView),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: RootShell.sideBarWidth + 20,
        backgroundColor: context.colors.bgSidebar,
        child: SafeArea(
          child: SessionSidebar(
            services: widget.services,
            onOpenSettings: _openSettings,
            onOpenMemory: _openMemory,
            onClose: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      body: SafeArea(child: chatView),
    );
  }
}
