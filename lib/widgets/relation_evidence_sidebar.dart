import 'package:flutter/material.dart';
import 'package:local_gemma_macos/services/entity_graph_transformer.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

class RelationEvidenceSidebar extends StatelessWidget {
  final EntityGraphEdge? selectedEdge;
  final List<ChunkSearchResult> chunks;
  final Map<int, List<String>> relationTraceByChunkId;
  final ChunkSearchResult? selectedChunk;
  final void Function(ChunkSearchResult chunk)? onChunkSelected;

  const RelationEvidenceSidebar({
    super.key,
    required this.selectedEdge,
    required this.chunks,
    required this.relationTraceByChunkId,
    this.selectedChunk,
    this.onChunkSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedEdge == null) {
      return Container(
        color: const Color(0xFF1E1E1E),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link, size: 34, color: Colors.grey[600]),
              const SizedBox(height: 10),
              Text(
                'Select relation',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Click an edge in entity graph',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    final chunkById = <int, ChunkSearchResult>{
      for (final chunk in chunks) chunk.chunkId.toInt(): chunk,
    };

    final evidenceChunks =
        selectedEdge!.evidenceChunkIds
            .map((id) => chunkById[id])
            .whereType<ChunkSearchResult>()
            .toList()
          ..sort((a, b) => b.similarity.compareTo(a.similarity));

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Relation Evidence',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${selectedEdge!.sourceId} -${selectedEdge!.relationType}-> ${selectedEdge!.targetId}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${evidenceChunks.length} chunks • conf ${selectedEdge!.confidence.toStringAsFixed(2)} • hop ${selectedEdge!.maxHop}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 10),
                ),
              ],
            ),
          ),
          if (evidenceChunks.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No evidence chunks',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(6),
                itemCount: evidenceChunks.length,
                itemBuilder: (context, index) {
                  final chunk = evidenceChunks[index];
                  final chunkId = chunk.chunkId.toInt();
                  final selected = selectedChunk?.chunkId == chunk.chunkId;
                  final rawTraces =
                      relationTraceByChunkId[chunkId] ?? const <String>[];
                  final traces = rawTraces
                      .where(
                        (trace) =>
                            trace.contains(selectedEdge!.sourceId) &&
                            trace.contains(selectedEdge!.relationType) &&
                            trace.contains(selectedEdge!.targetId),
                      )
                      .take(2)
                      .toList();

                  return GestureDetector(
                    onTap: () => onChunkSelected?.call(chunk),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.blue.withValues(alpha: 0.22)
                            : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.blue : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.24),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '#${chunk.chunkIndex}',
                                  style: TextStyle(
                                    color: Colors.purple[200],
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'sim ${(chunk.similarity).toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _preview(chunk.content),
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 10.5,
                              height: 1.4,
                            ),
                          ),
                          if (traces.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...traces.map(
                              (trace) => Text(
                                '• ${trace.split('|').first.trim()}',
                                style: TextStyle(
                                  color: Colors.orange[300],
                                  fontSize: 9.5,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _preview(String content) {
    final normalized = content.replaceAll('\n', ' ').trim();
    if (normalized.length <= 170) return normalized;
    return '${normalized.substring(0, 170)}...';
  }
}
