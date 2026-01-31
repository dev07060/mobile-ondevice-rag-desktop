/// Main chat screen with RAG-powered responses.
/// Uses RagChatService for message processing and extracted widgets for UI.

import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:ollama_dart/ollama_dart.dart';

import 'package:local_gemma_macos/services/topic_suggestion_service.dart';
import 'package:local_gemma_macos/services/query_understanding_service.dart';
import 'package:local_gemma_macos/services/ollama_response_service.dart';
import 'package:local_gemma_macos/services/rag_chat_service.dart';
import 'package:local_gemma_macos/services/document_add_service.dart';
import 'package:local_gemma_macos/models/chat_models.dart';
import 'package:local_gemma_macos/widgets/knowledge_graph_panel.dart';
import 'package:local_gemma_macos/widgets/chunk_detail_sidebar.dart';
import 'package:local_gemma_macos/widgets/suggestion_chips.dart';
import 'package:local_gemma_macos/widgets/chat_input_area.dart';
import 'package:local_gemma_macos/widgets/slash_command_overlay.dart';
import 'package:local_gemma_macos/widgets/document_style_response.dart';
import 'package:local_gemma_macos/widgets/rag_chat_appbar.dart';
import 'package:local_gemma_macos/widgets/add_document_dialog.dart';

class RagChatScreen extends StatefulWidget {
  final bool mockLlm;
  final String? modelName;

  const RagChatScreen({super.key, this.mockLlm = false, this.modelName});

  @override
  State<RagChatScreen> createState() => _RagChatScreenState();
}

class _RagChatScreenState extends State<RagChatScreen> {
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Messages
  final List<ChatMessage> _messages = [];

  // Services
  RagChatService? _chatService;
  DocumentAddService? _documentService;
  QueryUnderstandingService? _queryService;
  OllamaResponseService? _ollamaResponseService;
  final OllamaClient _ollamaClient = OllamaClient();
  final List<Message> _chatHistory = [];

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
  bool _showGraphPanel = true;
  bool _isSuggestionsExpanded = true;
  int _compressionLevel = 1;
  ResponseLanguage _responseLanguage = ResponseLanguage.english;
  final double _minSimilarityThreshold = 0.35;

  // Graph panel state
  ChunkSearchResult? _selectedChunk;
  String? _lastQuery;
  List<ChunkSearchResult> _lastChunks = [];
  int? _activeGraphMessageIndex;

  // Slash command state
  bool _showSlashPopup = false;
  String _slashFilter = '';
  String? _currentIntentType;
  SlashCommand? _selectedSlashCommand;
  int _slashSelectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _status = 'Initializing services...';
    });

    try {
      // Use the globally initialized MobileRag singleton
      final ragEngine = MobileRag.instance.engine;

      // Initialize services
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
        chatHistory: _chatHistory,
        minSimilarityThreshold: _minSimilarityThreshold,
        mockLlm: widget.mockLlm,
      );

      _documentService = DocumentAddService(ragEngine: ragEngine);

      // Get stats
      final stats = await ragEngine.getStats();
      _totalSources = stats.sourceCount.toInt();
      _totalChunks = stats.chunkCount.toInt();

      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _status = 'Ready! Sources: $_totalSources, Chunks: $_totalChunks';
      });

      // Add welcome message
      _addSystemMessage(
        'Welcome! I can answer questions based on the documents you add.\n\n'
        '• Use the 📎 button to add documents\n'
        '• Ask me questions about the documents\n'
        '• ${widget.mockLlm ? "(Mock mode - no LLM)" : "Using Ollama: ${widget.modelName ?? 'default'}"}',
      );

      // Generate topic suggestions if we have documents
      if (_totalChunks > 0 && !widget.mockLlm) {
        _generateTopicSuggestions();
      }
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
  }

  Future<void> _generateTopicSuggestions() async {
    if (widget.mockLlm) return;

    setState(() => _isLoadingSuggestions = true);

    try {
      final suggestions = await _topicService.generateSuggestions(
        ragService: MobileRag.instance.engine.service,
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

    _messageController.clear();
    _focusNode.unfocus();

    // Parse intent
    final parsedIntent = _chatService!.parseIntent(
      text,
      selectedCommand: _selectedSlashCommand,
    );

    // Clear selected command
    if (_selectedSlashCommand != null) {
      setState(() => _selectedSlashCommand = null);
    }

    // Handle invalid slash commands
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
      return;
    }

    // Add user message and empty AI response box
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
      // Process message using chat service
      final result = await _chatService!.processMessage(
        text,
        parsedIntent,
        language: _responseLanguage,
        onToken: (token) {
          if (mounted && _messages.isNotEmpty) {
            setState(() {
              _messages[0].content += token;
            });
          }
        },
      );

      // Update message with result
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
      _isLoading = false;
      _status = 'Ready! Sources: $_totalSources, Chunks: $_totalChunks';
    });

    _addSystemMessage(
      '🔄 New chat started! Chat history has been cleared.\n\n'
      '• Ask me questions about your documents',
    );
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
          _generateTopicSuggestions(); // Regenerate suggestions
        });
        break;
      case RagChatMenuAction.languageKorean:
        setState(() {
          _responseLanguage = ResponseLanguage.korean;
          _generateTopicSuggestions(); // Regenerate suggestions
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
    );

    if (result != null && result.success) {
      final stats = await _documentService!.getStats();
      setState(() {
        _totalSources = stats.sources;
        _totalChunks = stats.chunks;
        _status = result.fileName != null
            ? '${result.fileName} added! Chunks: ${result.chunkCount}'
            : 'Document added! Chunks: ${result.chunkCount}';
      });

      _addSystemMessage(
        result.fileName != null
            ? '✅ ${result.fileName} added. (${result.chunkCount} chunks)'
            : '✅ Document added with ${result.chunkCount} chunks.',
      );

      if (!widget.mockLlm) {
        _topicService.invalidateCache();
        _generateTopicSuggestions();
      }
    }
  }

  // Slash command handlers
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

  String? _getQueryForMessage(int aiMessageIndex) {
    for (var i = aiMessageIndex + 1; i < _messages.length; i++) {
      if (_messages[i].isUser) {
        return _messages[i].content;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: RagChatAppBar(
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
          // Left: Chat area
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF121212),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Status bar
                      if (_showDebugInfo) _buildStatusBar(),

                      // Suggestion chips
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

                      // Messages
                      Expanded(child: _buildMessageList()),

                      // Input area
                      _buildInputArea(),
                    ],
                  ),
                  // Slash command overlay
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

          // Divider
          if (_showGraphPanel) Container(width: 1, color: Colors.grey[800]),

          // Middle: Graph panel
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

          // Divider
          if (_showGraphPanel) Container(width: 1, color: Colors.grey[800]),

          // Right: Chunk detail sidebar
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
            '📄$_totalSources 📦$_totalChunks',
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
        } else {
          return DocumentStyleResponse(
            message: message,
            showDebugInfo: _showDebugInfo,
            isGraphActive: _showGraphPanel && _activeGraphMessageIndex == index,
            shouldAnimate: index == 0 && !_isGenerating,
            onViewGraph:
                message.retrievedChunks != null &&
                    message.retrievedChunks!.isNotEmpty
                ? () {
                    setState(() {
                      _lastQuery = _getQueryForMessage(index);
                      _lastChunks = message.retrievedChunks!;
                      _activeGraphMessageIndex = index;
                      _showGraphPanel = true;
                    });
                  }
                : null,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    // Note: Don't dispose MobileRag here as it's a global singleton
    // Only dispose when the entire app is closing
    super.dispose();
  }
}
