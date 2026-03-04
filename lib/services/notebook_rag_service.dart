import 'package:mobile_rag_engine/mobile_rag_engine.dart';

class NotebookSearchResult {
  final List<ChunkSearchResult> chunks;
  final String contextText;
  final int estimatedTokens;
  final Map<String, int> chunkCountByCollection;
  final List<String> failedCollections;

  const NotebookSearchResult({
    required this.chunks,
    required this.contextText,
    required this.estimatedTokens,
    required this.chunkCountByCollection,
    required this.failedCollections,
  });

  bool get hasContext => chunks.isNotEmpty && contextText.trim().isNotEmpty;
}

typedef CollectionSearchExecutor =
    Future<RagSearchResult> Function({
      required String collectionId,
      required String query,
      required int topK,
      required int tokenBudget,
      required ContextStrategy strategy,
      required int adjacentChunks,
      required bool singleSourceMode,
      required bool useHybridWithContext,
    });

class NotebookRagService {
  final RagEngine ragEngine;
  final CollectionSearchExecutor _searchExecutor;

  NotebookRagService({
    required this.ragEngine,
    CollectionSearchExecutor? searchExecutor,
  }) : _searchExecutor = searchExecutor ?? _defaultSearchExecutor(ragEngine);

  static CollectionSearchExecutor _defaultSearchExecutor(RagEngine ragEngine) {
    return ({
      required String collectionId,
      required String query,
      required int topK,
      required int tokenBudget,
      required ContextStrategy strategy,
      required int adjacentChunks,
      required bool singleSourceMode,
      required bool useHybridWithContext,
    }) async {
      if (useHybridWithContext) {
        return ragEngine.searchHybridWithContext(
          query,
          topK: topK,
          tokenBudget: tokenBudget,
          strategy: strategy,
          adjacentChunks: adjacentChunks,
          singleSourceMode: singleSourceMode,
          collectionId: collectionId,
        );
      }

      return ragEngine.search(
        query,
        topK: topK,
        tokenBudget: tokenBudget,
        strategy: strategy,
        adjacentChunks: adjacentChunks,
        singleSourceMode: singleSourceMode,
        collectionId: collectionId,
      );
    };
  }

  Future<NotebookSearchResult> searchMerged({
    required String query,
    required List<String> collectionIds,
    int topK = 10,
    int tokenBudget = 2000,
    ContextStrategy strategy = ContextStrategy.relevanceFirst,
    int adjacentChunks = 0,
    bool singleSourceMode = false,
    bool useHybridWithContext = false,
  }) async {
    final normalizedCollectionIds = collectionIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedCollectionIds.isEmpty) {
      return const NotebookSearchResult(
        chunks: [],
        contextText: '',
        estimatedTokens: 0,
        chunkCountByCollection: {},
        failedCollections: [],
      );
    }

    final perCollectionTopK =
        ((topK / normalizedCollectionIds.length).ceil() + 1).clamp(2, topK + 2);
    final perCollectionBudget = (tokenBudget ~/ normalizedCollectionIds.length)
        .clamp(250, tokenBudget);

    final chunkOwner = <int, String>{};
    final chunkCountByCollection = <String, int>{};
    final failedCollections = <String>[];
    final byCollection = <String, List<ChunkSearchResult>>{};

    final futures = normalizedCollectionIds.map((collectionId) async {
      try {
        final ragResult = await _searchExecutor(
          collectionId: collectionId,
          query: query,
          topK: perCollectionTopK,
          tokenBudget: perCollectionBudget,
          strategy: strategy,
          adjacentChunks: adjacentChunks,
          singleSourceMode: singleSourceMode,
          useHybridWithContext: useHybridWithContext,
        );

        byCollection[collectionId] = ragResult.chunks;
        chunkCountByCollection[collectionId] = ragResult.chunks.length;
        for (final chunk in ragResult.chunks) {
          chunkOwner.putIfAbsent(chunk.chunkId.toInt(), () => collectionId);
        }
      } catch (_) {
        failedCollections.add(collectionId);
        byCollection[collectionId] = const [];
        chunkCountByCollection[collectionId] = 0;
      }
    });

    await Future.wait(futures);

    final mergedByChunkId = <int, ChunkSearchResult>{};
    for (final chunks in byCollection.values) {
      for (final chunk in chunks) {
        final chunkId = chunk.chunkId.toInt();
        final existing = mergedByChunkId[chunkId];
        if (existing == null || chunk.similarity > existing.similarity) {
          mergedByChunkId[chunkId] = chunk;
        }
      }
    }

    final merged = mergedByChunkId.values.toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));

    final selected = merged.take(topK).toList(growable: false);
    final contextText = _buildContextText(
      collectionOrder: normalizedCollectionIds,
      selectedChunks: selected,
      chunkOwner: chunkOwner,
    );

    return NotebookSearchResult(
      chunks: selected,
      contextText: contextText,
      estimatedTokens: _estimateTokenCount(contextText),
      chunkCountByCollection: chunkCountByCollection,
      failedCollections: failedCollections,
    );
  }

  String _buildContextText({
    required List<String> collectionOrder,
    required List<ChunkSearchResult> selectedChunks,
    required Map<int, String> chunkOwner,
  }) {
    if (selectedChunks.isEmpty) return '';

    final grouped = <String, List<ChunkSearchResult>>{};
    for (final chunk in selectedChunks) {
      final owner = chunkOwner[chunk.chunkId.toInt()];
      if (owner == null) continue;
      grouped.putIfAbsent(owner, () => <ChunkSearchResult>[]).add(chunk);
    }

    final buffer = StringBuffer();
    var wroteAny = false;
    for (final collectionId in collectionOrder) {
      final chunks = grouped[collectionId];
      if (chunks == null || chunks.isEmpty) {
        continue;
      }

      chunks.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

      if (wroteAny) {
        buffer.writeln('\n---\n');
      }
      wroteAny = true;

      buffer.writeln('[Collection: $collectionId]');
      for (final chunk in chunks) {
        buffer.writeln(
          '- (source:${chunk.sourceId}, chunk:${chunk.chunkIndex}, sim:${chunk.similarity.toStringAsFixed(3)})',
        );
        buffer.writeln(chunk.content.trim());
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  int _estimateTokenCount(String text) {
    if (text.trim().isEmpty) return 0;
    return (text.length / 4).ceil();
  }
}
