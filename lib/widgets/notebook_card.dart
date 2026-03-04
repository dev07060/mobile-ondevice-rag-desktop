import 'package:flutter/material.dart';

import 'package:local_gemma_macos/models/notebook_models.dart';

class NotebookCard extends StatelessWidget {
  final NotebookModel notebook;
  final int sourceCount;
  final int chunkCount;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onManageCategories;
  final VoidCallback onDelete;

  const NotebookCard({
    super.key,
    required this.notebook,
    required this.sourceCount,
    required this.chunkCount,
    required this.onOpen,
    required this.onEdit,
    required this.onManageCategories,
    required this.onDelete,
  });

  Color _parseColor(String hex) {
    final normalized = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$normalized', radix: 16) ?? 0xFF334155;
    return Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _parseColor(notebook.colorHex);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(notebook.emoji, style: const TextStyle(fontSize: 20)),
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'categories':
                        onManageCategories();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit Notebook')),
                    PopupMenuItem(
                      value: 'categories',
                      child: Text('Manage Categories'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Notebook'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notebook.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: notebook.categories
                  .map((category) {
                    final isDefault =
                        category.collectionId == notebook.defaultCollectionId;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDefault
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.black.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        isDefault
                            ? 'Default (Upload Target)'
                            : category.title,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
            const Spacer(),
            Text(
              'Sources $sourceCount · Chunks $chunkCount',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
