/// Service for adding documents to the RAG engine.
/// Handles text and file (PDF/DOCX) document processing.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

enum DocumentAddStage {
  readingFile,
  extractingText,
  embeddingChunks,
  rebuildingIndex,
  completed,
}

class DocumentAddProgress {
  final DocumentAddStage stage;
  final String message;
  final int? done;
  final int? total;

  const DocumentAddProgress({
    required this.stage,
    required this.message,
    this.done,
    this.total,
  });
}

typedef DocumentAddProgressCallback =
    void Function(DocumentAddProgress progress);

/// Result of adding a document
class DocumentAddResult {
  final int chunkCount;
  final int totalSources;
  final int totalChunks;
  final String? fileName;

  const DocumentAddResult({
    required this.chunkCount,
    required this.totalSources,
    required this.totalChunks,
    this.fileName,
  });
}

/// Service for document management in RAG
class DocumentAddService {
  final RagEngine ragEngine;
  static const Duration _pdfExtractionTimeout = Duration(seconds: 90);
  static const Duration _docxExtractionTimeout = Duration(seconds: 60);

  DocumentAddService({required this.ragEngine});

  /// Add a text document to RAG
  Future<DocumentAddResult> addTextDocument(
    String text, {
    required String collectionId,
    DocumentAddProgressCallback? onProgress,
  }) async {
    final totalStopwatch = Stopwatch()..start();

    final result = await ragEngine.addDocument(
      text,
      collectionId: collectionId,
      onProgress: (done, total) {
        onProgress?.call(
          DocumentAddProgress(
            stage: DocumentAddStage.embeddingChunks,
            message: 'Embedding chunks... ($done/$total)',
            done: done,
            total: total,
          ),
        );
      },
    );

    onProgress?.call(
      const DocumentAddProgress(
        stage: DocumentAddStage.rebuildingIndex,
        message: 'Rebuilding index...',
      ),
    );
    await ragEngine.rebuildIndex(collectionId: collectionId);

    final stats = await ragEngine.getStats(collectionId: collectionId);
    totalStopwatch.stop();
    debugPrint(
      '⏱️ [DocumentAddService] Text document add completed in ${totalStopwatch.elapsedMilliseconds}ms',
    );

    onProgress?.call(
      const DocumentAddProgress(
        stage: DocumentAddStage.completed,
        message: 'Completed',
      ),
    );

    return DocumentAddResult(
      chunkCount: result.chunkCount,
      totalSources: stats.sourceCount.toInt(),
      totalChunks: stats.chunkCount.toInt(),
    );
  }

  /// Pick and add a file (PDF/DOCX) to RAG
  ///
  /// Returns null if user cancels file picker
  Future<DocumentAddResult?> pickAndAddFile({
    required String collectionId,
    DocumentAddProgressCallback? onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'md', 'txt'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    if (file.path == null) return null;

    return addFile(file, collectionId: collectionId, onProgress: onProgress);
  }

  /// Add a file (PDF/DOCX/MD/TXT) to RAG
  Future<DocumentAddResult> addFile(
    PlatformFile file, {
    required String collectionId,
    DocumentAddProgressCallback? onProgress,
  }) async {
    if (file.path == null) {
      throw Exception('File path is null');
    }

    final totalStopwatch = Stopwatch()..start();
    final extension = file.extension?.toLowerCase() ?? '';
    String text;

    onProgress?.call(
      DocumentAddProgress(
        stage: DocumentAddStage.readingFile,
        message: 'Reading file: ${file.name}',
      ),
    );

    if (extension == 'md' || extension == 'txt') {
      text = await File(file.path!).readAsString();
    } else {
      final extractionStopwatch = Stopwatch()..start();
      final bytes = await File(file.path!).readAsBytes();

      onProgress?.call(
        DocumentAddProgress(
          stage: DocumentAddStage.extractingText,
          message: 'Extracting text from ${extension.toUpperCase()}...',
        ),
      );

      if (extension == 'pdf') {
        text = await extractTextFromPdf(fileBytes: bytes).timeout(
          _pdfExtractionTimeout,
          onTimeout: () {
            throw TimeoutException(
              'PDF text extraction timed out after ${_pdfExtractionTimeout.inSeconds}s',
            );
          },
        );
      } else if (extension == 'docx') {
        text = await extractTextFromDocx(fileBytes: bytes).timeout(
          _docxExtractionTimeout,
          onTimeout: () {
            throw TimeoutException(
              'DOCX text extraction timed out after ${_docxExtractionTimeout.inSeconds}s',
            );
          },
        );
      } else {
        text = await extractTextFromDocument(fileBytes: bytes);
      }

      extractionStopwatch.stop();
      debugPrint(
        '⏱️ [DocumentAddService] Extraction(${file.name}) in ${extractionStopwatch.elapsedMilliseconds}ms',
      );
    }

    if (text.trim().isEmpty) {
      throw Exception('No text could be extracted from the file');
    }

    onProgress?.call(
      const DocumentAddProgress(
        stage: DocumentAddStage.embeddingChunks,
        message: 'Chunking and embedding...',
      ),
    );

    // Add to RAG with auto-chunking
    final addResult = await ragEngine.addDocument(
      text,
      collectionId: collectionId,
      onProgress: (done, total) {
        onProgress?.call(
          DocumentAddProgress(
            stage: DocumentAddStage.embeddingChunks,
            message: 'Embedding chunks... ($done/$total)',
            done: done,
            total: total,
          ),
        );
      },
    );

    onProgress?.call(
      const DocumentAddProgress(
        stage: DocumentAddStage.rebuildingIndex,
        message: 'Rebuilding index...',
      ),
    );
    await ragEngine.rebuildIndex(collectionId: collectionId);

    final stats = await ragEngine.getStats(collectionId: collectionId);
    totalStopwatch.stop();
    debugPrint(
      '⏱️ [DocumentAddService] Add file(${file.name}) completed in ${totalStopwatch.elapsedMilliseconds}ms, chunks=${addResult.chunkCount}',
    );

    onProgress?.call(
      const DocumentAddProgress(
        stage: DocumentAddStage.completed,
        message: 'Completed',
      ),
    );

    return DocumentAddResult(
      chunkCount: addResult.chunkCount,
      totalSources: stats.sourceCount.toInt(),
      totalChunks: stats.chunkCount.toInt(),
      fileName: file.name,
    );
  }

  /// Get current stats
  Future<({int sources, int chunks})> getStats({
    List<String>? collectionIds,
    String? collectionId,
  }) async {
    if (collectionIds != null && collectionIds.isNotEmpty) {
      var totalSources = 0;
      var totalChunks = 0;
      final uniqueCollectionIds = collectionIds.toSet();
      for (final id in uniqueCollectionIds) {
        try {
          final stats = await ragEngine.getStats(collectionId: id);
          totalSources += stats.sourceCount.toInt();
          totalChunks += stats.chunkCount.toInt();
        } catch (e) {
          debugPrint('⚠️ Failed to get stats for $id: $e');
        }
      }
      return (sources: totalSources, chunks: totalChunks);
    }

    try {
      final stats = await ragEngine.getStats(collectionId: collectionId);
      return (
        sources: stats.sourceCount.toInt(),
        chunks: stats.chunkCount.toInt(),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to get stats for $collectionId: $e');
      return (sources: 0, chunks: 0);
    }
  }
}
