/// Service for orchestrating RAG search and LLM response generation.
/// Extracts core chat logic from RagChatScreen for better separation of concerns.

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart' as intent;
import 'package:ollama_dart/ollama_dart.dart';
import 'package:local_gemma_macos/widgets/slash_command_overlay.dart';

import 'notebook_rag_service.dart';
import 'ollama_response_service.dart';
import 'query_intent_handler.dart';
import 'query_understanding_service.dart';

/// Result of processing a chat message
class ChatProcessResult {
  final String response;
  final List<ChunkSearchResult> chunks;
  final int estimatedTokens;
  final String queryType;
  final Duration ragSearchTime;
  final Duration llmGenerationTime;
  final Duration totalTime;
  final String? rejectionReason;
  final bool isRejected;

  const ChatProcessResult({
    required this.response,
    required this.chunks,
    required this.estimatedTokens,
    required this.queryType,
    required this.ragSearchTime,
    required this.llmGenerationTime,
    required this.totalTime,
    this.rejectionReason,
    this.isRejected = false,
  });

  /// Create a rejection result for invalid queries
  factory ChatProcessResult.rejected(String reason) {
    return ChatProcessResult(
      response: reason,
      chunks: const [],
      estimatedTokens: 0,
      queryType: 'rejected',
      ragSearchTime: Duration.zero,
      llmGenerationTime: Duration.zero,
      totalTime: Duration.zero,
      rejectionReason: reason,
      isRejected: true,
    );
  }
}

/// Parsed intent result with display text
class ParsedMessageIntent {
  final intent.ParsedIntent parsed;
  final String effectiveQuery;
  final String displayText;

  const ParsedMessageIntent({
    required this.parsed,
    required this.effectiveQuery,
    required this.displayText,
  });
}

/// Service for RAG + LLM orchestration
class RagChatService {
  final RagEngine ragEngine;
  final OllamaClient ollamaClient;
  final QueryUnderstandingService queryService;
  final OllamaResponseService responseService;
  final NotebookRagService notebookRagService;
  final List<Message> chatHistory;

  /// Minimum similarity threshold for filtering chunks
  final double minSimilarityThreshold;

  /// Whether to use mock LLM (for testing without Ollama)
  final bool mockLlm;

  RagChatService({
    required this.ragEngine,
    required this.ollamaClient,
    required this.queryService,
    required this.responseService,
    required this.chatHistory,
    NotebookRagService? notebookRagService,
    this.minSimilarityThreshold = 0.35,
    this.mockLlm = false,
  }) : notebookRagService =
           notebookRagService ?? NotebookRagService(ragEngine: ragEngine);

  /// Parse user input into intent
  ParsedMessageIntent parseIntent(
    String text, {
    SlashCommand? selectedCommand,
  }) {
    if (selectedCommand != null) {
      final intentType = switch (selectedCommand.command) {
        '/summary' => 'summary',
        '/define' => 'define',
        '/more' => 'more',
        _ => 'general',
      };

      return ParsedMessageIntent(
        parsed: intent.ParsedIntent(
          intentType: intentType,
          query: text,
          isValid: true,
          errorMessage: null,
        ),
        effectiveQuery: text,
        displayText: '${selectedCommand.command} $text',
      );
    }

    final parsedIntent = intent.parseIntent(input: text);
    return ParsedMessageIntent(
      parsed: parsedIntent,
      effectiveQuery: parsedIntent.query.isEmpty ? text : parsedIntent.query,
      displayText: text,
    );
  }

