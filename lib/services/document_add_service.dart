/// Service for adding documents to the RAG engine.
/// Handles text and file (PDF/DOCX) document processing.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';

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

  DocumentAddService({required this.ragEngine});

  /// Add a text document to RAG
  Future<DocumentAddResult> addTextDocument(String text) async {
    final result = await ragEngine.addDocument(text);
    await ragEngine.rebuildIndex();

    final stats = await ragEngine.getStats();
    return DocumentAddResult(
      chunkCount: result.chunkCount,
      totalSources: stats.sourceCount.toInt(),
      totalChunks: stats.chunkCount.toInt(),
    );
  }

  /// Pick and add a file (PDF/DOCX) to RAG
  ///
  /// Returns null if user cancels file picker
  Future<DocumentAddResult?> pickAndAddFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'md', 'txt'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    if (file.path == null) return null;

    return addFile(file);
  }

  /// Add a file (PDF/DOCX/MD/TXT) to RAG
  Future<DocumentAddResult> addFile(PlatformFile file) async {
    if (file.path == null) {
      throw Exception('File path is null');
    }

    final extension = file.extension?.toLowerCase() ?? '';
    String text;

    if (extension == 'md' || extension == 'txt') {
      text = await File(file.path!).readAsString();
    } else {
      final bytes = await File(file.path!).readAsBytes();
      // Extract text from PDF/DOCX using mobile_rag_engine
      text = await extractTextFromDocument(fileBytes: bytes);
    }

    if (text.trim().isEmpty) {
      throw Exception('No text could be extracted from the file');
    }

    // Add to RAG with auto-chunking
    final addResult = await ragEngine.addDocument(text);
    await ragEngine.rebuildIndex();

    final stats = await ragEngine.getStats();
    return DocumentAddResult(
      chunkCount: addResult.chunkCount,
      totalSources: stats.sourceCount.toInt(),
      totalChunks: stats.chunkCount.toInt(),
      fileName: file.name,
    );
  }

  /// Get current stats
  Future<({int sources, int chunks})> getStats() async {
    final stats = await ragEngine.getStats();
    return (
      sources: stats.sourceCount.toInt(),
      chunks: stats.chunkCount.toInt(),
    );
  }
}
