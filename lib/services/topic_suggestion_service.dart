/// Service for generating topic-based question suggestions from the knowledge base.
/// Uses LLM analysis and RAG validation to ensure answerable suggestions.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:local_gemma_macos/services/ollama_response_service.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// A suggested question with its source topic and validation score
class SuggestedQuestion {
  final String question;
  final String topic;
  final double? validationScore; // Highest similarity from RAG validation

  const SuggestedQuestion({
    required this.question,
    required this.topic,
    this.validationScore,
  });

  @override
  String toString() =>
      'SuggestedQuestion(topic: $topic, question: $question, score: $validationScore)';
}

/// Service for generating topic-based question suggestions
class TopicSuggestionService {
  // Cached suggestions
  List<SuggestedQuestion>? _cachedSuggestions;
  DateTime? _cacheTime;
  String? _cacheScopeKey;

  // Cache duration (regenerate if older than 1 hour)
  static const Duration _cacheDuration = Duration(hours: 1);

  // Validation threshold: minimum similarity score for a valid question
  static const double _validationThreshold = 0.5;

  // Minimum number of high-quality chunks needed
  static const int _minValidChunks = 2;

  // Avoid suggestion spinner getting stuck forever.
  static const Duration _suggestionLlmTimeout = Duration(seconds: 25);

  /// Get cached suggestions if available and not expired
  List<SuggestedQuestion>? getCachedSuggestions(String scopeKey) {
    if (_cachedSuggestions == null || _cacheTime == null) {
      return null;
    }
    if (_cacheScopeKey != scopeKey) {
      return null;
    }

    final now = DateTime.now();
    if (now.difference(_cacheTime!) > _cacheDuration) {
      return null; // Cache expired
    }

    return _cachedSuggestions;
  }

  /// Invalidate the cache (call when new documents are added)
  void invalidateCache() {
    _cachedSuggestions = null;
    _cacheTime = null;
    _cacheScopeKey = null;
    debugPrint('🔄 Topic suggestions cache invalidated');
  }

  /// Generate topic-based question suggestions from the knowledge base
  ///
  /// This method:
  /// 1. Fetches all chunks from the database
  /// 2. Samples a subset of chunks for analysis
  /// 3. Uses LLM to extract topics and generate relevant questions
  /// 4. Validates each question with RAG search to ensure answerability
  Future<List<SuggestedQuestion>> generateSuggestions({
    required RagEngine ragEngine,
    required List<String> collectionIds,
    required OllamaClient ollamaClient,
    String? modelName,
    int maxSuggestions = 3,
    int sampleSize = 15,
    ResponseLanguage language = ResponseLanguage.english,
  }) async {
    final normalizedCollectionIds = collectionIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedCollectionIds.isEmpty) {
      return [];
    }

    final scopeKey =
        '${normalizedCollectionIds.join('|')}::${language.name}::${maxSuggestions}_$sampleSize';

    // Return cached if available
    final cached = getCachedSuggestions(scopeKey);
    if (cached != null && cached.isNotEmpty) {
      debugPrint('📋 Returning ${cached.length} cached suggestions');
      return cached;
    }

    debugPrint('🔍 Generating topic suggestions...');
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Get all chunks from database
      final statsByCollection = await Future.wait(
        normalizedCollectionIds.map(
          (id) => ragEngine.getStats(collectionId: id),
        ),
      );
      final totalChunks = statsByCollection.fold<int>(
        0,
        (sum, stats) => sum + stats.chunkCount.toInt(),
      );
      if (totalChunks == 0) {
        debugPrint('📭 No chunks in database, cannot generate suggestions');
        return [];
      }

      // 2. Get chunk contents for sampling
      final allChunks = await _loadChunksForSampling(
        ragEngine: ragEngine,
        collectionIds: normalizedCollectionIds,
      );

      if (allChunks.isEmpty) {
        debugPrint('📭 No chunk contents found');
        return [];
      }

      // 3. Sample chunks for topic analysis
      final sampledChunks = _sampleChunks(allChunks, sampleSize);
      final sampleText = sampledChunks
          .map((c) => c.content)
          .join('\n\n---\n\n');

      debugPrint('📊 Sampled ${sampledChunks.length} chunks for analysis');

      // 4. Generate MORE suggestions than needed (to have room after filtering)
      final candidateCount = maxSuggestions * 2; // Generate 2x to filter
      final candidates = await _generateWithLLM(
        ollamaClient: ollamaClient,
        modelName: modelName,
        sampleText: sampleText,
        maxSuggestions: candidateCount,
        language: language,
      );

      debugPrint('📝 Generated ${candidates.length} candidate questions');

      // 5. Validate each question with RAG search (Validation uses original query, so language doesn't matter for similarity check)
      final validatedSuggestions = await _validateQuestions(
        candidates: candidates,
        ragEngine: ragEngine,
        collectionIds: normalizedCollectionIds,
        maxValid: maxSuggestions,
      );

