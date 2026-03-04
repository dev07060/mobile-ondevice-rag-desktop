import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_gemma_macos/services/entity_graph_transformer.dart';
import 'package:local_gemma_macos/widgets/entity_graph_panel.dart';
import 'package:local_gemma_macos/widgets/relation_evidence_sidebar.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

ChunkSearchResult _chunk(int id, String content) {
  return ChunkSearchResult(
    chunkId: id,
    sourceId: 1,
    chunkIndex: id,
    content: content,
    chunkType: 'graph',
    similarity: 0.8,
    metadata: null,
  );
}

void main() {
  testWidgets('EntityGraphPanel empty state is rendered', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: EntityGraphPanel(graphData: EntityGraphData.empty),
          ),
        ),
      ),
    );

    expect(find.text('Entity Graph'), findsOneWidget);
    expect(
      find.text('No relation traces found for current result'),
      findsOneWidget,
    );
  });

  testWidgets('EntityGraphPanel renders node/edge counters', (tester) async {
    const graphData = EntityGraphData(
      nodes: [
        EntityGraphNode(
          id: 'Alpha',
          label: 'Alpha',
          kind: EntityNodeKind.seed,
          score: 1.2,
          evidenceCount: 1,
        ),
        EntityGraphNode(
          id: 'Beta',
          label: 'Beta',
          kind: EntityNodeKind.expanded,
          score: 0.7,
          evidenceCount: 1,
        ),
      ],
      edges: [
        EntityGraphEdge(
          id: 'Alpha|uses|Beta',
          sourceId: 'Alpha',
          targetId: 'Beta',
          relationType: 'uses',
          confidence: 0.8,
          maxHop: 1,
          graphSignal: 0.3,
          evidenceChunkIds: [1],
        ),
      ],
      evidenceRefs: [],
      parsedTraceCount: 1,
      skippedTraceCount: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: EntityGraphPanel(graphData: graphData)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 entities • 1 relations'), findsOneWidget);
  });

  testWidgets('RelationEvidenceSidebar renders selected relation evidence', (
    tester,
  ) async {
    final chunks = [
      _chunk(5, 'This chunk contains evidence for Alpha uses Beta relation.'),
    ];

    const edge = EntityGraphEdge(
      id: 'Alpha|uses|Beta',
      sourceId: 'Alpha',
      targetId: 'Beta',
      relationType: 'uses',
      confidence: 0.8,
      maxHop: 1,
      graphSignal: 0.4,
      evidenceChunkIds: [5],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: RelationEvidenceSidebar(
              selectedEdge: edge,
              chunks: chunks,
              relationTraceByChunkId: const {
                5: ['Alpha -uses-> Beta (conf=0.80, hop=1)'],
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Relation Evidence'), findsOneWidget);
    expect(find.textContaining('Alpha -uses-> Beta'), findsNWidgets(2));
    expect(find.textContaining('This chunk contains evidence'), findsOneWidget);
  });
}
