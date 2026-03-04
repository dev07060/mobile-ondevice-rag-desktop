/// Service for generating LLM responses with RAG context.
/// Handles response mode selection (strict/hybrid/fallback) and prompt construction.

import 'dart:async';

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

/// Supported response languages for the LLM
enum ResponseLanguage { english, korean }

/// Service for generating Ollama LLM responses with RAG context
class OllamaResponseService {
  final OllamaClient ollamaClient;
  final String modelName;

  // Prevent indefinite waits when Ollama stalls.
  static const Duration _streamChunkTimeout = Duration(seconds: 30);
  static const Duration _streamMaxDuration = Duration(minutes: 2);

  // Thresholds for response mode selection
  static const double hybridThreshold = 0.5;
  static const double strictThreshold = 0.82;

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
    required List<ChunkSearchResult> retrievedChunks,
    required bool hasRelevantContext,
    required List<Message> chatHistory,
    ResponseLanguage language = ResponseLanguage.english,
    void Function(Message)? onHistoryUpdate,
    void Function(String token)? onToken,
  }) async {
    final effectiveLanguage =
        language == ResponseLanguage.english && _looksKorean(query)
        ? ResponseLanguage.korean
        : language;

    // Calculate best similarity score for mode decision
    final bestSimilarity = _calculateBestSimilarity(retrievedChunks);

    // Determine response mode
    final mode = _determineResponseMode(hasRelevantContext, bestSimilarity);

    debugPrint(
      '🎯 Response Mode: ${mode.name.toUpperCase()} '
      '(bestSim: ${bestSimilarity.toStringAsFixed(3)})',
    );

    try {
      // Build messages
      final messages = <Message>[];

      // 1. System Prompt - varies by mode and language
      messages.add(_buildSystemPrompt(mode, effectiveLanguage));

      // 2. Chat History (last 6 messages)
      final historyStart = chatHistory.length > 6 ? chatHistory.length - 6 : 0;
      messages.addAll(chatHistory.sublist(historyStart));

      // 3. Current User Message (WITH RAG CONTEXT)
      final userMessage = _buildUserMessage(
        query,
        contextText,
        mode,
        effectiveLanguage,
      );
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
      debugPrint('📨 Language: ${effectiveLanguage.name}');

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
          options: const RequestOptions(
            temperature: 0.15,
            topP: 0.9,
            repeatPenalty: 1.1,
            numPredict: 700,
          ),
        ),
      );

      final iterator = StreamIterator(stream);
      final streamStopwatch = Stopwatch()..start();

      while (await iterator.moveNext().timeout(
        _streamChunkTimeout,
        onTimeout: () => throw TimeoutException(
          'LLM stream stalled for ${_streamChunkTimeout.inSeconds}s',
        ),
      )) {
        if (streamStopwatch.elapsed > _streamMaxDuration) {
          throw TimeoutException(
            'LLM response exceeded ${_streamMaxDuration.inMinutes} minutes',
          );
        }

        final chunk = iterator.current;
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
      await iterator.cancel();

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
  double _calculateBestSimilarity(List<ChunkSearchResult> chunks) {
    if (chunks.isEmpty) return 0.0;

    return chunks
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
  Message _buildSystemPrompt(ResponseMode mode, ResponseLanguage language) {
    if (language == ResponseLanguage.korean) {
      return _buildKoreanSystemPrompt(mode);
    }
    return _buildEnglishSystemPrompt(mode);
  }

  Message _buildEnglishSystemPrompt(ResponseMode mode) {
    switch (mode) {
      case ResponseMode.strict:
        return const Message(
          role: MessageRole.system,
          content:
              'You are an AI assistant that answers from the provided context first. '
              'Do not invent facts. If evidence is insufficient, say it clearly. '
              'When the question asks for numbers, extract exact values from the context.',
        );
      case ResponseMode.hybrid:
        return const Message(
          role: MessageRole.system,
          content:
              'You are an AI assistant that combines context with general knowledge. '
              'Prioritize context first. If you add external knowledge, label it explicitly. '
              'Avoid unsupported claims and keep the answer concrete.',
        );
      case ResponseMode.fallback:
        return const Message(
          role: MessageRole.system,
          content: 'You are a helpful AI assistant.',
        );
    }
  }

  Message _buildKoreanSystemPrompt(ResponseMode mode) {
    switch (mode) {
      case ResponseMode.strict:
        return const Message(
          role: MessageRole.system,
          content:
              '당신은 제공된 문맥을 우선으로 답변하는 AI 어시스턴트입니다. '
              '근거가 부족하면 명확히 알리고 추측하지 마세요. '
              '숫자/수치 질문은 문맥의 값을 정확히 추출해 답변하세요.',
        );
      case ResponseMode.hybrid:
        return const Message(
          role: MessageRole.system,
          content:
              '당신은 제공된 문맥과 일반 지식을 조합하여 답변하는 AI 어시스턴트입니다. '
              '문서의 정보를 우선시하되, 필요한 경우 일반 지식을 보충하여 설명하세요. '
              '문서 근거와 일반 지식을 반드시 구분해서 작성하세요. '
              '근거 없는 단정은 피하고 한국어로 답변해주세요.',
        );
      case ResponseMode.fallback:
        return const Message(
          role: MessageRole.system,
          content: '당신은 도움이 되는 AI 어시스턴트입니다. 한국어로 답변해주세요.',
        );
    }
  }

  /// Build user message with context based on response mode and language
  String _buildUserMessage(
    String query,
    String contextText,
    ResponseMode mode,
    ResponseLanguage language,
  ) {
    if (language == ResponseLanguage.korean) {
      return _buildKoreanUserMessage(query, contextText, mode);
    }
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
If the question asks for specific numbers, provide exact values found in the context.

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

  String _buildKoreanUserMessage(
    String query,
    String contextText,
    ResponseMode mode,
  ) {
    switch (mode) {
      case ResponseMode.strict:
        return '''
[참고 문서]
$contextText
[참고 문서 끝]

위 내용을 바탕으로 다음 질문에 대해 답변해주세요.
숫자/수치 질문이라면 문맥에서 확인되는 값을 정확히 적어주세요.

질문: $query''';

      case ResponseMode.hybrid:
        return '''
[관련 문서]
$contextText
[관련 문서 끝]

위 문서는 질문과 관련된 내용을 포함하고 있습니다. 문서의 내용을 바탕으로 답변하되, 
필요하다면 일반 지식을 추가하여 설명해주세요.
문서의 내용과 일반 지식을 구분하여 답변해주세요.

질문: $query''';

      case ResponseMode.fallback:
        return '''
질문: $query

참고: 업로드된 문서에서 직접적으로 관련된 정보를 찾을 수 없습니다.
일반 지식을 바탕으로 답변해주시고, 더 정확한 정보가 필요하다면 관련 문서를 추가하도록 안내해주세요.''';
    }
  }

  bool _looksKorean(String text) => RegExp(r'[가-힣]').hasMatch(text);
}
