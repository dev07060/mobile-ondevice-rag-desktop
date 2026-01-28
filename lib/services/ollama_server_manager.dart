/// Ollama server process lifecycle manager.
/// Handles starting, stopping, and checking the status of the Ollama server.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart';
import '../config/app_config.dart';

/// Manages the Ollama server process lifecycle
class OllamaServerManager {
  static Process? _ollamaProcess;
  static bool _weStartedOllama = false;

  /// Check if Ollama is already running
  static Future<bool> isOllamaRunning() async {
    try {
      final client = OllamaClient();
      await client.getVersion();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start Ollama server if not already running
  static Future<bool> ensureOllamaRunning() async {
    // Check if already running
    if (await isOllamaRunning()) {
      debugPrint('✅ Ollama is already running');
      return true;
    }

    debugPrint('🚀 Starting Ollama server...');

    try {
      // Start ollama serve in background
      _ollamaProcess = await Process.start('ollama', [
        'serve',
      ], mode: ProcessStartMode.detached);
      _weStartedOllama = true;

      debugPrint('🚀 Ollama process started (PID: ${_ollamaProcess!.pid})');

      // Wait for server to be ready (max 10 seconds)
      for (int i = 0; i < AppConfig.ollamaStartupMaxRetries; i++) {
        await Future.delayed(AppConfig.ollamaStartupRetryDelay);
        if (await isOllamaRunning()) {
          debugPrint('✅ Ollama server is ready');
          return true;
        }
      }

      debugPrint('⚠️ Ollama server started but not responding');
      return false;
    } catch (e) {
      debugPrint('🔴 Failed to start Ollama: $e');
      return false;
    }
  }

  /// Stop Ollama server if we started it
  static Future<void> stopOllama() async {
    if (!_weStartedOllama || _ollamaProcess == null) {
      debugPrint('ℹ️ Ollama was not started by us, not stopping');
      return;
    }

    debugPrint('🛑 Stopping Ollama server...');

    try {
      // Try graceful shutdown first via API
      final result = await Process.run('pkill', ['-f', 'ollama serve']);
      debugPrint('🛑 Ollama stop result: ${result.exitCode}');
      _ollamaProcess = null;
      _weStartedOllama = false;
    } catch (e) {
      debugPrint('⚠️ Error stopping Ollama: $e');
    }
  }
}
