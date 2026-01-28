/// Ollama status checking and model management service.
/// Handles connection status, model listing, and status updates.

import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Service for checking Ollama status and managing models
class OllamaStatusService {
  final OllamaClient _client;

  OllamaStatusService({OllamaClient? client})
    : _client = client ?? OllamaClient();

  /// Check Ollama connection and available models
  /// Returns a map with connection status, model availability, and selected model
  Future<OllamaStatus> checkStatus() async {
    try {
      // Check if Ollama server is running
      final version = await _client.getVersion();
      debugPrint('✅ Ollama version: ${version.version}');

      // Check installed models
      final models = await _client.listModels();
      final modelList = models.models ?? [];

      if (modelList.isNotEmpty) {
        // Find a suitable model (prefer gemma, then llama, then any)
        String? preferredModel;
        for (final model in modelList) {
          final name = model.model ?? '';
          if (name.contains('gemma')) {
            preferredModel = name;
            break;
          }
        }
        preferredModel ??= modelList.first.model;

        return OllamaStatus(
          isConnected: true,
          hasModel: true,
          selectedModel: preferredModel,
        );
      } else {
        return const OllamaStatus(isConnected: true, hasModel: false);
      }
    } catch (e) {
      debugPrint('🔴 Ollama connection error: $e');
      return OllamaStatus(
        isConnected: false,
        hasModel: false,
        errorMessage: 'Cannot connect to Ollama server',
      );
    }
  }
}

/// Represents the current status of Ollama
class OllamaStatus {
  final bool isConnected;
  final bool hasModel;
  final String? selectedModel;
  final String? errorMessage;

  const OllamaStatus({
    required this.isConnected,
    required this.hasModel,
    this.selectedModel,
    this.errorMessage,
  });
}
