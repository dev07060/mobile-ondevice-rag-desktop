import 'package:flutter_test/flutter_test.dart';
import 'package:local_gemma_macos/services/entity_graph_transformer.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

ChunkSearchResult _chunk(int id, {double similarity = 0.8}) {
  return ChunkSearchResult(
    chunkId: id,
    sourceId: 1,
    chunkIndex: id,
    content: 'chunk-$id',
    chunkType: 'graph',
    similarity: similarity,
    metadata: null,
  );
}

void main() {
  group('EntityGraphTransformer', () {
    test('parses a valid relation trace', () {
      final data = EntityGraphTransformer.transform(
        relationTraceByChunkId: {
          11: ['Alpha -uses-> Beta (conf=0.70, hop=1)'],
        },
        graphSignalByChunkId: {11: 0.2},
        chunks: [_chunk(11)],
        maxNodes: 40,
      );

      expect(data.parsedTraceCount, 1);
      expect(data.skippedTraceCount, 0);
      expect(data.nodes.length, 2);
      expect(data.edges.length, 1);

      final edge = data.edges.first;
      expect(edge.sourceId, 'Alpha');
      expect(edge.relationType, 'uses');
      expect(edge.targetId, 'Beta');
      expect(edge.confidence, closeTo(0.70, 1e-9));
      expect(edge.maxHop, 1);
      expect(edge.graphSignal, closeTo(0.2, 1e-9));
      expect(edge.evidenceChunkIds, [11]);
    });

    test('parses trace line even when snippet exists', () {
      final data = EntityGraphTransformer.transform(
        relationTraceByChunkId: {
          21: ['Alpha -uses-> Beta (conf=0.70, hop=1) | snippet text'],
        },
        graphSignalByChunkId: {21: 0.3},
        chunks: [_chunk(21)],
      );

      expect(data.parsedTraceCount, 1);
      expect(data.skippedTraceCount, 0);
      expect(data.edges.length, 1);
    });

    test('skips malformed traces', () {
      final data = EntityGraphTransformer.transform(
        relationTraceByChunkId: {
          31: ['totally malformed relation line'],
        },
        graphSignalByChunkId: {31: 0.4},
        chunks: [_chunk(31)],
      );

      expect(data.parsedTraceCount, 0);
      expect(data.skippedTraceCount, 1);
      expect(data.edges, isEmpty);
      expect(data.nodes, isEmpty);
    });

    test('aggregates duplicate edge by confidence/evidence/graphSignal', () {
      final data = EntityGraphTransformer.transform(
        relationTraceByChunkId: {
          41: ['Alpha -uses-> Beta (conf=0.70, hop=1)'],
          42: ['Alpha -uses-> Beta (conf=0.90, hop=2)'],
        },
        graphSignalByChunkId: {41: 0.2, 42: 0.4},
        chunks: [_chunk(41), _chunk(42)],
      );

      expect(data.edges.length, 1);
      final edge = data.edges.first;
      expect(edge.confidence, closeTo(0.90, 1e-9));
      expect(edge.maxHop, 2);
      expect(edge.graphSignal, closeTo(0.6, 1e-9));
      expect(edge.evidenceChunkIds.toSet(), {41, 42});
    });

    test('applies Top-40 node cap', () {
      final traces = <int, List<String>>{};
      final signals = <int, double>{};
      final chunks = <ChunkSearchResult>[];

      for (var i = 0; i < 60; i++) {
        final chunkId = 100 + i;
        final conf = (1.0 - (i * 0.01)).clamp(0.01, 1.0);
        traces[chunkId] = [
          'A$i -rel-> B$i (conf=${conf.toStringAsFixed(2)}, hop=1)',
        ];
        signals[chunkId] = 0.0;
        chunks.add(_chunk(chunkId));
      }

      final data = EntityGraphTransformer.transform(
        relationTraceByChunkId: traces,
        graphSignalByChunkId: signals,
        chunks: chunks,
        maxNodes: 40,
      );

      expect(data.nodes.length <= 40, isTrue);
      expect(data.edges.length <= 20, isTrue);
      expect(data.edges.any((e) => e.id == 'A0|rel|B0'), isTrue);
      expect(data.edges.any((e) => e.id == 'A59|rel|B59'), isFalse);
    });
  });
}
