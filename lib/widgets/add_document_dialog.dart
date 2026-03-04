/// Dialog widget for adding documents to the RAG engine.
/// Supports both file upload (PDF/DOCX) and text input.

import 'package:flutter/material.dart';
import 'package:local_gemma_macos/services/document_add_service.dart';

/// Result returned when a document is added
class AddDocumentResult {
  final bool success;
  final int chunkCount;
  final String? fileName;
  final String? error;

  const AddDocumentResult({
    required this.success,
    this.chunkCount = 0,
    this.fileName,
    this.error,
  });
}

/// Shows the add document dialog as a bottom sheet
Future<AddDocumentResult?> showAddDocumentDialog({
  required BuildContext context,
  required DocumentAddService documentService,
  required String collectionId,
}) async {
  return showModalBottomSheet<AddDocumentResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => AddDocumentDialogContent(
      documentService: documentService,
      collectionId: collectionId,
    ),
  );
}

/// Content of the add document dialog
class AddDocumentDialogContent extends StatefulWidget {
  final DocumentAddService documentService;
  final String collectionId;

  const AddDocumentDialogContent({
    super.key,
    required this.documentService,
    required this.collectionId,
  });

  @override
  State<AddDocumentDialogContent> createState() =>
      _AddDocumentDialogContentState();
}

class _AddDocumentDialogContentState extends State<AddDocumentDialogContent> {
  final _textController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String _statusMessage = 'Ready';
  int? _progressDone;
  int? _progressTotal;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickAndAddFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = 'Picking file...';
      _progressDone = null;
      _progressTotal = null;
    });

    try {
      final result = await widget.documentService.pickAndAddFile(
        collectionId: widget.collectionId,
        onProgress: _handleProgress,
      );

      if (result == null) {
        // User cancelled
        setState(() => _isLoading = false);
        return;
      }

      if (mounted) {
        Navigator.pop(
          context,
          AddDocumentResult(
            success: true,
            chunkCount: result.chunkCount,
            fileName: result.fileName,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addTextDocument() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = 'Adding text document...';
      _progressDone = null;
      _progressTotal = null;
    });

    try {
      final result = await widget.documentService.addTextDocument(
        text,
        collectionId: widget.collectionId,
        onProgress: _handleProgress,
      );

      if (mounted) {
        Navigator.pop(
          context,
          AddDocumentResult(success: true, chunkCount: result.chunkCount),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _handleProgress(DocumentAddProgress progress) {
    if (!mounted) return;
    setState(() {
      _statusMessage = progress.message;
      _progressDone = progress.done;
      _progressTotal = progress.total;
    });
  }

  double? get _progressValue {
    final done = _progressDone;
    final total = _progressTotal;
    if (done == null || total == null || total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Document', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            if (_isLoading) ...[
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progressValue),
              const SizedBox(height: 12),
            ],

            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red[700])),
              ),
              const SizedBox(height: 16),
            ],

            // File picker button
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickAndAddFile,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: const Text('📁 Attach File (PDF, DOCX, MD, TXT)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),

            // Divider
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('OR', style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // Text input
            TextField(
              controller: _textController,
              maxLines: 6,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                hintText: 'Paste or type document content...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isLoading ? null : _addTextDocument,
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
