import 'dart:collection';

import 'package:mobile_rag_engine/mobile_rag_engine.dart';

enum EntityNodeKind { seed, expanded }

class EntityGraphNode {
  final String id;
  final String label;
  final EntityNodeKind kind;
  final double score;
  final int evidenceCount;

  const EntityGraphNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.score,
    required this.evidenceCount,
  });
}

class EntityGraphEdge {
  final String id;
  final String sourceId;
  final String targetId;
  final String relationType;
  final double confidence;
  final int maxHop;
  final double graphSignal;
  final List<int> evidenceChunkIds;

  const EntityGraphEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationType,
    required this.confidence,
    required this.maxHop,
    required this.graphSignal,
    required this.evidenceChunkIds,
  });
}

class EntityEvidenceRef {
  final int chunkId;
  final ChunkSearchResult chunk;
  final List<String> traces;
  final double graphSignal;

  const EntityEvidenceRef({
    required this.chunkId,
    required this.chunk,
    required this.traces,
    required this.graphSignal,
  });
}

class EntityGraphData {
  final List<EntityGraphNode> nodes;
  final List<EntityGraphEdge> edges;
  final List<EntityEvidenceRef> evidenceRefs;
  final int parsedTraceCount;
  final int skippedTraceCount;

  const EntityGraphData({
    required this.nodes,
    required this.edges,
    required this.evidenceRefs,
    required this.parsedTraceCount,
    required this.skippedTraceCount,
  });

  static const empty = EntityGraphData(
    nodes: [],
    edges: [],
    evidenceRefs: [],
    parsedTraceCount: 0,
    skippedTraceCount: 0,
  );

  bool get isEmpty => nodes.isEmpty || edges.isEmpty;
}

class EntityGraphTransformer {
  static final RegExp _tracePattern = RegExp(
    r'^\s*(.+?)\s*-(.+?)->\s*(.+?)\s*\(conf=([0-9]*\.?[0-9]+),\s*hop=(\d+)\)',
  );

  const EntityGraphTransformer._();

