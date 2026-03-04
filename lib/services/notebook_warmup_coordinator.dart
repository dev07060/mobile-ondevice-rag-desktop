import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

class NotebookWarmupCoordinator {
  final Future<void> Function(String collectionId) _warmup;
  final bool Function(String collectionId) _engineReadyCheck;

  final Set<String> _readyCollections = <String>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  NotebookWarmupCoordinator({
    required RagEngine ragEngine,
    Future<void> Function(String collectionId)? warmup,
    bool Function(String collectionId)? engineReadyCheck,
  }) : _warmup = warmup ?? ragEngine.collectionWarmupFuture,
       _engineReadyCheck = engineReadyCheck ?? ragEngine.isCollectionIndexReady;

  Iterable<String> _normalizeIds(Iterable<String> collectionIds) {
    return collectionIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool isReady(String collectionId) {
    final id = collectionId.trim();
    if (id.isEmpty) return false;
    return _readyCollections.contains(id) || _engineReadyCheck(id);
  }

  Set<String> get readyCollectionIds => Set<String>.from(_readyCollections);

  Future<void> ensureReady(Iterable<String> collectionIds) async {
    final normalized = _normalizeIds(collectionIds);
    if (normalized.isEmpty) return;

    await Future.wait(normalized.map(_warmupCollection));
  }

  void primeInBackground(Iterable<String> collectionIds) {
    final normalized = _normalizeIds(collectionIds);
    if (normalized.isEmpty) return;

    for (final collectionId in normalized) {
      unawaited(
        _warmupCollection(collectionId).catchError((error, stackTrace) {
          debugPrint('⚠️ Warmup failed for $collectionId: $error');
        }),
      );
    }
  }

  Future<void> _warmupCollection(String collectionId) async {
    if (isReady(collectionId)) {
      _readyCollections.add(collectionId);
      return;
    }

    final inFlight = _inFlight[collectionId];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = () async {
      await _warmup(collectionId);
      _readyCollections.add(collectionId);
    }();

    _inFlight[collectionId] = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight[collectionId], future)) {
        _inFlight.remove(collectionId);
      }
    }
  }
}
