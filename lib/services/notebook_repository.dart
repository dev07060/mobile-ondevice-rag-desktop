import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';

import 'package:local_gemma_macos/models/notebook_models.dart';

abstract class NotebookMigrationRagApi {
  Future<List<SourceEntry>> listSources({required String collectionId});
  Future<String?> getSourceDocument(int sourceId);
  Future<void> addDocument({
    required String content,
    String? metadata,
    String? name,
    required String collectionId,
  });
  Future<void> removeSource({
    required int sourceId,
    required String collectionId,
  });
  Future<void> rebuildIndex({required String collectionId, bool force = true});
}

class _EngineMigrationRagApi implements NotebookMigrationRagApi {
  final RagEngine _engine;

  _EngineMigrationRagApi(this._engine);

  @override
  Future<List<SourceEntry>> listSources({required String collectionId}) {
    return _engine.listSources(collectionId: collectionId);
  }

  @override
  Future<String?> getSourceDocument(int sourceId) {
    return _engine.getSourceDocument(sourceId);
  }

  @override
  Future<void> addDocument({
    required String content,
    String? metadata,
    String? name,
    required String collectionId,
  }) {
    return _engine.addDocument(
      content,
      metadata: metadata,
      name: name,
      collectionId: collectionId,
    );
  }

  @override
  Future<void> removeSource({
    required int sourceId,
    required String collectionId,
  }) {
    return _engine.removeSource(sourceId, collectionId: collectionId);
  }

  @override
  Future<void> rebuildIndex({required String collectionId, bool force = true}) {
    return _engine.rebuildIndex(force: force, collectionId: collectionId);
  }
}

class NotebookRepository {
  static const String fileName = 'notebooks_v1.json';

  final Future<Directory> Function() _documentsDirProvider;
  final DateTime Function() _clock;
  final Random _random;

  NotebookRepository({
    Future<Directory> Function()? documentsDirProvider,
    DateTime Function()? clock,
    Random? random,
  }) : _documentsDirProvider =
           documentsDirProvider ?? getApplicationDocumentsDirectory,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  Future<File> get _storeFile async {
    final dir = await _documentsDirProvider();
    return File('${dir.path}/$fileName');
  }

  String _newId(String prefix) {
    final ts = _clock().microsecondsSinceEpoch;
    final salt = _random.nextInt(0x7fffffff).toRadixString(16);
    return '${prefix}_${ts}_$salt';
  }

  NotebookCategoryModel _newCategory({
    required String title,
    required String collectionId,
  }) {
    return NotebookCategoryModel(
      id: _newId('cat'),
      title: title,
      collectionId: collectionId,
      createdAt: _clock(),
    );
  }

  NotebookModel _newDefaultNotebook() {
    final now = _clock();
    final collectionId = _newId('nbk_main');
    final category = NotebookCategoryModel(
      id: _newId('cat'),
      title: 'Default',
      collectionId: collectionId,
      createdAt: now,
    );
    return NotebookModel(
      id: _newId('nbk'),
      title: 'Default Notebook',
      emoji: '📓',
      colorHex: '#334155',
      createdAt: now,
      updatedAt: now,
      defaultCollectionId: collectionId,
      categories: [category],
    );
  }

  NotebookStoreModel _newDefaultStore() {
    return NotebookStoreModel(
      version: NotebookStoreModel.currentVersion,
      notebooks: [_newDefaultNotebook()],
      migration: NotebookMigrationState.initial,
    );
  }

  static void validateOwnership(NotebookStoreModel store) {
    final ownerByCollection = <String, String>{};

    for (final notebook in store.notebooks) {
      if (notebook.categories.isEmpty) {
        throw StateError(
          'Notebook(${notebook.id}) must have at least 1 category.',
        );
      }

      var foundDefault = false;
      for (final category in notebook.categories) {
        if (category.collectionId.trim().isEmpty) {
          throw StateError(
            'Notebook(${notebook.id}) has an empty collectionId category.',
          );
        }

        final existingOwner = ownerByCollection[category.collectionId];
        if (existingOwner != null && existingOwner != notebook.id) {
          throw StateError(
            'Collection(${category.collectionId}) is already owned by notebook($existingOwner).',
          );
        }
        ownerByCollection[category.collectionId] = notebook.id;

        if (category.collectionId == notebook.defaultCollectionId) {
          foundDefault = true;
        }
      }

      if (!foundDefault) {
        throw StateError(
          'Notebook(${notebook.id}) defaultCollectionId does not exist in categories.',
        );
      }
    }
  }

  Future<NotebookStoreModel> loadStore() async {
    final file = await _storeFile;

    if (!await file.exists()) {
      final store = _newDefaultStore();
      await saveStore(store);
      return store;
    }

    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) {
        final store = _newDefaultStore();
        await saveStore(store);
        return store;
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Notebook store must be a JSON object.');
      }

