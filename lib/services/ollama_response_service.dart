/// Service for generating LLM responses with RAG context.
/// Handles response mode selection (strict/hybrid/fallback) and prompt construction.

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Response mode based on RAG similarity scores
enum ResponseMode {
  strict, // High similarity (>= 0.7): use only document context
  hybrid, // Medium similarity (>= 0.5): combine document + general knowledge
  fallback, // Low/no similarity: use general knowledge
}

/// Result of response generation
class OllamaResponseResult {
  final String response;
  final ResponseMode mode;
  final double bestSimilarity;

  const OllamaResponseResult({
    required this.response,
    required this.mode,
    required this.bestSimilarity,
  });
}

/// Service for generating Ollama LLM responses with RAG context
class OllamaResponseService {
  final OllamaClient ollamaClient;
  final String modelName;

  // Thresholds for response mode selection
  static const double hybridThreshold = 0.5;
  static const double strictThreshold = 0.7;

  OllamaResponseService({
    required this.ollamaClient,
    this.modelName = 'gemma3:4b',
  });

  /// Generate a response using RAG context
  /// Returns the response text and metadata
  /// [onToken] callback is called for each token as it arrives (for real-time UI)
  Future<OllamaResponseResult> generateResponse({
    required String query,
    required String contextText,
    required RagSearchResult ragResult,
    required bool hasRelevantContext,
    required List<Message> chatHistory,
    void Function(Message)? onHistoryUpdate,
    void Function(String token)? onToken,
  }) async {
    // Calculate best similarity score for mode decision
    final bestSimilarity = _calculateBestSimilarity(ragResult);

    // Determine response mode
    final mode = _determineResponseMode(hasRelevantContext, bestSimilarity);

    debugPrint(
      '🎯 Response Mode: ${mode.name.toUpperCase()} '
      '(bestSim: ${bestSimilarity.toStringAsFixed(3)})',
    );

    try {
      // Build messages
      final messages = <Message>[];

      // 1. System Prompt - varies by mode
      messages.add(_buildSystemPrompt(mode));

      // 2. Chat History (last 6 messages)
      final historyStart = chatHistory.length > 6 ? chatHistory.length - 6 : 0;
      messages.addAll(chatHistory.sublist(historyStart));

      // 3. Current User Message (WITH RAG CONTEXT)
      final userMessage = _buildUserMessage(query, contextText, mode);
      messages.add(Message(role: MessageRole.user, content: userMessage));

      // Save raw query to history (not the huge context prompt)
      onHistoryUpdate?.call(Message(role: MessageRole.user, content: query));

      // Debug: Log prompt structure
      debugPrint('📨 === Prompt to LLM ===');
      debugPrint('📨 System: ${messages[0].content}');
      debugPrint('📨 History: ${chatHistory.length} messages');
      debugPrint('📨 User Query: $query');
      debugPrint('📨 Context Length: ${contextText.length} chars');
      debugPrint('📨 Mode: ${mode.name}');

      // Stream response from Ollama
      final responseBuffer = StringBuffer();
      final thinkingBuffer = StringBuffer();
      bool isInThinking = false;
      int chunkCount = 0;

      debugPrint('📝 === LLM Streaming Start ===');

      final stream = ollamaClient.generateChatCompletionStream(
        request: GenerateChatCompletionRequest(
          model: modelName,
          messages: messages,
        ),
      );

      await for (final chunk in stream) {
        final content = chunk.message.content;
        responseBuffer.write(content);
        chunkCount++;

        // Detect thinking/reasoning sections (some models use <think> tags)
        if (content.contains('<think>')) {
          isInThinking = true;
          debugPrint('🧠 [THINKING START]');
        }
        if (content.contains('</think>')) {
          isInThinking = false;
          debugPrint('🧠 [THINKING END]');
        }

        // Log chunk content
        if (isInThinking) {
          thinkingBuffer.write(content);
          // Print thinking chunks with special prefix
          final cleanContent = content.replaceAll('\n', '↕');
          debugPrint('🧠 $cleanContent');
        } else {
          // Stream token to UI callback (real-time display)
          if (onToken != null && content.isNotEmpty) {
            onToken(content);
          }
          // Print response chunks
          final cleanContent = content.replaceAll('\n', '↕');
          if (cleanContent.isNotEmpty) {
            // debugPrint('💬 $cleanContent');
          }
        }
      }

      debugPrint('📝 === LLM Streaming End ($chunkCount chunks) ===');

      // Log thinking summary if any
      if (thinkingBuffer.isNotEmpty) {
        debugPrint('🧠 === Thinking Summary ===');
        debugPrint(thinkingBuffer.toString());
        debugPrint('🧠 === End Thinking ===');
      }

      final response = responseBuffer.toString().trim();

      // Save assistant response to history
      onHistoryUpdate?.call(
        Message(role: MessageRole.assistant, content: response),
      );

      if (response.isEmpty) {
        return OllamaResponseResult(
          response:
              '⚠️ The model returned an empty response. Please try again.',
          mode: mode,
          bestSimilarity: bestSimilarity,
        );
      }

      return OllamaResponseResult(
        response: response,
        mode: mode,
        bestSimilarity: bestSimilarity,
      );
    } catch (e, stackTrace) {
      debugPrint('🔴 Ollama Error: $e');
      debugPrint('🔴 Stack Trace: $stackTrace');

      return OllamaResponseResult(
        response:
            '⚠️ Ollama Error: $e\n\n'
            'Make sure Ollama is running (ollama serve) and the model is installed.',
        mode: mode,
        bestSimilarity: bestSimilarity,
      );
    }
  }

