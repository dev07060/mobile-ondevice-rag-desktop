/// Main chat screen with RAG-powered responses.
/// Uses RagChatService for message processing and extracted widgets for UI.

import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:ollama_dart/ollama_dart.dart';

import 'package:local_gemma_macos/models/chat_models.dart';
import 'package:local_gemma_macos/models/notebook_chat_session.dart';
import 'package:local_gemma_macos/models/notebook_models.dart';
import 'package:local_gemma_macos/services/document_add_service.dart';
import 'package:local_gemma_macos/services/notebook_chat_session_store.dart';
import 'package:local_gemma_macos/services/notebook_rag_service.dart';
import 'package:local_gemma_macos/services/notebook_warmup_coordinator.dart';
import 'package:local_gemma_macos/services/ollama_response_service.dart';
import 'package:local_gemma_macos/services/query_understanding_service.dart';
import 'package:local_gemma_macos/services/rag_chat_service.dart';
import 'package:local_gemma_macos/services/topic_suggestion_service.dart';
import 'package:local_gemma_macos/widgets/add_document_dialog.dart';
import 'package:local_gemma_macos/widgets/chat_input_area.dart';
import 'package:local_gemma_macos/widgets/chunk_detail_sidebar.dart';
import 'package:local_gemma_macos/widgets/document_style_response.dart';
import 'package:local_gemma_macos/widgets/knowledge_graph_panel.dart';
import 'package:local_gemma_macos/widgets/rag_chat_appbar.dart';
import 'package:local_gemma_macos/widgets/slash_command_overlay.dart';
import 'package:local_gemma_macos/widgets/suggestion_chips.dart';

class RagChatScreen extends StatefulWidget {
  final NotebookModel notebook;
  final NotebookChatSessionStore sessionStore;
  final bool mockLlm;
  final String? modelName;

  const RagChatScreen({
    super.key,
    required this.notebook,
    required this.sessionStore,
    this.mockLlm = false,
    this.modelName,
  });

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Notebook context
  late NotebookModel _notebook;
  NotebookChatSession? _session;
  Set<String> _selectedCollectionIds = <String>{};

  // Messages
  List<ChatMessage> _messages = <ChatMessage>[];

  // Services
  RagChatService? _chatService;
  DocumentAddService? _documentService;
  QueryUnderstandingService? _queryService;
  OllamaResponseService? _ollamaResponseService;
  NotebookWarmupCoordinator? _warmupCoordinator;
  NotebookRagService? _notebookRagService;
  final OllamaClient _ollamaClient = OllamaClient();
  List<Message> _chatHistory = <Message>[];

  // Topic suggestions
  final TopicSuggestionService _topicService = TopicSuggestionService();
  List<SuggestedQuestion> _suggestedQuestions = [];
  bool _isLoadingSuggestions = false;

  // UI State
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isGenerating = false;
  String _status = 'Initializing...';
  int _totalChunks = 0;
  int _totalSources = 0;

  // Settings
  bool _showDebugInfo = true;
  bool _showGraphPanel = false;
  bool _isSuggestionsExpanded = true;
  int _compressionLevel = 1;
  ResponseLanguage _responseLanguage = ResponseLanguage.english;
  final double _minSimilarityThreshold = 0.35;

  // Graph panel state
  ChunkSearchResult? _selectedChunk;
  String? _lastQuery;
  List<ChunkSearchResult> _lastChunks = [];

  // Slash command state
  bool _showSlashPopup = false;
  String _slashFilter = '';
  String? _currentIntentType;
  SlashCommand? _selectedSlashCommand;
  int _slashSelectedIndex = 0;

