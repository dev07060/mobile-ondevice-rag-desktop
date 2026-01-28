/// Query understanding service for RAG.
/// Analyzes user intent, validates queries, and normalizes for consistent results.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Query type classification
enum QueryType {
  definition, // What is X? = asking for definition
  explanation, // Why? How? = asking for explanation
  factual, // When? Where? Who? How much? = factual query
  comparison, // A vs B, Difference = comparison
  listing, // List, Types = listing request
  summary, // Summary = summary request
  opinion, // Opinion (may reject)
  greeting, // Hello, Hi = greeting (reject)
  unclear, // Ambiguous input (reject)
  unknown, // Cannot determine
}

/// Result of query understanding analysis
class QueryUnderstanding {
  final bool isValid;
  final QueryType type;
  final String originalQuery;
  final String normalizedQuery;
  final List<String> keywords;
  final String? implicitIntent;
  final double confidence;
  final String? rejectionReason;

  const QueryUnderstanding({
    required this.isValid,
    required this.type,
    required this.originalQuery,
    required this.normalizedQuery,
    required this.keywords,
    this.implicitIntent,
    required this.confidence,
    this.rejectionReason,
  });

  /// Create an invalid/rejected query understanding
  factory QueryUnderstanding.invalid(String originalQuery, String reason) {
    return QueryUnderstanding(
      isValid: false,
      type: QueryType.unknown,
      originalQuery: originalQuery,
      normalizedQuery: '',
      keywords: [],
      confidence: 0.0,
      rejectionReason: reason,
    );
  }

  @override
  String toString() =>
      'QueryUnderstanding(valid: $isValid, type: ${type.name}, '
      'normalized: "$normalizedQuery", confidence: ${confidence.toStringAsFixed(2)}, '
      'keywords: $keywords)';
}

/// Service for understanding and analyzing user queries
class QueryUnderstandingService {
  final OllamaClient ollamaClient;
  final String? modelName;

  QueryUnderstandingService({required this.ollamaClient, this.modelName});

  // Localized error messages
  String get _msgEmptyQuery => 'Please enter a question.';
  String get _msgTooShort => 'Input is too short.';
  String get _msgMeaningful => 'Please enter a meaningful question.';
  String get _msgOnlyNumbers =>
      'Cannot understand a question with only numbers.';
  String get _msgNotUnderstood =>
      'I didn\'t understand the question. Please be more specific.';
  String get _msgGreeting =>
      'Hello! Please ask me a question about the documents.';
  String get _msgRephrase =>
      'I didn\'t understand the question. Please rephrase.';

  /// Analyze a user query to understand intent and validate
  Future<QueryUnderstanding> analyze(String query) async {
    final trimmedQuery = query.trim();

    // === Stage 1: Basic validity check ===
    final basicCheck = _basicValidityCheck(trimmedQuery);
    if (basicCheck != null) {
      debugPrint(
        '🚫 Query rejected (basic check): ${basicCheck.rejectionReason}',
      );
      return basicCheck;
    }

    // === Stage 2: LLM-based deep analysis ===
    final stopwatch = Stopwatch()..start();
    final llmResult = await _analyzeWithLLM(trimmedQuery);
    stopwatch.stop();

    debugPrint('🧠 Query Understanding (${stopwatch.elapsedMilliseconds}ms):');
    debugPrint('   Original: "$trimmedQuery"');
    debugPrint('   Type: ${llmResult.type.name}');
    debugPrint('   Normalized: "${llmResult.normalizedQuery}"');
    debugPrint('   Implicit Intent: ${llmResult.implicitIntent}');
    debugPrint('   Keywords: ${llmResult.keywords}');
    debugPrint('   Confidence: ${llmResult.confidence.toStringAsFixed(2)}');

    // === Stage 3: Confidence threshold check ===
    if (llmResult.confidence < 0.4) {
      return QueryUnderstanding.invalid(trimmedQuery, _msgNotUnderstood);
    }

    return llmResult;
  }

  /// Basic validity check before LLM analysis
  QueryUnderstanding? _basicValidityCheck(String query) {
    // Empty or too short
    if (query.isEmpty) {
      return QueryUnderstanding.invalid(query, _msgEmptyQuery);
    }

    if (query.length < 2) {
      return QueryUnderstanding.invalid(query, _msgTooShort);
    }

    // Only special characters or punctuation
    final onlySpecialChars = RegExp(r'^[\s\p{P}\p{S}]+$', unicode: true);
    if (onlySpecialChars.hasMatch(query)) {
      return QueryUnderstanding.invalid(query, _msgMeaningful);
    }

    // Only numbers
    final onlyNumbers = RegExp(r'^[\d\s.,]+$');
    if (onlyNumbers.hasMatch(query)) {
      return QueryUnderstanding.invalid(query, _msgOnlyNumbers);
    }

    return null; // Passed basic check
  }