      stopwatch.stop();
      debugPrint(
        '✅ Validated ${validatedSuggestions.length}/${candidates.length} suggestions in ${stopwatch.elapsedMilliseconds}ms',
      );

      // 6. Cache results
      _cachedSuggestions = validatedSuggestions;
      _cacheTime = DateTime.now();
      _cacheScopeKey = scopeKey;

      return validatedSuggestions;
    } catch (e, stackTrace) {
      debugPrint('❌ Error generating suggestions: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Load all chunks using public APIs only.
  ///
  /// `getAllChunkIdsAndContents()` is a low-level raw API and is not exported
  /// by `mobile_rag_engine.dart`, so we compose equivalent data here.
  Future<List<ChunkForReembedding>> _loadChunksForSampling({
    required RagEngine ragEngine,
    required List<String> collectionIds,
  }) async {
    final chunks = <ChunkForReembedding>[];
    var syntheticChunkId = 1;

    for (final collectionId in collectionIds) {
      final sources = await ragEngine.listSources(collectionId: collectionId);
      for (final source in sources) {
        final sourceId = source.id.toInt();
        final sourceChunks = await ragEngine.getSourceChunks(sourceId);

        for (final content in sourceChunks) {
          final trimmed = content.trim();
          if (trimmed.isEmpty) continue;

          chunks.add(
            ChunkForReembedding(chunkId: syntheticChunkId, content: trimmed),
          );
          syntheticChunkId += 1;
        }
      }
    }

    return chunks;
  }

  /// Validate questions using RAG search to ensure they can be answered
  Future<List<SuggestedQuestion>> _validateQuestions({
    required List<SuggestedQuestion> candidates,
    required RagEngine ragEngine,
    required List<String> collectionIds,
    required int maxValid,
  }) async {
    final validatedList = <SuggestedQuestion>[];

    for (final candidate in candidates) {
      if (validatedList.length >= maxValid) break;

      try {
        final resultsByCollection = await Future.wait(
          collectionIds.map((collectionId) async {
            try {
              return await ragEngine.search(
                candidate.question,
                topK: 5,
                tokenBudget: 500,
                adjacentChunks: 0,
                collectionId: collectionId,
              );
            } catch (_) {
              return RagSearchResult(
                chunks: [],
                context: AssembledContext(
                  text: '',
                  includedChunks: [],
                  estimatedTokens: 0,
                  remainingBudget: 0,
                ),
              );
            }
          }),
        );
        final allChunks = resultsByCollection
            .expand((result) => result.chunks)
            .toList(growable: false);

        // Count chunks with high similarity
        final highQualityChunks = allChunks
            .where((c) => c.similarity >= _validationThreshold)
            .length;

        // Get best similarity score
        final bestScore = allChunks.isNotEmpty
            ? allChunks.map((c) => c.similarity).reduce((a, b) => a > b ? a : b)
            : 0.0;

        debugPrint(
          '🔍 Validating: "${candidate.question.substring(0, min(50, candidate.question.length))}..." → '
          'bestScore: ${bestScore.toStringAsFixed(3)}, highQuality: $highQualityChunks',
        );

        // Question is valid if it has enough high-quality matches
        if (highQualityChunks >= _minValidChunks &&
            bestScore >= _validationThreshold) {
          validatedList.add(
            SuggestedQuestion(
              question: candidate.question,
              topic: candidate.topic,
              validationScore: bestScore,
            ),
          );
          debugPrint('  ✅ PASSED validation');
        } else {
          debugPrint(
            '  ❌ FAILED validation (need $highQualityChunks >= $_minValidChunks chunks with sim >= $_validationThreshold)',
          );
        }
      } catch (e) {
        debugPrint('  ⚠️ Validation error: $e');
      }
    }

    // Sort by validation score (highest first)
    validatedList.sort(
      (a, b) => (b.validationScore ?? 0).compareTo(a.validationScore ?? 0),
    );

    return validatedList;
  }

  /// Sample chunks randomly, preferring diverse content
  List<ChunkForReembedding> _sampleChunks(
    List<ChunkForReembedding> chunks,
    int sampleSize,
  ) {
    if (chunks.length <= sampleSize) {
      return chunks;
    }

    // Shuffle and take sample
    final shuffled = List<ChunkForReembedding>.from(chunks);
    shuffled.shuffle(Random());

    // Take sample, preferring longer chunks (more content)
    shuffled.sort((a, b) => b.content.length.compareTo(a.content.length));

    // Take top half by length, then shuffle again for diversity
    final topHalf = shuffled.take((shuffled.length / 2).ceil()).toList();
    topHalf.shuffle(Random());

    return topHalf.take(sampleSize).toList();
  }

  /// Use LLM to analyze sample text and generate questions
  Future<List<SuggestedQuestion>> _generateWithLLM({
    required OllamaClient ollamaClient,
    String? modelName,
    required String sampleText,
    required int maxSuggestions,
    required ResponseLanguage language,
  }) async {
    // Truncate sample text if too long (keep within context window)
    final truncatedText = sampleText.length > 4000
        ? '${sampleText.substring(0, 4000)}...'
        : sampleText;

    // 🔍 DEBUG: Log sample text for analysis
    debugPrint('=' * 70);
    debugPrint(
      '📜 [DEBUG] SAMPLE TEXT SENT TO LLM (${truncatedText.length} chars):',
    );
    debugPrint('=' * 70);
    debugPrint(truncatedText);
    debugPrint('=' * 70);

    final String prompt;
    if (language == ResponseLanguage.korean) {
      prompt =
          '''Below is a sample of documents stored in the knowledge base.
Analyze this content and generate $maxSuggestions useful questions that a user might ask.

Rules:
1. Questions must be directly answerable from the documents below.
2. Ask about facts, data, and concepts explicitly mentioned in the documents.
3. Avoid questions that require external information not in the documents.
4. Keep questions concise (1-2 sentences).
5. Write questions in Korean (한국어).

Document sample:
$truncatedText

Respond ONLY in JSON format:
[
  {"topic": "주제1", "question": "질문1?"},
  {"topic": "주제2", "question": "질문2?"}
]''';
    } else {
      prompt =
          '''Below is a sample of documents stored in the knowledge base.
Analyze this content and generate $maxSuggestions useful questions that a user might ask.

Rules:
1. Questions must be directly answerable from the documents below.
2. Ask about facts, data, and concepts explicitly mentioned in the documents.
3. Avoid questions that require external information not in the documents.
4. Keep questions concise (1-2 sentences).
5. Write questions in English.

Document sample:
$truncatedText

Respond ONLY in JSON format:
[
  {"topic": "Topic1", "question": "Question1?"},
  {"topic": "Topic2", "question": "Question2?"}
]''';
    }

    try {
      final response = await ollamaClient
          .generateCompletion(
            request: GenerateCompletionRequest(
              model: modelName ?? 'gemma3:4b',
              prompt: prompt,
              options: const RequestOptions(
                temperature:
                    0.5, // Lower temperature for more grounded questions
                numPredict: 800, // More tokens for more questions
              ),
            ),
          )
          .timeout(_suggestionLlmTimeout);

      final responseText = response.response?.trim() ?? '';
      debugPrint('🤖 LLM response: $responseText');

      final questions = _parseResponse(responseText);

      // 🔍 DEBUG: Analyze keyword matching between questions and sample text
      debugPrint('=' * 70);
      debugPrint('🔬 [DEBUG] KEYWORD MATCHING ANALYSIS:');
      debugPrint('=' * 70);
      final sampleLower = truncatedText.toLowerCase();
      for (final q in questions) {
        final questionWords = q.question
            .replaceAll(RegExp(r'[^\w\s]'), ' ') // English regex only
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 2)
            .toSet();

        final matches = <String>[];
        final misses = <String>[];
        for (final word in questionWords) {
          if (sampleLower.contains(word.toLowerCase())) {
            matches.add(word);
          } else {
            misses.add(word);
          }
        }

        debugPrint('📌 Q: "${q.question}"');
        debugPrint('   Topic: ${q.topic}');
        debugPrint('   ✅ In sample: ${matches.join(", ")}');
        debugPrint(
          '   ❌ NOT in sample: ${misses.isEmpty ? "(all matched)" : misses.join(", ")}',
        );
        if (misses.isNotEmpty) {
          debugPrint(
            '   ⚠️ HALLUCINATION DETECTED: ${misses.length}/${questionWords.length} keywords missing',
          );
        }
        debugPrint('');
      }
      debugPrint('=' * 70);

      return questions;
    } catch (e) {
      debugPrint('❌ LLM call failed: $e');
      return [];
    }
  }

  /// Parse LLM response JSON into SuggestedQuestion list
  List<SuggestedQuestion> _parseResponse(String responseText) {
    try {
      // Find JSON array in response
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(responseText);
      if (jsonMatch == null) {
        debugPrint('⚠️ No JSON array found in response');
        return [];
      }

      String jsonStr = jsonMatch.group(0)!;

      // Sanitize JSON string: remove control characters and fix smart quotes
      jsonStr = jsonStr
          .replaceAll(''', "'")  // Left single quote
          .replaceAll(''', "'") // Right single quote
          .replaceAll('"', '"') // Left double quote
          .replaceAll('"', '"') // Right double quote
          .replaceAll('–', '-') // En dash
          .replaceAll('—', '-') // Em dash
          .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ''); // Remove control chars

      final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;

      return jsonList
          .map((item) {
            final map = item as Map<String, dynamic>;
            return SuggestedQuestion(
              topic: (map['topic'] as String?) ?? '',
              question: (map['question'] as String?) ?? '',
            );
          })
          .where((q) => q.question.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to parse response: $e');
      return [];
    }
  }
}
