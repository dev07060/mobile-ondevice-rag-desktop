// test/analyze_topic_suggestion_test.dart
//
// Diagnostic test to analyze topic suggestion failure root cause
// Run with: dart test test/analyze_topic_suggestion_test.dart --reporter expanded

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:ollama_dart/ollama_dart.dart';

/// Run analysis to understand topic suggestion failures
void main() async {
  debugPrint('=' * 70);
  debugPrint('📊 TOPIC SUGGESTION FAILURE ANALYSIS');
  debugPrint('=' * 70);

  // DB path - same as app uses
  final homeDir = Platform.environment['HOME']!;
  final dbPath =
      '$homeDir/Library/Containers/com.example.localGemmaMacos/Data/Documents/local_gemma_rag.db';

  // Check if DB exists
  if (!File(dbPath).existsSync()) {
    debugPrint('❌ Database not found at: $dbPath');
    debugPrint('   Please run the app first to create the database.');
    return;
  }

  debugPrint('📁 Using DB: $dbPath\n');

  final ragService = SourceRagService(
    dbPath: dbPath,
    maxChunkChars: 500,
    overlapChars: 50,
  );
  await ragService.init();
  debugPrint('✅ RAG service initialized\n');

  // 1. Get all chunks from database
  debugPrint('📚 STEP 1: Loading all chunks from database...');
  debugPrint('-' * 50);

  final allChunks = await _loadAllChunksFromService(ragService);
  debugPrint('   Total chunks: ${allChunks.length}');

  if (allChunks.isEmpty) {
    debugPrint('❌ No chunks found in database.');
    return;
  }

  // 2. Analyze chunk topics
  debugPrint('\n📋 STEP 2: Analyzing chunk content topics...');
  debugPrint('-' * 50);

  // Extract key topics by looking at chunk content
  final Set<String> allKeywords = {};
  for (final chunk in allChunks) {
    // Simple keyword extraction - look for nouns and key phrases
    final words = chunk.content
        .replaceAll(RegExp(r'[^\w\s가-힣]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toSet();
    allKeywords.addAll(words);
  }

  // Show sample chunks
  debugPrint('   Sample chunk contents (first 5):');
  for (var i = 0; i < allChunks.length && i < 5; i++) {
    final preview = allChunks[i].content.length > 100
        ? '${allChunks[i].content.substring(0, 100)}...'
        : allChunks[i].content;
    debugPrint('   [$i] ${preview.replaceAll('\n', ' ')}');
  }

  debugPrint('\n   Unique keywords extracted: ${allKeywords.length}');
  debugPrint('   Sample keywords: ${allKeywords.take(30).join(', ')}');

  // 3. Simulate LLM question generation
  debugPrint('\n🤖 STEP 3: Generating questions via LLM...');
  debugPrint('-' * 50);

  final ollamaClient = OllamaClient();

  // Sample chunks (same logic as TopicSuggestionService)
  final sampledChunks = _sampleChunks(allChunks, 15);
  final sampleText = sampledChunks.map((c) => c.content).join('\n\n---\n\n');

  // Truncate like the service does
  final truncatedText = sampleText.length > 4000
      ? '${sampleText.substring(0, 4000)}...'
      : sampleText;

  debugPrint('   Sampled ${sampledChunks.length} chunks for analysis');
  debugPrint('   Total sample text length: ${truncatedText.length} chars');

  // Show sampled chunk text for debugging
  debugPrint('\n   📜 SAMPLED CHUNK TEXT (for LLM):');
  debugPrint('   ${'=' * 60}');
  debugPrint(truncatedText);
  debugPrint('   ${'=' * 60}');

  // Generate questions
  final candidateCount = 6;
  final prompt =
      '''아래는 지식 베이스에 저장된 문서들의 샘플입니다. 
이 내용을 분석하여 사용자가 물어볼 만한 유용한 질문 $candidateCount개를 생성해주세요.

규칙:
1. 질문은 반드시 아래 문서에서 직접적으로 답할 수 있는 내용이어야 합니다.
2. 문서에 명시적으로 언급된 사실, 데이터, 개념에 대해 질문하세요.
3. 문서에 없는 외부 정보를 필요로 하는 질문은 피하세요.
4. 질문은 간결하게 작성하세요 (1-2문장).
5. 질문은 한국어로 작성해주세요 (문서가 한국어인 경우).

문서 샘플:
$truncatedText

JSON 형식으로만 응답하세요:
[
  {"topic": "주제1", "question": "질문1?"},
  {"topic": "주제2", "question": "질문2?"}
]''';

  debugPrint('\n   🔄 Calling Ollama for question generation...');

  try {
    final response = await ollamaClient.generateCompletion(
      request: GenerateCompletionRequest(
        model: 'gemma3:4b',
        prompt: prompt,
        options: const RequestOptions(temperature: 0.5, numPredict: 800),
      ),
    );

    final responseText = response.response?.trim() ?? '';
    debugPrint('\n   📝 LLM Response:');
    debugPrint('   ${responseText.replaceAll('\n', '\n   ')}');

    // Parse questions
    final questions = _parseQuestions(responseText);
    debugPrint('\n   Parsed ${questions.length} questions');

    // 4. Validate each question
    debugPrint('\n🔍 STEP 4: Validating questions with RAG search...');
    debugPrint('-' * 50);

    // Check model/tokenizer files for validation search path
    debugPrint('   🔄 Checking RAG runtime assets...');
    final modelPath = '${Directory.current.path}/assets/model.onnx';
    final tokenizerPath = '${Directory.current.path}/assets/tokenizer.json';

    if (!File(modelPath).existsSync() || !File(tokenizerPath).existsSync()) {
      debugPrint('   ❌ Model or tokenizer not found');
      debugPrint('      Model: $modelPath');
      debugPrint('      Tokenizer: $tokenizerPath');
      debugPrint('   Skipping validation...');
      return;
    }

    // Validate each question
    for (final q in questions) {
      debugPrint('\n   📌 Question: "${q['question']}"');
      debugPrint('      Topic: ${q['topic']}');

      // Search for the question
      final result = await ragService.search(
        q['question']!,
        topK: 5,
        tokenBudget: 500,
        adjacentChunks: 0,
      );

      debugPrint('      RAG Results:');

      if (result.chunks.isEmpty) {
        debugPrint('      ❌ NO CHUNKS FOUND');
        continue;
      }

      // Check if question keywords appear in chunks
      final questionWords = q['question']!
          .replaceAll(RegExp(r'[^\w가-힣]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 2)
          .toSet();

      for (var i = 0; i < result.chunks.length && i < 5; i++) {
        final chunk = result.chunks[i];
        final preview = chunk.content.length > 80
            ? '${chunk.content.substring(0, 80)}...'
            : chunk.content;

        // Count matching keywords
        final chunkWords = chunk.content
            .replaceAll(RegExp(r'[^\w가-힣]'), ' ')
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .toSet();
        final matchingWords = questionWords
            .where((w) => chunkWords.contains(w.toLowerCase()))
            .toList();

        final matchIndicator = matchingWords.isEmpty
            ? '❌ NO MATCH'
            : '✅ ${matchingWords.length} matches (${matchingWords.take(3).join(', ')})';

        debugPrint(
          '      [$i] sim=${chunk.similarity.toStringAsFixed(3)}: '
          '${preview.replaceAll('\n', ' ')}',
        );
        debugPrint('          $matchIndicator');
      }

      // Analysis
      final bestScore = result.chunks.isNotEmpty
          ? result.chunks
                .map((c) => c.similarity)
                .reduce((a, b) => a > b ? a : b)
          : 0.0;
      final highQualityCount = result.chunks
          .where((c) => c.similarity >= 0.5)
          .length;

      if (bestScore >= 0.5 && highQualityCount >= 2) {
        debugPrint(
          '      ✅ PASSES validation (score: ${bestScore.toStringAsFixed(3)}, quality chunks: $highQualityCount)',
        );
      } else {
        debugPrint(
          '      ❌ FAILS validation (score: ${bestScore.toStringAsFixed(3)}, quality chunks: $highQualityCount)',
        );
      }
    }
  } catch (e, st) {
    debugPrint('   ❌ Error: $e');
    debugPrint('   Stack: $st');
  }

  debugPrint('\n${'=' * 70}');
  debugPrint('📊 ANALYSIS COMPLETE');
  debugPrint('=' * 70);
}

Future<List<ChunkForReembedding>> _loadAllChunksFromService(
  SourceRagService ragService,
) async {
  final sources = await ragService.listSources();
  final chunks = <ChunkForReembedding>[];
  var syntheticChunkId = 1;

  for (final source in sources) {
    final sourceChunks = await ragService.getSourceChunks(
      sourceId: source.id.toInt(),
    );
    for (final content in sourceChunks) {
      final trimmed = content.trim();
      if (trimmed.isEmpty) continue;
      chunks.add(
        ChunkForReembedding(chunkId: syntheticChunkId, content: trimmed),
      );
      syntheticChunkId += 1;
    }
  }

  return chunks;
}

/// Sample chunks (same logic as TopicSuggestionService)
List<ChunkForReembedding> _sampleChunks(
  List<ChunkForReembedding> chunks,
  int sampleSize,
) {
  if (chunks.length <= sampleSize) {
    return chunks;
  }

  // Shuffle
  final shuffled = List<ChunkForReembedding>.from(chunks);
  shuffled.shuffle();

  // Sort by length (prefer longer chunks)
  shuffled.sort((a, b) => b.content.length.compareTo(a.content.length));

  // Take top half by length, shuffle again
  final topHalf = shuffled.take((shuffled.length / 2).ceil()).toList();
  topHalf.shuffle();

  return topHalf.take(sampleSize).toList();
}

/// Parse LLM response into questions
List<Map<String, String>> _parseQuestions(String responseText) {
  try {
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(responseText);
    if (jsonMatch == null) {
      debugPrint('   ⚠️ No JSON array found in response');
      return [];
    }

    final jsonStr = jsonMatch.group(0)!;

    // Manual JSON parsing since we don't have dart:convert in test
    final questions = <Map<String, String>>[];
    final itemRegex = RegExp(
      r'\{\s*"topic"\s*:\s*"([^"]+)"\s*,\s*"question"\s*:\s*"([^"]+)"\s*\}',
    );

    for (final match in itemRegex.allMatches(jsonStr)) {
      questions.add({'topic': match.group(1)!, 'question': match.group(2)!});
    }

    return questions;
  } catch (e) {
    debugPrint('   ⚠️ Failed to parse response: $e');
    return [];
  }
}