      var store = NotebookStoreModel.fromJson(decoded);
      if (store.notebooks.isEmpty) {
        store = store.copyWith(notebooks: [_newDefaultNotebook()]);
      }

      validateOwnership(store);
      return store;
    } catch (e) {
      debugPrint('⚠️ Notebook store load failed, recreating default store: $e');
      final store = _newDefaultStore();
      await saveStore(store);
      return store;
    }
  }

  Future<void> saveStore(NotebookStoreModel store) async {
    validateOwnership(store);

    final file = await _storeFile;
    final tmpFile = File('${file.path}.tmp');

    await tmpFile.writeAsString(store.toPrettyJson(), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }

  Future<NotebookStoreModel> resetToDefaultStore() async {
    final store = _newDefaultStore();
    await saveStore(store);
    return store;
  }

  Future<NotebookStoreModel> createNotebook({
    required String title,
    String emoji = '📓',
    String colorHex = '#334155',
  }) async {
    final store = await loadStore();
    final now = _clock();

    final collectionId = _newId('nbk_main');
    final category = NotebookCategoryModel(
      id: _newId('cat'),
      title: 'Default',
      collectionId: collectionId,
      createdAt: now,
    );

    final notebook = NotebookModel(
      id: _newId('nbk'),
      title: title.trim().isEmpty ? 'Untitled Notebook' : title.trim(),
      emoji: emoji,
      colorHex: colorHex,
      createdAt: now,
      updatedAt: now,
      defaultCollectionId: collectionId,
      categories: [category],
    );

    final updated = store.copyWith(notebooks: [...store.notebooks, notebook]);
    await saveStore(updated);
    return updated;
  }

  Future<NotebookStoreModel> updateNotebookMeta({
    required String notebookId,
    String? title,
    String? emoji,
    String? colorHex,
  }) async {
    final store = await loadStore();
    final notebooks = store.notebooks.map((notebook) {
      if (notebook.id != notebookId) return notebook;
      return notebook.copyWith(
        title: title ?? notebook.title,
        emoji: emoji ?? notebook.emoji,
        colorHex: colorHex ?? notebook.colorHex,
        updatedAt: _clock(),
      );
    }).toList();

    final updated = store.copyWith(notebooks: notebooks);
    await saveStore(updated);
    return updated;
  }

  Future<NotebookStoreModel> addCategory({
    required String notebookId,
    required String title,
    String? explicitCollectionId,
  }) async {
    final store = await loadStore();

    final collectionId = explicitCollectionId?.trim().isNotEmpty == true
        ? explicitCollectionId!.trim()
        : _newId('col');

    final notebooks = store.notebooks.map((notebook) {
      if (notebook.id != notebookId) return notebook;

      final exists = notebook.categories.any(
        (category) => category.collectionId == collectionId,
      );
      if (exists) {
        throw StateError('Collection($collectionId) is already linked.');
      }

      final newCategory = _newCategory(
        title: title.trim().isEmpty ? 'Category' : title.trim(),
        collectionId: collectionId,
      );

      return notebook.copyWith(
        categories: [...notebook.categories, newCategory],
        updatedAt: _clock(),
      );
    }).toList();

    final updated = store.copyWith(notebooks: notebooks);
    await saveStore(updated);
    return updated;
  }

  Future<NotebookStoreModel> removeCategory({
    required String notebookId,
    required String categoryId,
  }) async {
    final store = await loadStore();

    final notebooks = store.notebooks.map((notebook) {
      if (notebook.id != notebookId) return notebook;

      final existing = notebook.findCategory(categoryId);
      if (existing == null) {
        throw StateError('Category($categoryId) does not exist.');
      }

      final remaining = notebook.categories
          .where((category) => category.id != categoryId)
          .toList();

      if (remaining.isEmpty) {
        throw StateError('Notebook must keep at least one category.');
      }

      String nextDefault = notebook.defaultCollectionId;
      if (existing.collectionId == notebook.defaultCollectionId) {
        nextDefault = remaining.first.collectionId;
      }

      return notebook.copyWith(
        categories: remaining,
        defaultCollectionId: nextDefault,
        updatedAt: _clock(),
      );
    }).toList();

    final updated = store.copyWith(notebooks: notebooks);
    await saveStore(updated);
    return updated;
  }

  Future<NotebookStoreModel> setDefaultCategory({
    required String notebookId,
    required String categoryId,
  }) async {
    final store = await loadStore();

    final notebooks = store.notebooks.map((notebook) {
      if (notebook.id != notebookId) return notebook;

      final category = notebook.findCategory(categoryId);
      if (category == null) {
        throw StateError('Category($categoryId) does not exist.');
      }

      return notebook.copyWith(
        defaultCollectionId: category.collectionId,
        updatedAt: _clock(),
      );
    }).toList();

    final updated = store.copyWith(notebooks: notebooks);
    await saveStore(updated);
    return updated;
  }

  Future<NotebookStoreModel> deleteNotebook(String notebookId) async {
    final store = await loadStore();
    final notebooks = store.notebooks
        .where((notebook) => notebook.id != notebookId)
        .toList();

    final updated = notebooks.isEmpty
        ? store.copyWith(notebooks: [_newDefaultNotebook()])
        : store.copyWith(notebooks: notebooks);

    await saveStore(updated);
    return updated;
  }

  Future<NotebookStoreModel> runInitialMigrationIfNeeded(
    RagEngine ragEngine,
  ) async {
    return runInitialMigrationWithApi(_EngineMigrationRagApi(ragEngine));
  }

  @visibleForTesting
  Future<NotebookStoreModel> runInitialMigrationWithApi(
    NotebookMigrationRagApi ragApi,
  ) async {
    var store = await loadStore();
    if (store.migration.completed) {
      return store;
    }

    if (store.notebooks.isEmpty) {
      store = store.copyWith(notebooks: [_newDefaultNotebook()]);
      await saveStore(store);
    }

    var migration = store.migration;
    var targetNotebookId = migration.targetNotebookId;

    if (targetNotebookId == null ||
        store.findNotebook(targetNotebookId) == null) {
      targetNotebookId = store.notebooks.first.id;
      migration = migration.copyWith(targetNotebookId: targetNotebookId);
      store = store.copyWith(migration: migration);
      await saveStore(store);
    }

    var targetNotebook = store.findNotebook(targetNotebookId);
    if (targetNotebook == null) {
      throw StateError('Migration target notebook not found.');
    }

    if (targetNotebook.categories.isEmpty) {
      final category = _newCategory(
        title: 'Default',
        collectionId: _newId('col'),
      );
      final notebooks = store.notebooks.map((notebook) {
        if (notebook.id != targetNotebookId) return notebook;
        return notebook.copyWith(
          categories: [category],
          defaultCollectionId: category.collectionId,
          updatedAt: _clock(),
        );
      }).toList();
      store = store.copyWith(notebooks: notebooks);
      await saveStore(store);
      targetNotebook = store.findNotebook(targetNotebookId)!;
    }

    final targetCollectionId = targetNotebook.defaultCollectionId;

    if (migration.phase == 'copying') {
      final defaultSources = await _safeListSources(
        ragApi,
        collectionId: SourceRagService.defaultCollectionId,
      );

      for (var i = migration.cursor; i < defaultSources.length; i++) {
        final source = defaultSources[i];
        final sourceId = source.id.toInt();
        final sourceDocument = await ragApi.getSourceDocument(sourceId);
        final content = sourceDocument?.trim() ?? '';

        if (content.isNotEmpty) {
          await ragApi.addDocument(
            content: content,
            name: source.name,
            metadata: source.metadata,
            collectionId: targetCollectionId,
          );
        }

        migration = migration.copyWith(cursor: i + 1);
        store = store.copyWith(migration: migration);
        await saveStore(store);
      }

      migration = migration.copyWith(phase: 'cleaning', cursor: 0);
      store = store.copyWith(migration: migration);
      await saveStore(store);
    }

    if (migration.phase == 'cleaning') {
      final defaultSources = await _safeListSources(
        ragApi,
        collectionId: SourceRagService.defaultCollectionId,
      );

      for (var i = migration.cursor; i < defaultSources.length; i++) {
        final source = defaultSources[i];
        await ragApi.removeSource(
          sourceId: source.id.toInt(),
          collectionId: SourceRagService.defaultCollectionId,
        );

        migration = migration.copyWith(cursor: i + 1);
        store = store.copyWith(migration: migration);
        await saveStore(store);
      }

      if (defaultSources.isNotEmpty) {
        await _safeRebuildIndex(
          ragApi,
          collectionId: SourceRagService.defaultCollectionId,
        );
      }
      await _safeRebuildIndex(ragApi, collectionId: targetCollectionId);

      migration = migration.copyWith(
        completed: true,
        phase: 'done',
        cursor: 0,
        clearTargetNotebookId: true,
      );
      store = store.copyWith(migration: migration);
      await saveStore(store);
    }

    return store;
  }

  Future<List<SourceEntry>> _safeListSources(
    NotebookMigrationRagApi ragApi, {
    required String collectionId,
  }) async {
    try {
      return await ragApi.listSources(collectionId: collectionId);
    } catch (e) {
      debugPrint('⚠️ listSources failed for $collectionId: $e');
      return const [];
    }
  }

  Future<void> _safeRebuildIndex(
    NotebookMigrationRagApi ragApi, {
    required String collectionId,
  }) async {
    try {
      await ragApi.rebuildIndex(force: true, collectionId: collectionId);
    } catch (e) {
      debugPrint('⚠️ rebuildIndex failed for $collectionId: $e');
    }
  }
}
