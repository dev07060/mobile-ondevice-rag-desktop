/// Home screen app bar with settings menu.
/// Provides menu actions for clearing documents, changing models, refreshing, and restarting Ollama.

import 'package:flutter/material.dart';

/// App bar for the home screen with settings menu
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Function(String) onMenuAction;

  const HomeAppBar({super.key, required this.onMenuAction});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('🤖 RAG + Ollama'),
      centerTitle: true,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.settings),
          onSelected: onMenuAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'clear_documents',
              child: ListTile(
                leading: Icon(Icons.delete_sweep),
                title: Text('Clear Documents'),
                subtitle: Text('Reset RAG database'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'change_model',
              child: ListTile(
                leading: Icon(Icons.swap_horiz),
                title: Text('Change Model'),
                subtitle: Text('Select different model'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Refresh Status'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'restart_ollama',
              child: ListTile(
                leading: Icon(Icons.restart_alt),
                title: Text('Restart Ollama'),
                subtitle: Text('Restart Ollama server'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
