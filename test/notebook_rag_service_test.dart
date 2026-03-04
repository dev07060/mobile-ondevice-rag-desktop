import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:local_gemma_macos/services/notebook_rag_service.dart';

class _FakeRagEngine extends Fake implements RagEngine {}

RagSearchResult _makeResult(List<ChunkSearchResult> chunks) {
  return RagSearchResult(
    chunks: chunks,
    context: AssembledContext(
      text: chunks.map((c) => c.content).join('\n'),
      includedChunks: chunks,
      estimatedTokens: 10,
      remainingBudget: 0,
    ),
  );
}

ChunkSearchResult _chunk({
  required int chunkId,
  required int sourceId,
  required int chunkIndex,
  required String content,
  required double similarity,
}) {
  return ChunkSearchResult(
    chunkId: chunkId,
    sourceId: sourceId,
    chunkIndex: chunkIndex,
    content: content,
    chunkType: 'general',
    similarity: similarity,
    metadata: null,
  );
}

void main() {
  group('NotebookRagService', () {
    test(
      'searchMerged deduplicates by chunkId and sorts by similarity',
      () async {
        final service = NotebookRagService(
          ragEngine: _FakeRagEngine(),
          searchExecutor:
              ({
                required collectionId,
                required query,
                required topK,
                required tokenBudget,
                required strategy,
                required adjacentChunks,
                required singleSourceMode,
                required useHybridWithContext,
              }) async {
                if (collectionId == 'a') {
                  return _makeResult([
                    _chunk(
                      chunkId: 10,
                      sourceId: 1,
                      chunkIndex: 0,
                      content: 'A-1',
                      similarity: 0.90,
                    ),
                    _chunk(
                      chunkId: 11,
                      sourceId: 1,
                      chunkIndex: 1,
                      content: 'A-2',
                      similarity: 0.60,
                    ),
                  ]);
                }

                return _makeResult([
                  _chunk(
                    chunkId: 10,
                    sourceId: 2,
                    chunkIndex: 0,
                    content: 'B-dup',
                    similarity: 0.70,
                  ),
                  _chunk(
                    chunkId: 12,
                    sourceId: 2,
                    chunkIndex: 1,
                    content: 'B-1',
                    similarity: 0.80,
                  ),
                ]);
              },
        );

        final result = await service.searchMerged(
          query: 'test',
          collectionIds: const ['a', 'b'],
          topK: 3,
        );

        expect(result.chunks.length, 3);
        expect(result.chunks[0].chunkId, 10);
        expect(result.chunks[1].chunkId, 12);
        expect(result.chunks[2].chunkId, 11);
        expect(result.failedCollections, isEmpty);
        expect(result.contextText.contains('[Collection: a]'), isTrue);
        expect(result.contextText.contains('[Collection: b]'), isTrue);
      },
    );

    test(
      'searchMerged allows partial success when one collection fails',
      () async {
        final service = NotebookRagService(
          ragEngine: _FakeRagEngine(),
          searchExecutor:
              ({
                required collectionId,
                required query,
                required topK,
                required tokenBudget,
                required strategy,
                required adjacentChunks,
                required singleSourceMode,
                required useHybridWithContext,
              }) async {
                if (collectionId == 'bad') {
                  throw Exception('collection error');
                }

                return _makeResult([
                  _chunk(
                    chunkId: 20,
                    sourceId: 3,
                    chunkIndex: 0,
                    content: 'good',
                    similarity: 0.88,
                  ),
                ]);
              },
        );

        final result = await service.searchMerged(
          query: 'test',
          collectionIds: const ['good', 'bad'],
          topK: 5,
        );

        expect(result.chunks.length, 1);
        expect(result.failedCollections, const ['bad']);
        expect(result.chunkCountByCollection['good'], 1);
        expect(result.chunkCountByCollection['bad'], 0);
      },
    );
  });
}