  Set<String> get _allNotebookCollectionIds =>
      _notebook.categories.map((category) => category.collectionId).toSet();

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    _initialize();
  }

  void _persistSession() {
    final notebookId = _notebook.id;
    widget.sessionStore.save(
      NotebookChatSession(
        notebookId: notebookId,
        messages: List<ChatMessage>.from(_messages),
        chatHistory: List<Message>.from(_chatHistory),
        selectedCollectionIds: Set<String>.from(_selectedCollectionIds),
      ),
    );
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _status = 'Initializing services...';
    });

    try {
      final ragEngine = MobileRag.instance.engine;
      _notebookRagService = NotebookRagService(ragEngine: ragEngine);
      _warmupCoordinator = NotebookWarmupCoordinator(ragEngine: ragEngine);

      _session = widget.sessionStore.getOrCreate(
        notebookId: _notebook.id,
        initialSelectedCollectionIds: _allNotebookCollectionIds,
      );

      _messages = _session!.messages;
      _chatHistory = _session!.chatHistory;

      final validStoredSelection = _session!.selectedCollectionIds
          .where(
            (collectionId) => _allNotebookCollectionIds.contains(collectionId),
          )
          .toSet();
      _selectedCollectionIds = validStoredSelection.isEmpty
          ? _allNotebookCollectionIds
          : validStoredSelection;

      _queryService = QueryUnderstandingService(
        ollamaClient: _ollamaClient,
        modelName: widget.modelName,
      );

      _ollamaResponseService = OllamaResponseService(
        ollamaClient: _ollamaClient,
        modelName: widget.modelName ?? 'gemma3:4b',
      );

      _chatService = RagChatService(
        ragEngine: ragEngine,
        ollamaClient: _ollamaClient,
        queryService: _queryService!,
        responseService: _ollamaResponseService!,
        notebookRagService: _notebookRagService,
        chatHistory: _chatHistory,
        minSimilarityThreshold: _minSimilarityThreshold,
        mockLlm: widget.mockLlm,
      );

      _documentService = DocumentAddService(ragEngine: ragEngine);

      final stats = await _documentService!.getStats(
        collectionIds: _allNotebookCollectionIds.toList(growable: false),
      );
      _totalSources = stats.sources;
      _totalChunks = stats.chunks;

      _warmupCoordinator?.primeInBackground(_selectedCollectionIds);

      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _status =
            'Ready: ${_notebook.title} · Sources $_totalSources · Chunks $_totalChunks';
      });

      if (_messages.isEmpty) {
        _addSystemMessage(
          'Notebook: ${_notebook.title}\n'
          'Selected collections: ${_selectedCollectionIds.length}/${_allNotebookCollectionIds.length}\n\n'
          '• Use the 📎 button to add documents (default collection)\n'
          '• Ask questions across selected collections\n'
          '• ${widget.mockLlm ? "(Mock mode - no LLM)" : "Using Ollama: ${widget.modelName ?? 'default'}"}',
        );
      }

      if (_totalChunks > 0 && !widget.mockLlm) {
        _generateTopicSuggestions();
      }

      _persistSession();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error: $e';
      });
    }
  }

  void _addSystemMessage(String content) {
    setState(() {
      _messages.insert(0, ChatMessage(content: content, isUser: false));
    });
    _persistSession();
  }

  Future<void> _generateTopicSuggestions() async {
    if (widget.mockLlm) return;

    setState(() => _isLoadingSuggestions = true);

    try {
      final suggestions = await _topicService.generateSuggestions(
        ragEngine: MobileRag.instance.engine,
        collectionIds: _selectedCollectionIds.toList(growable: false),
        ollamaClient: _ollamaClient,
        modelName: widget.modelName,
        maxSuggestions: 3,
        language: _responseLanguage,
      );

      if (mounted) {
        setState(() {
          _suggestedQuestions = suggestions;
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Topic suggestion error: $e');
      if (mounted) {
        setState(() => _isLoadingSuggestions = false);
      }
    }
  }

  void _sendSuggestedQuestion(SuggestedQuestion question) {
    setState(() {
      _suggestedQuestions.remove(question);
      _isSuggestionsExpanded = false;
    });
    _messageController.text = question.question;
    _sendMessage();

    if (_suggestedQuestions.isEmpty && !widget.mockLlm) {
      _topicService.invalidateCache();
      _generateTopicSuggestions();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || !_isInitialized || _isGenerating) return;
    if (_selectedCollectionIds.isEmpty) {
      setState(() => _status = 'Select at least one collection to query.');
      return;
    }

    _messageController.clear();
    _focusNode.unfocus();

    await _warmupCoordinator?.ensureReady(_selectedCollectionIds);

    final parsedIntent = _chatService!.parseIntent(
      text,
      selectedCommand: _selectedSlashCommand,
    );

    if (_selectedSlashCommand != null) {
      setState(() => _selectedSlashCommand = null);
    }

    if (!parsedIntent.parsed.isValid && text.startsWith('/')) {
      setState(() {
        _messages.insert(
          0,
          ChatMessage(content: parsedIntent.displayText, isUser: true),
        );
        _messages.insert(
          0,
          ChatMessage(
            content:
                '❌ ${parsedIntent.parsed.errorMessage ?? "Unknown command."}',
            isUser: false,
          ),
        );
      });
      _persistSession();
      return;
    }

    setState(() {
      _messages.insert(
        0,
        ChatMessage(content: parsedIntent.displayText, isUser: true),
      );
      _messages.insert(
        0,
        ChatMessage(content: '', isUser: false, isStreaming: true),
      );
      _isGenerating = true;
      _currentIntentType = parsedIntent.parsed.intentType == 'general'
          ? null
          : parsedIntent.parsed.intentType;
    });

    try {
      final result = await _chatService!.processMessage(
        text,
        parsedIntent,
        collectionIds: _selectedCollectionIds.toList(growable: false),
        language: _responseLanguage,
        onToken: (token) {
          if (mounted && _messages.isNotEmpty) {
            setState(() {
              _messages[0].content += token;
            });
          }
        },
      );

      if (mounted && _messages.isNotEmpty) {
        setState(() {
          _lastQuery = text;
          _lastChunks = result.chunks;
          _messages[0] = _messages[0].copyWith(
            content: result.response,
            isStreaming: false,
            retrievedChunks: result.chunks,
            tokensUsed: result.estimatedTokens,
            queryType: result.queryType,
            ragSearchTime: result.ragSearchTime,
            llmGenerationTime: result.llmGenerationTime,
            totalTime: result.totalTime,
          );
          if (!widget.mockLlm) {
            _messages[0].hasAnimated = true;
          }
        });
      }
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty && _messages[0].isStreaming) {
          _messages[0] = _messages[0].copyWith(
            content: '❌ Error: $e',
            isStreaming: false,
          );
        }
      });
    } finally {
      setState(() => _isGenerating = false);
      _persistSession();
    }

    _scrollToBottom();
  }

  Future<void> _startNewChat() async {
    setState(() {
      _isLoading = true;
      _status = 'Starting new chat...';
    });

    _chatService?.clearHistory();

    setState(() {
      _messages.clear();
      _chatHistory.clear();
      _isLoading = false;
      _status =
          'Ready: ${_notebook.title} · Sources $_totalSources · Chunks $_totalChunks';
    });

    _addSystemMessage(
      '🔄 New chat started in ${_notebook.title}.\n\n'
      '• Ask questions about selected collections',
    );
    _persistSession();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleMenuAction(RagChatMenuAction action) {
    switch (action) {
      case RagChatMenuAction.newChat:
        _startNewChat();
        break;
      case RagChatMenuAction.languageEnglish:
        setState(() {
          _responseLanguage = ResponseLanguage.english;
          _generateTopicSuggestions();
        });
        break;
      case RagChatMenuAction.languageKorean:
        setState(() {
          _responseLanguage = ResponseLanguage.korean;
          _generateTopicSuggestions();
        });
        break;
      case RagChatMenuAction.compression0:
        setState(() => _compressionLevel = 0);
        break;
      case RagChatMenuAction.compression1:
        setState(() => _compressionLevel = 1);
        break;
      case RagChatMenuAction.compression2:
        setState(() => _compressionLevel = 2);
        break;
    }
  }

  Future<void> _showAddDocumentDialog() async {
    if (_documentService == null) return;

    final result = await showAddDocumentDialog(
      context: context,
      documentService: _documentService!,
      collectionId: _notebook.defaultCollectionId,
    );

    if (result != null && result.success) {
      final stats = await _documentService!.getStats(
        collectionIds: _allNotebookCollectionIds.toList(growable: false),
      );
      setState(() {
        _totalSources = stats.sources;
        _totalChunks = stats.chunks;
        _status = result.fileName != null
            ? '${result.fileName} added to ${_notebook.defaultCollectionId}! Chunks: ${result.chunkCount}'
            : 'Document added! Chunks: ${result.chunkCount}';
      });

      _addSystemMessage(
        result.fileName != null
            ? '✅ ${result.fileName} added to ${_notebook.defaultCollectionId} (${result.chunkCount} chunks).'
            : '✅ Document added with ${result.chunkCount} chunks.',
      );

      if (!widget.mockLlm) {
        _topicService.invalidateCache();
        _generateTopicSuggestions();
      }
    }
  }

  void _onSlashCommandSelected(SlashCommand command) {
    setState(() {
      _showSlashPopup = false;
      _slashFilter = '';
      _selectedSlashCommand = command;
    });
    _messageController.clear();
    _focusNode.requestFocus();
  }

  void _clearSlashCommand() {
    setState(() {
      _selectedSlashCommand = null;
      _currentIntentType = null;
    });
  }

  List<SlashCommand> get _filteredSlashCommands {
    if (_slashFilter.isEmpty || _slashFilter == '/') {
      return kSlashCommands;
    }
    final filterLower = _slashFilter.toLowerCase();
    return kSlashCommands.where((cmd) {
      return cmd.command.toLowerCase().startsWith(filterLower) ||
          cmd.label.toLowerCase().contains(filterLower.replaceFirst('/', ''));
    }).toList();
  }

  void _onSlashArrowKey(bool isUp) {
    final commands = _filteredSlashCommands;
    if (commands.isEmpty) return;

    setState(() {
      if (isUp) {
        _slashSelectedIndex =
            (_slashSelectedIndex - 1 + commands.length) % commands.length;
      } else {
        _slashSelectedIndex = (_slashSelectedIndex + 1) % commands.length;
      }
    });
  }

  void _confirmSlashSelection() {
    final commands = _filteredSlashCommands;
    if (commands.isEmpty) return;

    final index = _slashSelectedIndex.clamp(0, commands.length - 1);
    _onSlashCommandSelected(commands[index]);
  }

  void _toggleCollection(String collectionId, bool selected) {
    final nextSelection = Set<String>.from(_selectedCollectionIds);
    if (selected) {
      nextSelection.add(collectionId);
    } else {
      if (nextSelection.length == 1 && nextSelection.contains(collectionId)) {
        return;
      }
      nextSelection.remove(collectionId);
    }

    setState(() {
      _selectedCollectionIds = nextSelection;
      _status =
          'Selected collections: ${_selectedCollectionIds.length}/${_allNotebookCollectionIds.length}';
    });

    _warmupCoordinator?.primeInBackground(_selectedCollectionIds);
    _topicService.invalidateCache();
    _generateTopicSuggestions();
    _persistSession();
  }

  Widget _buildCollectionScopeBar() {
    final categories = _notebook.categories;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      color: const Color(0xFF171A20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            selected:
                _selectedCollectionIds.length ==
                _allNotebookCollectionIds.length,
            label: const Text('All Categories'),
            onSelected: (_) {
              setState(() {
                _selectedCollectionIds = _allNotebookCollectionIds;
              });
              _warmupCoordinator?.primeInBackground(_selectedCollectionIds);
              _topicService.invalidateCache();
              _generateTopicSuggestions();
              _persistSession();
            },
          ),
          ...categories.map((category) {
            final selected = _selectedCollectionIds.contains(
              category.collectionId,
            );
            return FilterChip(
              selected: selected,
              label: Text(_displayCategoryLabel(category)),
              onSelected: (value) =>
                  _toggleCollection(category.collectionId, value),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: RagChatAppBar(
        title: '${_notebook.emoji} ${_notebook.title}',
        showGraphPanel: _showGraphPanel,
        showDebugInfo: _showDebugInfo,
        language: _responseLanguage,
        compressionLevel: _compressionLevel,
        onToggleGraph: () => setState(() => _showGraphPanel = !_showGraphPanel),
        onToggleDebug: () => setState(() => _showDebugInfo = !_showDebugInfo),
        onMenuAction: _handleMenuAction,
      ),
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF121212),
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (_showDebugInfo) _buildStatusBar(),
                      _buildCollectionScopeBar(),
                      SuggestionChipsPanel(
                        suggestions: _suggestedQuestions,
                        isLoading: _isLoadingSuggestions,
                        isExpanded: _isSuggestionsExpanded,
                        isDisabled: _isGenerating,
                        onToggleExpanded: () => setState(
                          () =>
                              _isSuggestionsExpanded = !_isSuggestionsExpanded,
                        ),
                        onRefresh: () {
                          _topicService.invalidateCache();
                          _generateTopicSuggestions();
                        },
                        onQuestionSelected: _sendSuggestedQuestion,
                      ),
                      Expanded(child: _buildMessageList()),
                      _buildInputArea(),
                    ],
                  ),
                  if (_showSlashPopup)
                    Positioned(
                      left: 60,
                      bottom: 80,
                      child: SlashCommandOverlay(
                        filter: _slashFilter,
                        selectedIndex: _slashSelectedIndex,
                        onSelect: _onSlashCommandSelected,
                        onDismiss: () =>
                            setState(() => _showSlashPopup = false),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_showGraphPanel) Container(width: 1, color: Colors.grey[800]),
          if (_showGraphPanel)
            Expanded(
              flex: 4,
              child: KnowledgeGraphPanel(
                query: _lastQuery,
                chunks: _lastChunks,
                similarityThreshold: _minSimilarityThreshold,
                selectedChunk: _selectedChunk,
                userIntent: _currentIntentType,
                onChunkSelected: (chunk) {
                  setState(() => _selectedChunk = chunk);
                },
              ),
            ),
          if (_showGraphPanel) Container(width: 1, color: Colors.grey[800]),
          if (_showGraphPanel)
            Expanded(
              flex: 2,
              child: ChunkDetailSidebar(
                chunks: _lastChunks,
                selectedChunk: _selectedChunk,
                searchQuery: _lastQuery,
                onChunkSelected: (chunk) {
                  setState(() => _selectedChunk = chunk);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          if (_isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              _isInitialized ? Icons.check_circle : Icons.error,
              size: 16,
              color: _isInitialized ? Colors.green : Colors.red,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_notebook.emoji} ${_selectedCollectionIds.length}/${_allNotebookCollectionIds.length} • 📄$_totalSources 📦$_totalChunks',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return ChatInputArea(
      controller: _messageController,
      focusNode: _focusNode,
      isEnabled: _isInitialized,
      isGenerating: _isGenerating,
      onSend: _sendMessage,
      onAttach: _showAddDocumentDialog,
      selectedCommand: _selectedSlashCommand,
      onClearCommand: _clearSlashCommand,
      isSlashPopupVisible: _showSlashPopup,
      onConfirmSlashSelection: _confirmSlashSelection,
      onArrowKey: _onSlashArrowKey,
      onSlashInput: (showPopup, filter) {
        setState(() {
          _showSlashPopup = showPopup;
          _slashFilter = filter;
          if (showPopup) {
            _slashSelectedIndex = 0;
          }
        });
      },
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No messages yet', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _showAddDocumentDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add documents to start'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        if (message.isUser) {
          return UserMessageBubble(message: message);
        }

        return DocumentStyleResponse(
          message: message,
          showDebugInfo: _showDebugInfo,
          shouldAnimate: index == 0 && !_isGenerating,
        );
      },
    );
  }

  String _displayCategoryLabel(NotebookCategoryModel category) {
    if (category.collectionId == _notebook.defaultCollectionId) {
      return 'Default (Upload Target)';
    }
    return category.title;
  }

  @override
  void dispose() {
    _persistSession();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
