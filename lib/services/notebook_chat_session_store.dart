import 'package:local_gemma_macos/models/notebook_chat_session.dart';

class NotebookChatSessionStore {
  final Map<String, NotebookChatSession> _sessions =
      <String, NotebookChatSession>{};

  NotebookChatSession getOrCreate({
    required String notebookId,
    required Set<String> initialSelectedCollectionIds,
  }) {
    return _sessions.putIfAbsent(
      notebookId,
      () => NotebookChatSession(
        notebookId: notebookId,
        selectedCollectionIds: initialSelectedCollectionIds,
      ),
    );
  }

  void save(NotebookChatSession session) {
    _sessions[session.notebookId] = session;
  }

  void clearNotebook(String notebookId) {
    _sessions.remove(notebookId);
  }

  void clearAll() {
    _sessions.clear();
  }
}
