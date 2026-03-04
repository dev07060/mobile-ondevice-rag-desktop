import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:local_gemma_macos/models/notebook_models.dart';
import 'package:local_gemma_macos/services/notebook_repository.dart';

class _FakeMigrationRagApi implements NotebookMigrationRagApi {
  final List<SourceEntry> _defaultSources;
  final Map<int, String> _sourceDocuments;

  final List<({String collectionId, String content})> addedDocuments = [];
  final List<({String collectionId, int sourceId})> removedSources = [];
  final List<String> rebuiltCollections = [];

  _FakeMigrationRagApi({
    required List<SourceEntry> defaultSources,
    required Map<int, String> sourceDocuments,
  }) : _defaultSources = List<SourceEntry>.from(defaultSources),
       _sourceDocuments = Map<int, String>.from(sourceDocuments);

  @override
  Future<void> addDocument({
    required String content,
    String? metadata,
    String? name,
    required String collectionId,
  }) async {
    addedDocuments.add((collectionId: collectionId, content: content));
  }

  @override
  Future<String?> getSourceDocument(int sourceId) async {
    return _sourceDocuments[sourceId];
  }

  @override
  Future<List<SourceEntry>> listSources({required String collectionId}) async {
    if (collectionId != SourceRagService.defaultCollectionId) {
      return const [];
    }
    return List<SourceEntry>.from(_defaultSources);
  }

  @override
  Future<void> rebuildIndex({
    required String collectionId,
    bool force = true,
  }) async {
    rebuiltCollections.add(collectionId);
  }

  @override
  Future<void> removeSource({
    required int sourceId,
    required String collectionId,
  }) async {
    removedSources.add((collectionId: collectionId, sourceId: sourceId));
    _defaultSources.removeWhere((source) => source.id.toInt() == sourceId);
  }
}

SourceEntry _source({required int id}) {
  return SourceEntry(
    id: id,
    name: 'source_$id',
    createdAt: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    metadata: '{"k":"v"}',
    status: 'completed',
    collectionId: SourceRagService.defaultCollectionId,
  );
}

void main() {
  group('NotebookRepository migration', () {
    test(
      'moves __default__ data into target notebook collection and cleans up',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'nb_migration_test',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final repo = NotebookRepository(
          documentsDirProvider: () async => tempDir,
          clock: () => DateTime.utc(2026, 2, 1),
        );

        final initialStore = await repo.loadStore();
        final targetCollectionId =
            initialStore.notebooks.first.defaultCollectionId;

        final api = _FakeMigrationRagApi(
          defaultSources: [_source(id: 1), _source(id: 2)],
          sourceDocuments: {1: 'alpha content', 2: 'beta content'},
        );

        final migratedStore = await repo.runInitialMigrationWithApi(api);

        expect(migratedStore.migration.completed, isTrue);
        expect(api.addedDocuments.length, 2);
        expect(
          api.addedDocuments.every(
            (entry) => entry.collectionId == targetCollectionId,
          ),
          isTrue,
        );
        expect(api.removedSources.length, 2);
        expect(
          api.rebuiltCollections.contains(SourceRagService.defaultCollectionId),
          isTrue,
        );
        expect(api.rebuiltCollections.contains(targetCollectionId), isTrue);
        expect(
          (await api.listSources(
            collectionId: SourceRagService.defaultCollectionId,
          )).isEmpty,
          isTrue,
        );
      },
    );

    test('resumes from cursor during copying phase', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nb_migration_resume',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final repo = NotebookRepository(
        documentsDirProvider: () async => tempDir,
        clock: () => DateTime.utc(2026, 2, 1),
      );

      final baseStore = await repo.loadStore();
      final notebook = baseStore.notebooks.first;
      final resumedStore = baseStore.copyWith(
        migration: NotebookMigrationState(
          completed: false,
          phase: 'copying',
          cursor: 1,
          targetNotebookId: notebook.id,
        ),
      );
      await repo.saveStore(resumedStore);

      final api = _FakeMigrationRagApi(
        defaultSources: [_source(id: 1), _source(id: 2)],
        sourceDocuments: {1: 'alpha content', 2: 'beta content'},
      );

      final migratedStore = await repo.runInitialMigrationWithApi(api);

      expect(migratedStore.migration.completed, isTrue);
      expect(api.addedDocuments.length, 1);
      expect(api.addedDocuments.first.content, 'beta content');
      expect(api.removedSources.length, 2);
    });
  });
}
