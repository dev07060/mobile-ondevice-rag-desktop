import 'package:mobile_rag_engine/mobile_rag_engine.dart';

/// Query intent types for RAG parameter optimization
enum QueryIntent {
  summary, // Summary, recap, core points → fewer chunks, lower token budget
  definition, // What is, meaning, define → precise definition
  broad, // All, list, entirety → many chunks
  detail, // Detail, why, how → medium chunks
  general, // Basic question
}

/// Analysis result from LLM intent classification
class QueryAnalysis {
  final QueryIntent intent;
  final int adjacentChunks;
  final int tokenBudget;
  final int topK;
  final String refinedQuery; // Search keyword refined by LLM

  const QueryAnalysis({
    required this.intent,
    required this.adjacentChunks,
    required this.tokenBudget,
    required this.topK,
    required this.refinedQuery,
  });

  /// Default fallback analysis
  factory QueryAnalysis.defaultFor(String query) {
    return QueryAnalysis(
      intent: QueryIntent.general,
      adjacentChunks: 2,
      tokenBudget: 2000,
      topK: 10,
      refinedQuery: query,
    );
  }

  @override
  String toString() =>
      'QueryAnalysis(intent: $intent, adjacent: $adjacentChunks, budget: $tokenBudget, topK: $topK, query: "$refinedQuery")';
}

/// Message model for chat
class ChatMessage {
  String content; // Mutable for streaming updates
  final bool isUser;
  final DateTime timestamp;
  final List<ChunkSearchResult>? retrievedChunks;
  final int? tokensUsed;
  final double? compressionRatio; // 0.0-1.0, lower = more compressed
  final int? originalTokens; // Before compression

  // Animation tracking - mutable to persist across widget rebuilds
  bool hasAnimated = false;

  // Streaming state
  bool isStreaming;

  // Processing metadata for UI display
  final String? queryType; // explanation, definition, factual, etc.

  // Timing metrics for debug
  final Duration? ragSearchTime;
  final Duration? llmGenerationTime;
  final Duration? totalTime;

  ChatMessage({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
    this.retrievedChunks,
    this.tokensUsed,
    this.compressionRatio,
    this.originalTokens,
    this.queryType,
    this.ragSearchTime,
    this.llmGenerationTime,
    this.totalTime,
    this.hasAnimated = false,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a copy with updated fields (for streaming updates)
  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<ChunkSearchResult>? retrievedChunks,
    int? tokensUsed,
    String? queryType,
    Duration? ragSearchTime,
    Duration? llmGenerationTime,
    Duration? totalTime,
  }) {
    return ChatMessage(
      content: content ?? this.content,
      isUser: isUser,
      timestamp: timestamp,
      retrievedChunks: retrievedChunks ?? this.retrievedChunks,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      compressionRatio: compressionRatio,
      originalTokens: originalTokens,
      queryType: queryType ?? this.queryType,
      ragSearchTime: ragSearchTime ?? this.ragSearchTime,
      llmGenerationTime: llmGenerationTime ?? this.llmGenerationTime,
      totalTime: totalTime ?? this.totalTime,
      hasAnimated: hasAnimated,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