  /// Calculate best similarity score from RAG results
  double _calculateBestSimilarity(RagSearchResult ragResult) {
    if (ragResult.chunks.isEmpty) return 0.0;

    return ragResult.chunks
        .map((c) => c.similarity)
        .where((s) => s > 0) // Exclude adjacent chunks with 0.0
        .fold(0.0, (a, b) => a > b ? a : b);
  }

  /// Determine response mode based on context and similarity
  ResponseMode _determineResponseMode(
    bool hasRelevantContext,
    double bestSimilarity,
  ) {
    if (!hasRelevantContext) return ResponseMode.fallback;
    if (bestSimilarity >= strictThreshold) return ResponseMode.strict;
    if (bestSimilarity >= hybridThreshold) return ResponseMode.hybrid;
    return ResponseMode.fallback;
  }

  /// Build system prompt based on response mode and language
  Message _buildSystemPrompt(ResponseMode mode) {
    // English is now the default and only supported prompt language for this release
    return _buildEnglishSystemPrompt(mode);
  }

  Message _buildEnglishSystemPrompt(ResponseMode mode) {
    switch (mode) {
      case ResponseMode.strict:
        return const Message(
          role: MessageRole.system,
          content:
              'You are an AI assistant that answers accurately based on the provided context. '
              'Prioritize information from the context in your answers.',
        );
      case ResponseMode.hybrid:
        return const Message(
          role: MessageRole.system,
          content:
              'You are an AI assistant that combines the provided context with general knowledge. '
              'Prioritize context information, but supplement with general knowledge when needed. '
              'Clearly distinguish between information from the context and general knowledge.',
        );
      case ResponseMode.fallback:
        return const Message(
          role: MessageRole.system,
          content: 'You are a helpful AI assistant.',
        );
    }
  }

  /// Build user message with context based on response mode and language
  String _buildUserMessage(
    String query,
    String contextText,
    ResponseMode mode,
  ) {
    // English is now the default and only supported prompt language for this release
    return _buildEnglishUserMessage(query, contextText, mode);
  }

  String _buildEnglishUserMessage(
    String query,
    String contextText,
    ResponseMode mode,
  ) {
    switch (mode) {
      case ResponseMode.strict:
        return '''
[Reference Documents]
$contextText
[End of Reference Documents]

Based on the content above, please answer the following question.

Question: $query''';

      case ResponseMode.hybrid:
        return '''
[Related Documents]
$contextText
[End of Related Documents]

The documents above contain related information. Please answer based on the document content, 
but you may supplement with general knowledge if needed.
Please distinguish between information from the documents and general knowledge.

Question: $query''';

      case ResponseMode.fallback:
        return '''
Question: $query

Note: No directly relevant information was found in the uploaded documents.
Please answer with general knowledge, and suggest adding relevant documents if more accurate information is needed.''';
    }
  }
}
