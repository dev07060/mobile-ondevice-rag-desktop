import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:local_gemma_macos/services/entity_graph_transformer.dart';

class EntityGraphPanel extends StatefulWidget {
  final String? query;
  final EntityGraphData graphData;
  final String? selectedNodeId;
  final String? selectedEdgeId;
  final void Function(String nodeId)? onNodeSelected;
  final void Function(EntityGraphEdge edge)? onEdgeSelected;

  const EntityGraphPanel({
    super.key,
    this.query,
    required this.graphData,
    this.selectedNodeId,
    this.selectedEdgeId,
    this.onNodeSelected,
    this.onEdgeSelected,
  });

  @override
  State<EntityGraphPanel> createState() => _EntityGraphPanelState();
}

class _EntityGraphPanelState extends State<EntityGraphPanel>
    with SingleTickerProviderStateMixin {
  final Map<String, Offset> _nodePositions = {};
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _scaleAtGestureStart = 1.0;
  Size? _containerSize;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _layoutNodes();
    _animationController.forward();
  }

  @override
  void didUpdateWidget(EntityGraphPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graphData != widget.graphData ||
        oldWidget.query != widget.query) {
      _layoutNodes();
      _scale = 1.0;
      _offset = Offset.zero;
      _centerGraph();
      _animationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _layoutNodes() {
    _nodePositions.clear();
    final nodes = widget.graphData.nodes;
    if (nodes.isEmpty) return;

    final seeds = nodes.where((n) => n.kind == EntityNodeKind.seed).toList();
    final expanded = nodes
        .where((n) => n.kind == EntityNodeKind.expanded)
        .toList();

    const center = Offset(220, 220);
    const innerRadius = 110.0;
    const outerRadius = 210.0;

    if (seeds.length == 1) {
      _nodePositions[seeds.first.id] = center;
    } else if (seeds.isNotEmpty) {
      final step = (2 * math.pi) / seeds.length;
      for (var i = 0; i < seeds.length; i++) {
        final angle = (step * i) - math.pi / 2;
        _nodePositions[seeds[i].id] = Offset(
          center.dx + innerRadius * math.cos(angle),
          center.dy + innerRadius * math.sin(angle),
        );
      }
    }

    final outerList = expanded.isEmpty ? [] : expanded;
    if (outerList.isNotEmpty) {
      final step = (2 * math.pi) / outerList.length;
      for (var i = 0; i < outerList.length; i++) {
        final node = outerList[i];
        final jitter = (((node.id.hashCode % 13) - 6) / 20.0);
        final angle = (step * i) - math.pi / 2 + jitter;
        _nodePositions[node.id] = Offset(
          center.dx + outerRadius * math.cos(angle),
          center.dy + outerRadius * math.sin(angle),
        );
      }
    }

    for (final node in nodes) {
      _nodePositions.putIfAbsent(node.id, () => center);
    }
  }

  void _centerGraph() {
    if (_containerSize == null) return;
    const logicalCenter = Offset(220, 220);
    final realCenter = Offset(
      _containerSize!.width / 2,
      _containerSize!.height / 2,
    );
    _offset = realCenter - (logicalCenter * _scale);
  }

  EntityGraphEdge? _findTappedEdge(Offset localPosition) {
    const maxDistance = 14.0;
    final edges = widget.graphData.edges;
    EntityGraphEdge? nearest;
    var bestDistance = double.infinity;

    for (final edge in edges) {
      final start = _project(_nodePositions[edge.sourceId] ?? Offset.zero);
      final end = _project(_nodePositions[edge.targetId] ?? Offset.zero);
      final distance = _distanceToSegment(localPosition, start, end);
      if (distance < maxDistance && distance < bestDistance) {
        bestDistance = distance;
        nearest = edge;
      }
    }
    return nearest;
  }

  Offset _project(Offset raw) => (raw * _scale) + _offset;

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) {
      return (p - a).distance;
    }
    final t =
        (((p.dx - a.dx) * dx) + ((p.dy - a.dy) * dy)) / ((dx * dx) + (dy * dy));
    final clamped = t.clamp(0.0, 1.0);
    final projection = Offset(a.dx + clamped * dx, a.dy + clamped * dy);
    return (p - projection).distance;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graphData.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 46,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 12),
              Text(
                'Entity Graph',
                style: TextStyle(color: Colors.grey[500], fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                'No relation traces found for current result',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Graph is shown only when answer has document evidence',
                style: TextStyle(color: Colors.grey[700], fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.grey[900],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_tree,
                      size: 16,
                      color: Colors.cyan,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Entity Graph',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.graphData.nodes.length} entities • ${widget.graphData.edges.length} relations',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Retrieved relation candidates from source chunks (not final truth)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_containerSize != constraints.biggest) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _containerSize = constraints.biggest;
                    if (_offset == Offset.zero) {
                      setState(_centerGraph);
                    }
                  });
                }

                return GestureDetector(
                  onDoubleTap: () {
                    setState(() {
                      _scale = 1.0;
                      _centerGraph();
                    });
                  },
                  onScaleStart: (_) {
                    _scaleAtGestureStart = _scale;
                  },
                  onTapUp: (details) {
                    final edge = _findTappedEdge(details.localPosition);
                    if (edge != null) {
                      widget.onEdgeSelected?.call(edge);
                    }
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _offset += details.focalPointDelta;
                      if (details.pointerCount > 1) {
                        _scale = (_scaleAtGestureStart * details.scale).clamp(
                          0.5,
                          3.0,
                        );
                      }
                    });
                  },
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _EntityEdgePainter(
                          edges: widget.graphData.edges,
                          positions: _nodePositions,
                          offset: _offset,
                          scale: _scale,
                          selectedEdgeId: widget.selectedEdgeId,
                          animationValue: _animationController.value,
                        ),
                        size: Size.infinite,
                        child: Stack(
                          children: widget.graphData.nodes.map((node) {
                            final position = _project(
                              _nodePositions[node.id] ?? Offset.zero,
                            );
                            final isSelected = widget.selectedNodeId == node.id;
                            final baseSize = node.kind == EntityNodeKind.seed
                                ? 28.0
                                : 22.0;
                            final nodeSize = isSelected
                                ? baseSize + 4
                                : baseSize;
                            return Positioned(
                              left: position.dx - nodeSize / 2,
                              top: position.dy - nodeSize / 2,
                              child: GestureDetector(
                                onTap: () =>
                                    widget.onNodeSelected?.call(node.id),
                                child: Tooltip(
                                  message:
                                      '${node.label}\nscore=${node.score.toStringAsFixed(2)}',
                                  child: Container(
                                    width: nodeSize,
                                    height: nodeSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: node.kind == EntityNodeKind.seed
                                          ? Colors.teal
                                          : Colors.indigo,
                                      border: isSelected
                                          ? Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            )
                                          : null,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              (node.kind == EntityNodeKind.seed
                                                      ? Colors.teal
                                                      : Colors.indigo)
                                                  .withValues(alpha: 0.45),
                                          blurRadius: isSelected ? 12 : 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              border: Border(top: BorderSide(color: Colors.grey[800]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(color: Colors.teal, label: 'Seed'),
                const SizedBox(width: 16),
                _legend(color: Colors.indigo, label: 'Expanded'),
                const SizedBox(width: 16),
                _legend(color: Colors.orange, label: 'Selected relation'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
      ],
    );
  }
}

class _EntityEdgePainter extends CustomPainter {
  final List<EntityGraphEdge> edges;
  final Map<String, Offset> positions;
  final Offset offset;
  final double scale;
  final String? selectedEdgeId;
  final double animationValue;

  _EntityEdgePainter({
    required this.edges,
    required this.positions,
    required this.offset,
    required this.scale,
    required this.selectedEdgeId,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final startRaw = positions[edge.sourceId];
      final endRaw = positions[edge.targetId];
      if (startRaw == null || endRaw == null) continue;

      final start = (startRaw * scale) + offset;
      final end = (endRaw * scale) + offset;
      final animatedEnd = Offset.lerp(start, end, animationValue.clamp(0, 1))!;

      final isSelected = selectedEdgeId == edge.id;
      final color = isSelected
          ? Colors.orange
          : Colors.grey.withValues(alpha: 0.45);
      final width = isSelected ? 3.0 : 1.0 + (edge.confidence * 2.6);
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      if (edge.maxHop >= 2) {
        _drawDashedLine(canvas, start, animatedEnd, paint);
      } else {
        canvas.drawLine(start, animatedEnd, paint);
      }

      final mid = Offset(
        (start.dx + animatedEnd.dx) / 2,
        (start.dy + animatedEnd.dy) / 2,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: edge.relationType,
          style: TextStyle(
            color: isSelected ? Colors.orange[200] : Colors.grey[400],
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 110);

      textPainter.paint(
        canvas,
        Offset(mid.dx - textPainter.width / 2, mid.dy - textPainter.height / 2),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 3.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final dashCount = (distance / (dashLength + gapLength)).floor();

    for (var i = 0; i < dashCount; i++) {
      final t1 = i * (dashLength + gapLength) / distance;
      final t2 = (i * (dashLength + gapLength) + dashLength) / distance;
      canvas.drawLine(
        Offset(start.dx + dx * t1, start.dy + dy * t1),
        Offset(start.dx + dx * t2, start.dy + dy * t2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EntityEdgePainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.edges != edges;
  }
}
