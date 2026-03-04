import 'package:flutter/material.dart';

class NotebookEditorResult {
  final String title;
  final String emoji;
  final String colorHex;

  const NotebookEditorResult({
    required this.title,
    required this.emoji,
    required this.colorHex,
  });
}

Future<NotebookEditorResult?> showNotebookEditorDialog({
  required BuildContext context,
  String initialTitle = '',
  String initialEmoji = '📓',
  String initialColorHex = '#334155',
  String title = 'Edit Notebook',
  String confirmLabel = 'Save',
}) async {
  return showDialog<NotebookEditorResult>(
    context: context,
    builder: (context) => _NotebookEditorDialog(
      initialTitle: initialTitle,
      initialEmoji: initialEmoji,
      initialColorHex: initialColorHex,
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NotebookEditorDialog extends StatefulWidget {
  final String initialTitle;
  final String initialEmoji;
  final String initialColorHex;
  final String title;
  final String confirmLabel;

  const _NotebookEditorDialog({
    required this.initialTitle,
    required this.initialEmoji,
    required this.initialColorHex,
    required this.title,
    required this.confirmLabel,
  });

  @override
  State<_NotebookEditorDialog> createState() => _NotebookEditorDialogState();
}

class _NotebookEditorDialogState extends State<_NotebookEditorDialog> {
  static const _palette = <String>[
    '#334155',
    '#1E3A8A',
    '#0F766E',
    '#7C2D12',
    '#5B21B6',
    '#7F1D1D',
  ];

  late final TextEditingController _titleController;
  late final TextEditingController _emojiController;
  late String _selectedColorHex;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _emojiController = TextEditingController(text: widget.initialEmoji);
    _selectedColorHex = widget.initialColorHex;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final emoji = _emojiController.text.trim();

    if (title.isEmpty) return;

    Navigator.of(context).pop(
      NotebookEditorResult(
        title: title,
        emoji: emoji.isEmpty ? '📓' : emoji,
        colorHex: _selectedColorHex,
      ),
    );
  }

  Color _parseColor(String hex) {
    final normalized = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$normalized', radix: 16) ?? 0xFF334155;
    return Color(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Notebook name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emojiController,
            decoration: const InputDecoration(labelText: 'Emoji'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _palette
                .map((hex) {
                  final selected = _selectedColorHex == hex;
                  return InkWell(
                    onTap: () => setState(() => _selectedColorHex = hex),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _parseColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
