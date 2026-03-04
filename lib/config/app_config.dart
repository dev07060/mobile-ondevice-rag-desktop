/// Application configuration constants.
/// Centralizes all configuration values used throughout the application.

class AppConfig {
  // Private constructor to prevent instantiation
  AppConfig._();

  // Database configuration
  static const String databaseName = 'local_gemma_rag.db';

  // Asset paths
  static const String tokenizerAsset = 'assets/tokenizer.json';
  static const String modelAsset = 'assets/model.onnx';

  // Ollama server configuration
  static const int ollamaStartupMaxRetries = 20;
  static const Duration ollamaStartupRetryDelay = Duration(milliseconds: 500);
  static const Duration ollamaRestartDelay = Duration(seconds: 1);

  // UI configuration
  static const String appTitle = 'RAG + Ollama';
}
