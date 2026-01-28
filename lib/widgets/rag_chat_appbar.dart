/// Custom AppBar widget for RAG Chat screen.
/// Contains graph toggle, debug toggle, and settings menu.

import 'package:flutter/material.dart';

/// Actions that can be triggered from the AppBar menu
enum RagChatMenuAction { newChat, compression0, compression1, compression2 }

/// AppBar for RAG Chat screen with settings and toggles
class RagChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showGraphPanel;
  final bool showDebugInfo;
  final int compressionLevel;
  final VoidCallback onToggleGraph;
  final VoidCallback onToggleDebug;
  final void Function(RagChatMenuAction action) onMenuAction;

  const RagChatAppBar({
    super.key,
    required this.showGraphPanel,
    required this.showDebugInfo,
    required this.compressionLevel,
    required this.onToggleGraph,
    required this.onToggleDebug,
    required this.onMenuAction,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('RAG Chat', style: TextStyle(color: Colors.white)),
      centerTitle: true,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        // Graph panel toggle
        IconButton(
          icon: Icon(
            showGraphPanel ? Icons.hub : Icons.hub_outlined,
            color: showGraphPanel ? Colors.purple : Colors.grey,
          ),
          tooltip: 'Toggle Knowledge Graph',
          onPressed: onToggleGraph,
        ),
        // Debug info toggle
        IconButton(
          icon: Icon(
            showDebugInfo ? Icons.bug_report : Icons.bug_report_outlined,
            color: Colors.grey,
          ),
          tooltip: 'Toggle debug info',
          onPressed: onToggleDebug,
        ),
        // Settings menu
        _buildSettingsMenu(context),
      ],
    );
  }

  Widget _buildSettingsMenu(BuildContext context) {
    return PopupMenuButton<RagChatMenuAction>(
      onSelected: onMenuAction,
      itemBuilder: (context) => [
        // New Chat
        const PopupMenuItem(
          value: RagChatMenuAction.newChat,
          child: ListTile(
            leading: Icon(Icons.refresh),
            title: Text('New Chat'),
            subtitle: Text('Clear chat history'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),

        // Compression section
        PopupMenuItem(
          enabled: false,
          child: Text(
            'Compression Level',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ),
        PopupMenuItem(
          value: RagChatMenuAction.compression0,
          child: ListTile(
            leading: Icon(
              compressionLevel == 0
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: compressionLevel == 0
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: const Text('Minimal'),
            subtitle: const Text('Max context'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: RagChatMenuAction.compression1,
          child: ListTile(
            leading: Icon(
              compressionLevel == 1
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: compressionLevel == 1
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: const Text('Balanced'),
            subtitle: const Text('Default'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: RagChatMenuAction.compression2,
          child: ListTile(
            leading: Icon(
              compressionLevel == 2
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: compressionLevel == 2
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: const Text('Aggressive'),
            subtitle: const Text('Less context'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
