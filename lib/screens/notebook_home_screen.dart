import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

import 'package:local_gemma_macos/models/notebook_models.dart';
import 'package:local_gemma_macos/services/notebook_chat_session_store.dart';
import 'package:local_gemma_macos/services/notebook_repository.dart';
import 'package:local_gemma_macos/widgets/notebook_card.dart';
import 'package:local_gemma_macos/widgets/notebook_editor_dialog.dart';
import 'package:local_gemma_macos/screens/rag_chat_screen.dart';

class NotebookHomeScreen extends StatefulWidget {
  final String? modelName;
  final bool mockLlm;
  final NotebookChatSessionStore sessionStore;

  const NotebookHomeScreen({
    super.key,
    required this.modelName,
    required this.sessionStore,
    this.mockLlm = false,
  });

  @override
  State<NotebookHomeScreen> createState() => _NotebookHomeScreenState();
}

class _NotebookHomeScreenState extends State<NotebookHomeScreen> {
  final NotebookRepository _repository = NotebookRepository();
  NotebookStoreModel? _store;
  bool _isLoading = true;
  String? _error;

  final Map<String, ({int sources, int chunks})> _statsByNotebook =
      <String, ({int sources, int chunks})>{};

  RagEngine get _ragEngine => MobileRag.instance.engine;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final migrated = await _repository.runInitialMigrationIfNeeded(
        _ragEngine,
      );
      final stats = <String, ({int sources, int chunks})>{};

      for (final notebook in migrated.notebooks) {
        final collectionIds = notebook.categories
            .map((category) => category.collectionId)
            .toSet();

        var totalSources = 0;
        var totalChunks = 0;
        for (final collectionId in collectionIds) {
          try {
            final stat = await _ragEngine.getStats(collectionId: collectionId);
            totalSources += stat.sourceCount.toInt();
            totalChunks += stat.chunkCount.toInt();
          } catch (e) {
            debugPrint('⚠️ Failed to load stats for $collectionId: $e');
          }
        }
        stats[notebook.id] = (sources: totalSources, chunks: totalChunks);
      }

      if (!mounted) return;
      setState(() {
        _store = migrated;
        _statsByNotebook
          ..clear()
          ..addAll(stats);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createNotebook() async {
    final result = await showNotebookEditorDialog(
      context: context,
      title: 'Create Notebook',
      confirmLabel: 'Create',
      initialTitle: 'Untitled Notebook',
    );
    if (result == null) return;

    await _repository.createNotebook(
      title: result.title,
      emoji: result.emoji,
      colorHex: result.colorHex,
    );
    await _loadStore();
  }

  Future<void> _editNotebook(NotebookModel notebook) async {
    final result = await showNotebookEditorDialog(
      context: context,
      title: 'Edit Notebook',
      confirmLabel: 'Save',
      initialTitle: notebook.title,
      initialEmoji: notebook.emoji,
      initialColorHex: notebook.colorHex,
    );
    if (result == null) return;

    await _repository.updateNotebookMeta(
      notebookId: notebook.id,
      title: result.title,
      emoji: result.emoji,
      colorHex: result.colorHex,
    );

    await _loadStore();
  }

  Future<void> _deleteCollectionData(String collectionId) async {
    try {
      final sources = await _ragEngine.listSources(collectionId: collectionId);
      for (final source in sources) {
        await _ragEngine.removeSource(
          source.id.toInt(),
          collectionId: collectionId,
        );
      }
      if (sources.isNotEmpty) {
        await _ragEngine.rebuildIndex(force: true, collectionId: collectionId);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to delete data in $collectionId: $e');
    }
  }

  Future<void> _deleteNotebook(NotebookModel notebook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notebook?'),
        content: Text(
          'This will delete notebook metadata and all data in ${notebook.categories.length} owned collections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    for (final category in notebook.categories) {
      await _deleteCollectionData(category.collectionId);
    }

    await _repository.deleteNotebook(notebook.id);
    widget.sessionStore.clearNotebook(notebook.id);
    await _loadStore();
  }

  Future<void> _showCategoryDialog(NotebookModel notebook) async {
    final titleController = TextEditingController();
    final collectionController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final currentStore = _store;
              final currentNotebook = currentStore?.findNotebook(notebook.id);
              final categories =
                  currentNotebook?.categories ?? notebook.categories;
              final defaultCollectionId =
                  currentNotebook?.defaultCollectionId ??
                  notebook.defaultCollectionId;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manage Categories',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ...categories.map((category) {
                    final isDefault =
                        category.collectionId == defaultCollectionId;
                    return ListTile(
                      dense: true,
                      title: Text(_displayCategoryLabel(category, notebook)),
                      subtitle: Text(category.collectionId),
                      leading: Icon(
                        isDefault
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isDefault
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onTap: () async {
                        await _repository.setDefaultCategory(
                          notebookId: notebook.id,
                          categoryId: category.id,
                        );
                        await _loadStore();
                        setSheetState(() {});
                      },
                      trailing: IconButton(
                        onPressed: categories.length <= 1
                            ? null
                            : () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Remove category?'),
                                    content: Text(
                                      'Collection ${category.collectionId} data will be deleted immediately.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;

                                await _deleteCollectionData(
                                  category.collectionId,
                                );
                                await _repository.removeCategory(
                                  notebookId: notebook.id,
                                  categoryId: category.id,
                                );
                                await _loadStore();
                                setSheetState(() {});
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Category title',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: collectionController,
                    decoration: const InputDecoration(
                      labelText: 'Collection ID (optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) return;

                          await _repository.addCategory(
                            notebookId: notebook.id,
                            title: title,
                            explicitCollectionId: collectionController.text
                                .trim(),
                          );
                          titleController.clear();
                          collectionController.clear();
                          await _loadStore();
                          setSheetState(() {});
                        },
                        child: const Text('Add Category'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    titleController.dispose();
    collectionController.dispose();
  }

  void _openNotebook(NotebookModel notebook) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RagChatScreen(
          notebook: notebook,
          modelName: widget.modelName,
          mockLlm: widget.mockLlm,
          sessionStore: widget.sessionStore,
        ),
      ),
    ).then((_) => _loadStore());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadStore, child: const Text('Retry')),
          ],
        ),
      );
    }

    final notebooks = _store?.notebooks ?? const <NotebookModel>[];

    return Container(
      color: const Color(0xFF0F1115),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Notebooks',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadStore,
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                ),
                FilledButton.icon(
                  onPressed: _createNotebook,
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final maxCrossAxisExtent = width >= 1280
                      ? 360.0
                      : width >= 840
                      ? 330.0
                      : width;

                  return GridView.builder(
                    itemCount: notebooks.length,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxCrossAxisExtent,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 210,
                    ),
                    itemBuilder: (context, index) {
                      final notebook = notebooks[index];
                      final stats =
                          _statsByNotebook[notebook.id] ??
                          (sources: 0, chunks: 0);

                      return NotebookCard(
                        notebook: notebook,
                        sourceCount: stats.sources,
                        chunkCount: stats.chunks,
                        onOpen: () => _openNotebook(notebook),
                        onEdit: () => _editNotebook(notebook),
                        onManageCategories: () => _showCategoryDialog(notebook),
                        onDelete: () => _deleteNotebook(notebook),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayCategoryLabel(
    NotebookCategoryModel category,
    NotebookModel notebook,
  ) {
    if (category.collectionId == notebook.defaultCollectionId) {
      return 'Default (Upload Target)';
    }
    if (category.title.trim().toLowerCase() == 'main') {
      return 'Default';
    }
    return category.title;
  }
}
