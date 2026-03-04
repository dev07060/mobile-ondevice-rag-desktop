import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_gemma_macos/models/notebook_models.dart';
import 'package:local_gemma_macos/services/notebook_repository.dart';

void main() {
  group('NotebookRepository', () {
    test('save/load round trip preserves notebook fields', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nb_repo_roundtrip',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final repo = NotebookRepository(
        documentsDirProvider: () async => tempDir,
        clock: () => DateTime.utc(2026, 1, 1, 0, 0, 0),
      );

      final store = NotebookStoreModel(
        version: NotebookStoreModel.currentVersion,
        migration: NotebookMigrationState.initial,
        notebooks: [
          NotebookModel(
            id: 'nbk_1',
            title: 'Research',
            emoji: '📘',
            colorHex: '#1F2937',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 2),
            defaultCollectionId: 'col_main',
            categories: [
              NotebookCategoryModel(
                id: 'cat_main',
                title: 'Main',
                collectionId: 'col_main',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              NotebookCategoryModel(
                id: 'cat_sub',
                title: 'Sub',
                collectionId: 'col_sub',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
        ],
      );

      await repo.saveStore(store);
      final loaded = await repo.loadStore();

      expect(loaded.version, store.version);
      expect(loaded.notebooks.length, 1);
      expect(loaded.notebooks.first.id, 'nbk_1');
      expect(loaded.notebooks.first.defaultCollectionId, 'col_main');
      expect(loaded.notebooks.first.categories.length, 2);
      expect(loaded.notebooks.first.categories[1].collectionId, 'col_sub');
    });

    test(
      'validateOwnership throws when a collection is shared across notebooks',
      () {
        final store = NotebookStoreModel(
          version: NotebookStoreModel.currentVersion,
          migration: NotebookMigrationState.initial,
          notebooks: [
            NotebookModel(
              id: 'nbk_a',
              title: 'A',
              emoji: '📓',
              colorHex: '#334155',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
              defaultCollectionId: 'shared_collection',
              categories: [
                NotebookCategoryModel(
                  id: 'cat_a',
                  title: 'A',
                  collectionId: 'shared_collection',
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ],
            ),
            NotebookModel(
              id: 'nbk_b',
              title: 'B',
              emoji: '📓',
              colorHex: '#334155',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
              defaultCollectionId: 'shared_collection',
              categories: [
                NotebookCategoryModel(
                  id: 'cat_b',
                  title: 'B',
                  collectionId: 'shared_collection',
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ],
            ),
          ],
        );

        expect(
          () => NotebookRepository.validateOwnership(store),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