  /// Process a message and generate response
  Future<ChatProcessResult> processMessage(
    String text,
    ParsedMessageIntent parsedIntent, {
    required List<String> collectionIds,
    ResponseLanguage language = ResponseLanguage.english,
    void Function(String token)? onToken,
  }) async {
    final totalStopwatch = Stopwatch()..start();

    final understanding = await queryService.analyze(
      parsedIntent.effectiveQuery,
    );

    if (!understanding.isValid && parsedIntent.parsed.intentType == 'general') {
      totalStopwatch.stop();
      return ChatProcessResult.rejected(
        understanding.rejectionReason ?? '질문을 이해하지 못했습니다.',
      );
    }

    debugPrint('✅ Query validated: ${understanding.type.name}');
    debugPrint('   Normalized: "${understanding.normalizedQuery}"');
    debugPrint('   Keywords: ${understanding.keywords}');

    final intentConfig = QueryIntentHandler.getConfig(parsedIntent.parsed);
    final int adjacentChunks;
    final int tokenBudget;
    final int topK;

    if (parsedIntent.parsed.intentType != 'general') {
      adjacentChunks = intentConfig.adjacentChunks;
      tokenBudget = intentConfig.tokenBudget;
      topK = intentConfig.topK;
    } else {
      (adjacentChunks, tokenBudget, topK) = switch (understanding.type) {
        QueryType.definition => (1, 1000, 5),
        QueryType.explanation => (2, 2500, 10),
        QueryType.factual => (1, 1500, 5),
        QueryType.comparison => (2, 3000, 12),
        QueryType.listing => (3, 4000, 15),
        QueryType.summary => (1, 1500, 5),
        _ => (2, 2000, 10),
      };
    }

    debugPrint(
      '📐 Using: type=${understanding.type.name}, adjacent=$adjacentChunks, budget=$tokenBudget, topK=$topK',
    );

    final ragStopwatch = Stopwatch()..start();

    final notebookResult = await notebookRagService.searchMerged(
      query: understanding.normalizedQuery,
      collectionIds: collectionIds,
      topK: topK,
      tokenBudget: tokenBudget,
      strategy: ContextStrategy.relevanceFirst,
      adjacentChunks: adjacentChunks,
      singleSourceMode: false,
      useHybridWithContext: false,
    );

    ragStopwatch.stop();
    final ragSearchTime = ragStopwatch.elapsed;

    debugPrint('🔍 BGE-m3 merged search for: "${understanding.normalizedQuery}"');
    debugPrint(
      '   Found ${notebookResult.chunks.length} chunks across ${collectionIds.length} collections',
    );

    for (var i = 0; i < notebookResult.chunks.length && i < 5; i++) {
      final c = notebookResult.chunks[i];
      final preview = c.content.length > 50
          ? '${c.content.substring(0, 50)}...'
          : c.content;
      debugPrint('   [$i] sim=${c.similarity.toStringAsFixed(3)}: $preview');
    }

    if (notebookResult.failedCollections.isNotEmpty) {
      debugPrint(
        '⚠️ Partial retrieval failure: ${notebookResult.failedCollections.join(', ')}',
      );
    }

    final relevantChunks = notebookResult.chunks
        .where(
          (chunk) =>
              chunk.similarity >= minSimilarityThreshold ||
              chunk.similarity == 0,
        )
        .toList(growable: false);

    if (relevantChunks.length < notebookResult.chunks.length) {
      debugPrint(
        '   🧹 Filtered ${notebookResult.chunks.length - relevantChunks.length} low similarity chunks (<$minSimilarityThreshold)',
      );
    }

    final hasRelevantContext = relevantChunks.isNotEmpty;
    final contextText = hasRelevantContext ? notebookResult.contextText : '';
    final estimatedTokens = notebookResult.estimatedTokens;

    debugPrint(
      '📊 RAG Context: $estimatedTokens tokens, ${notebookResult.chunks.length} chunks (Relevant: ${relevantChunks.length})',
    );

    final llmStopwatch = Stopwatch()..start();
    String response;

    if (mockLlm) {
      response = _generateMockResponse(
        chunks: notebookResult.chunks,
        estimatedTokens: estimatedTokens,
      );
    } else {
      response = await _generateOllamaResponse(
        query: text,
        contextText: contextText,
        retrievedChunks: notebookResult.chunks,
        hasRelevantContext: hasRelevantContext,
        language: language,
        onToken: onToken,
      );
    }

    llmStopwatch.stop();
    totalStopwatch.stop();

    return ChatProcessResult(
      response: response,
      chunks: notebookResult.chunks,
      estimatedTokens: estimatedTokens,
      queryType: understanding.type.name,
      ragSearchTime: ragSearchTime,
      llmGenerationTime: llmStopwatch.elapsed,
      totalTime: totalStopwatch.elapsed,
    );
  }

  String _generateMockResponse({
    required List<ChunkSearchResult> chunks,
    required int estimatedTokens,
  }) {
    if (chunks.isEmpty) {
      return '📭 No relevant documents found.\n\nPlease add some documents using the menu.';
    }

    final buffer = StringBuffer();
    buffer.writeln('📚 Found ${chunks.length} relevant chunks:');
    buffer.writeln('📊 Using ~$estimatedTokens tokens\n');

    for (var i = 0; i < chunks.length && i < 3; i++) {
      final chunk = chunks[i];
      final preview = chunk.content.length > 100
          ? '${chunk.content.substring(0, 100)}...'
          : chunk.content;
      buffer.writeln('${i + 1}. $preview\n');
    }

    buffer.writeln('---');
    buffer.writeln(
      '💡 This is a mock response. Install an LLM model for real answers.',
    );

    return buffer.toString();
  }

  Future<String> _generateOllamaResponse({
    required String query,
    required String contextText,
    required List<ChunkSearchResult> retrievedChunks,
    required bool hasRelevantContext,
    required ResponseLanguage language,
    void Function(String token)? onToken,
  }) async {
    final result = await responseService.generateResponse(
      query: query,
      contextText: contextText,
      retrievedChunks: retrievedChunks,
      hasRelevantContext: hasRelevantContext,
      chatHistory: chatHistory,
      language: language,
      onHistoryUpdate: (message) => chatHistory.add(message),
      onToken: onToken,
    );

    return result.response;
  }

  void clearHistory() {
    chatHistory.clear();
  }
}
