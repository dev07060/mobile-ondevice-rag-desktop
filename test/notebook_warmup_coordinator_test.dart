import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:local_gemma_macos/services/notebook_warmup_coordinator.dart';

class _FakeRagEngine extends Fake implements RagEngine {}

void main() {
  group('NotebookWarmupCoordinator', () {
    test(
      'ensureReady warms only requested collections and deduplicates',
      () async {
        final warmed = <String>[];

        final coordinator = NotebookWarmupCoordinator(
          ragEngine: _FakeRagEngine(),
          warmup: (collectionId) async {
            warmed.add(collectionId);
          },
          engineReadyCheck: (_) => false,
        );

        await coordinator.ensureReady(['alpha', 'alpha', 'beta']);

        expect(warmed.length, 2);
        expect(warmed.contains('alpha'), isTrue);
        expect(warmed.contains('beta'), isTrue);
        expect(coordinator.isReady('alpha'), isTrue);
        expect(coordinator.isReady('beta'), isTrue);
        expect(coordinator.isReady('gamma'), isFalse);
      },
    );

    test('primeInBackground does not warm unrequested collections', () async {
      final completer = Completer<void>();
      final warmed = <String>[];

      final coordinator = NotebookWarmupCoordinator(
        ragEngine: _FakeRagEngine(),
        warmup: (collectionId) async {
          warmed.add(collectionId);
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        engineReadyCheck: (_) => false,
      );

      coordinator.primeInBackground(['selected_collection']);
      await completer.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(warmed, ['selected_collection']);
      expect(coordinator.isReady('selected_collection'), isTrue);
      expect(coordinator.isReady('not_selected_collection'), isFalse);
    });
  });
}