  /// Use LLM to deeply analyze the query
  Future<QueryUnderstanding> _analyzeWithLLM(String query) async {
    final prompt =
        '''Analyze the user input. Respond ONLY in JSON.

Input: "$query"

Rules:
1. `normalized_query` and `keywords` MUST ONLY use words present in the input.
2. Do NOT invent new words not in the input.
3. Treat meaningless or ambiguous input as `is_valid: false`.

Analysis Fields:
1. is_valid: Is it a meaningful question/request? (true/false)
   - Ambiguous expressions like "I don't know", "What is it", "Hmm" → false
   - Clear topic or keyword → true
2. query_type: Question type
   - "definition": Asking for meaning (e.g., "What is X?", "Define X", or just "X")
   - "explanation": Asking for reason/method (e.g., "Why?", "How?")
   - "factual": Asking for facts (e.g., "When?", "Where?", "Who?", "How much?")
   - "comparison": Asking for comparison (e.g., "A vs B", "Difference")
   - "listing": Asking for a list (e.g., "List of...", "Types of...")
   - "summary": Asking for summary (e.g., "Summarize", "TLDR")
   - "greeting": Greeting (e.g., "Hello", "Hi")
   - "unclear": Cannot determine intent
3. implicit_intent: inferred intent (based ONLY on input words)
4. normalized_query: Query for search (use ONLY words from input!)
5. keywords: Key keywords extracted from input (Array, ONLY words from input!)
6. confidence: Analysis confidence (0.0-1.0)
   - Ambiguous: 0.3 or less
   - Clear: 0.7 or more

JSON Format:
{
  "is_valid": true/false,
  "query_type": "...",
  "implicit_intent": "...",
  "normalized_query": "only words from input",
  "keywords": ["words", "from", "input"],
  "confidence": 0.0-1.0
}''';

    try {
      final response = await ollamaClient.generateCompletion(
        request: GenerateCompletionRequest(
          model: modelName ?? 'gemma3:4b',
          prompt: prompt,
          options: const RequestOptions(temperature: 0.0, numPredict: 200),
        ),
      );

      final responseText = response.response?.trim() ?? '';
      debugPrint('🤖 LLM Analysis Response: $responseText');

      return _parseLLMResponse(query, responseText);
    } catch (e) {
      debugPrint('❌ LLM analysis failed: $e');
      // Fallback: treat as simple query
      return QueryUnderstanding(
        isValid: true,
        type: QueryType.definition,
        originalQuery: query,
        normalizedQuery: query,
        keywords: [query],
        confidence: 0.5,
      );
    }
  }

  /// Parse LLM response into QueryUnderstanding
  QueryUnderstanding _parseLLMResponse(
    String originalQuery,
    String responseText,
  ) {
    try {
      // Extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(responseText);
      if (jsonMatch == null) {
        debugPrint('⚠️ No JSON found in LLM response');
        return _fallbackUnderstanding(originalQuery);
      }

      // Sanitize and parse JSON
      String jsonStr = jsonMatch.group(0)!;
      jsonStr = jsonStr
          .replaceAll(''', "'")
          .replaceAll(''', "'")
          .replaceAll('"', '"')
          .replaceAll('"', '"')
          .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final isValid = json['is_valid'] as bool? ?? true;
      final queryTypeStr =
          (json['query_type'] as String?)?.toLowerCase() ?? 'unknown';
      final implicitIntent = json['implicit_intent'] as String?;
      final normalizedQuery =
          (json['normalized_query'] as String?) ?? originalQuery;
      final keywordsList = json['keywords'] as List<dynamic>? ?? [];
      final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.5;

      // Map query type string to enum
      final queryType = switch (queryTypeStr) {
        'definition' => QueryType.definition,
        'explanation' => QueryType.explanation,
        'factual' => QueryType.factual,
        'comparison' => QueryType.comparison,
        'listing' => QueryType.listing,
        'summary' => QueryType.summary,
        'greeting' => QueryType.greeting,
        'opinion' => QueryType.opinion,
        'unclear' => QueryType.unclear,
        _ => QueryType.unknown,
      };

      // Reject greetings and unclear queries
      if (queryType == QueryType.greeting) {
        return QueryUnderstanding.invalid(originalQuery, _msgGreeting);
      }

      if (queryType == QueryType.unclear || queryType == QueryType.unknown) {
        return QueryUnderstanding.invalid(originalQuery, _msgNotUnderstood);
      }

      if (!isValid) {
        return QueryUnderstanding.invalid(originalQuery, _msgRephrase);
      }

      return QueryUnderstanding(
        isValid: true,
        type: queryType,
        originalQuery: originalQuery,
        normalizedQuery: normalizedQuery,
        keywords: keywordsList.map((k) => k.toString()).toList(),
        implicitIntent: implicitIntent,
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to parse LLM response: $e');
      return _fallbackUnderstanding(originalQuery);
    }
  }

  /// Fallback when LLM parsing fails
  QueryUnderstanding _fallbackUnderstanding(String query) {
    return QueryUnderstanding(
      isValid: true,
      type: QueryType.definition,
      originalQuery: query,
      normalizedQuery: query,
      keywords: _extractSimpleKeywords(query),
      confidence: 0.5,
    );
  }

  /// Simple keyword extraction fallback
  List<String> _extractSimpleKeywords(String query) {
    // Remove punctuation and common stop words (simplified)
    final cleaned = query
        .replaceAll(RegExp(r'[?？!！.,。，]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned.split(' ').where((w) => w.length > 1).take(5).toList();
  }
}