  static EntityGraphData transform({
    required Map<int, List<String>> relationTraceByChunkId,
    required Map<int, double> graphSignalByChunkId,
    required List<ChunkSearchResult> chunks,
    int maxNodes = 40,
  }) {
    if (relationTraceByChunkId.isEmpty || chunks.isEmpty) {
      return EntityGraphData.empty;
    }

    final chunkById = <int, ChunkSearchResult>{};
    for (final chunk in chunks) {
      chunkById[chunk.chunkId.toInt()] = chunk;
    }

    final edgeAgg = <String, _EdgeAccumulator>{};
    var parsed = 0;
    var skipped = 0;

    relationTraceByChunkId.forEach((chunkId, traces) {
      final chunkSignal = graphSignalByChunkId[chunkId] ?? 0.0;
      for (final trace in traces) {
        final parsedTrace = _parseTrace(trace);
        if (parsedTrace == null) {
          skipped += 1;
          continue;
        }
        parsed += 1;

        final edgeKey =
            '${parsedTrace.source}|${parsedTrace.relation}|${parsedTrace.target}';
        final edge = edgeAgg.putIfAbsent(
          edgeKey,
          () => _EdgeAccumulator(
            sourceId: parsedTrace.source,
            targetId: parsedTrace.target,
            relationType: parsedTrace.relation,
            confidence: parsedTrace.confidence,
            maxHop: parsedTrace.hop,
          ),
        );

        if (parsedTrace.confidence > edge.confidence) {
          edge.confidence = parsedTrace.confidence;
        }
        if (parsedTrace.hop > edge.maxHop) {
          edge.maxHop = parsedTrace.hop;
        }
        if (edge.evidenceChunkIds.add(chunkId)) {
          edge.graphSignal += chunkSignal;
        }
      }
    });

    if (edgeAgg.isEmpty) {
      return EntityGraphData(
        nodes: const [],
        edges: const [],
        evidenceRefs: const [],
        parsedTraceCount: parsed,
        skippedTraceCount: skipped,
      );
    }

    final sortedEdges = edgeAgg.values.toList()
      ..sort((a, b) => b.weightScore.compareTo(a.weightScore));

    final selectedNodeIds = <String>{};
    final selectedEdges = <_EdgeAccumulator>[];

    for (final edge in sortedEdges) {
      final missingNodes = <String>[
        if (!selectedNodeIds.contains(edge.sourceId)) edge.sourceId,
        if (!selectedNodeIds.contains(edge.targetId)) edge.targetId,
      ];

      final wouldOverflow =
          selectedNodeIds.length + missingNodes.length > maxNodes;
      if (wouldOverflow && missingNodes.isNotEmpty) {
        continue;
      }

      selectedNodeIds.addAll(missingNodes);
      selectedEdges.add(edge);
    }

    final nodeScores = <String, double>{};
    final nodeEvidenceCounts = <String, int>{};
    final seedNodeIds = <String>{};

    for (final edge in selectedEdges) {
      nodeScores[edge.sourceId] =
          (nodeScores[edge.sourceId] ?? 0.0) + edge.weightScore;
      nodeScores[edge.targetId] =
          (nodeScores[edge.targetId] ?? 0.0) + edge.weightScore;
      nodeEvidenceCounts[edge.sourceId] =
          (nodeEvidenceCounts[edge.sourceId] ?? 0) +
          edge.evidenceChunkIds.length;
      nodeEvidenceCounts[edge.targetId] =
          (nodeEvidenceCounts[edge.targetId] ?? 0) +
          edge.evidenceChunkIds.length;

      if (edge.maxHop <= 1) {
        seedNodeIds.add(edge.sourceId);
        seedNodeIds.add(edge.targetId);
      }
    }

    final nodes =
        selectedNodeIds
            .map(
              (id) => EntityGraphNode(
                id: id,
                label: id,
                kind: seedNodeIds.contains(id)
                    ? EntityNodeKind.seed
                    : EntityNodeKind.expanded,
                score: nodeScores[id] ?? 0.0,
                evidenceCount: nodeEvidenceCounts[id] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    final edges =
        selectedEdges
            .map(
              (edge) => EntityGraphEdge(
                id: edge.id,
                sourceId: edge.sourceId,
                targetId: edge.targetId,
                relationType: edge.relationType,
                confidence: edge.confidence,
                maxHop: edge.maxHop,
                graphSignal: edge.graphSignal,
                evidenceChunkIds: edge.evidenceChunkIds.toList()..sort(),
              ),
            )
            .toList()
          ..sort((a, b) {
            final byConfidence = b.confidence.compareTo(a.confidence);
            if (byConfidence != 0) return byConfidence;
            return b.graphSignal.compareTo(a.graphSignal);
          });

    final evidenceRefMap = <int, EntityEvidenceRef>{};
    for (final edge in edges) {
      for (final chunkId in edge.evidenceChunkIds) {
        final chunk = chunkById[chunkId];
        if (chunk == null) continue;
        final tracesForChunk =
            relationTraceByChunkId[chunkId] ?? const <String>[];
        final matching = tracesForChunk
            .where(
              (trace) =>
                  trace.contains(edge.sourceId) &&
                  trace.contains(edge.relationType) &&
                  trace.contains(edge.targetId),
            )
            .toList();

        evidenceRefMap[chunkId] = EntityEvidenceRef(
          chunkId: chunkId,
          chunk: chunk,
          traces: matching,
          graphSignal: graphSignalByChunkId[chunkId] ?? 0.0,
        );
      }
    }

    final evidenceRefs = evidenceRefMap.values.toList()
      ..sort((a, b) => b.graphSignal.compareTo(a.graphSignal));

    return EntityGraphData(
      nodes: nodes,
      edges: edges,
      evidenceRefs: evidenceRefs,
      parsedTraceCount: parsed,
      skippedTraceCount: skipped,
    );
  }

  static _ParsedTrace? _parseTrace(String trace) {
    final head = trace.split('|').first.trim();
    final match = _tracePattern.firstMatch(head);
    if (match == null) return null;

    final source = match.group(1)?.trim();
    final relation = match.group(2)?.trim();
    final target = match.group(3)?.trim();
    final confidence = double.tryParse(match.group(4) ?? '');
    final hop = int.tryParse(match.group(5) ?? '');

    if (source == null ||
        source.isEmpty ||
        relation == null ||
        relation.isEmpty ||
        target == null ||
        target.isEmpty ||
        confidence == null ||
        hop == null) {
      return null;
    }

    return _ParsedTrace(
      source: source,
      relation: relation,
      target: target,
      confidence: confidence.clamp(0.0, 1.0),
      hop: hop,
    );
  }
}

class _ParsedTrace {
  final String source;
  final String relation;
  final String target;
  final double confidence;
  final int hop;

  const _ParsedTrace({
    required this.source,
    required this.relation,
    required this.target,
    required this.confidence,
    required this.hop,
  });
}

class _EdgeAccumulator {
  final String sourceId;
  final String targetId;
  final String relationType;
  double confidence;
  int maxHop;
  double graphSignal = 0.0;
  final LinkedHashSet<int> evidenceChunkIds = LinkedHashSet<int>();

  _EdgeAccumulator({
    required this.sourceId,
    required this.targetId,
    required this.relationType,
    required this.confidence,
    required this.maxHop,
  });

  String get id => '$sourceId|$relationType|$targetId';

  double get weightScore => confidence + graphSignal;
}
