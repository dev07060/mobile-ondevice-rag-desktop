import 'package:ollama_dart/ollama_dart.dart';

import 'package:local_gemma_macos/models/chat_models.dart';

class NotebookChatSession {
  final String notebookId;
  final List<ChatMessage> messages;
  final List<Message> chatHistory;
  final Set<String> selectedCollectionIds;

  NotebookChatSession({
    required this.notebookId,
    List<ChatMessage>? messages,
    List<Message>? chatHistory,
    Set<String>? selectedCollectionIds,
  }) : messages = messages ?? <ChatMessage>[],
       chatHistory = chatHistory ?? <Message>[],
       selectedCollectionIds = selectedCollectionIds ?? <String>{};

  NotebookChatSession copyWith({
    List<ChatMessage>? messages,
    List<Message>? chatHistory,
    Set<String>? selectedCollectionIds,
  }) {
    return NotebookChatSession(
      notebookId: notebookId,
      messages: messages ?? this.messages,
      chatHistory: chatHistory ?? this.chatHistory,
      selectedCollectionIds:
          selectedCollectionIds ?? this.selectedCollectionIds,
    );
  }
}
