/// Application entry point and Ollama server lifecycle manager.
/// Provides RAG + LLM integration for macOS using mobile_rag_engine and ollama_dart.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_rag_engine/mobile_rag_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'config/app_config.dart';
import 'screens/model_setup_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/rag_chat_screen.dart';
import 'services/ollama_server_manager.dart';
import 'services/ollama_status_service.dart';
import 'widgets/home_app_bar.dart';
import 'widgets/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Mobile RAG Engine
  // The package now handles Rust FFI initialization automatically
  await MobileRag.initialize(
    tokenizerAsset: AppConfig.tokenizerAsset,
    modelAsset: AppConfig.modelAsset,
    databaseName: AppConfig.databaseName,
    threadLevel: ThreadUseLevel.high,
  );

  runApp(const LocalGemmaApp());
}

class LocalGemmaApp extends StatefulWidget {
  const LocalGemmaApp({super.key});

  @override
  State<LocalGemmaApp> createState() => _LocalGemmaAppState();
}

class _LocalGemmaAppState extends State<LocalGemmaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop Ollama when app closes
    OllamaServerManager.stopOllama();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is being terminated
      OllamaServerManager.stopOllama();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isOllamaConnected = false;
  bool _hasModel = false;
  bool _isChecking = true;
  String? _statusMessage;
  String? _selectedModel;
  final OllamaStatusService _statusService = OllamaStatusService();

  @override
  void initState() {
    super.initState();
    _initializeOllama();
  }

  Future<void> _initializeOllama() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Starting Ollama server...';
    });

    // Try to start Ollama automatically
    final started = await OllamaServerManager.ensureOllamaRunning();

    if (started) {
      await _checkOllamaStatus();
    } else {
      setState(() {
        _isOllamaConnected = false;
        _isChecking = false;
        _statusMessage = 'Failed to start Ollama server';
      });
    }
  }

  Future<void> _checkOllamaStatus() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Connecting to Ollama...';
    });

    final status = await _statusService.checkStatus();

    setState(() {
      _isOllamaConnected = status.isConnected;
      _hasModel = status.hasModel;
      _selectedModel = status.selectedModel;
      _isChecking = false;
      _statusMessage = status.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return LoadingScreen(statusMessage: _statusMessage);
    }

    return Scaffold(
      appBar: HomeAppBar(onMenuAction: _handleMenuAction),
      body: OnboardingScreen(
        isOllamaConnected: _isOllamaConnected,
        hasModel: _hasModel,
        selectedModel: _selectedModel,
        onStartChat: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RagChatScreen(modelName: _selectedModel!),
            ),
          );
        },
        onDownloadModel: () async {
          final result = await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const ModelSetupScreen()),
          );
          if (result != null) {
            setState(() {
              _hasModel = true;
              _selectedModel = result;
            });
          }
        },
        onSkip: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RagChatScreen(mockLlm: true),
            ),
          );
        },
        onRetryConnection: _initializeOllama,
      ),
    );
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'clear_documents':
        await _clearDocuments();
        break;
      case 'change_model':
        await _changeModel();
        break;
      case 'refresh':
        await _checkOllamaStatus();
        break;
      case 'restart_ollama':
        await _restartOllama();
        break;
    }
  }

  Future<void> _restartOllama() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Restarting Ollama...';
    });

    await OllamaServerManager.stopOllama();
    await Future.delayed(AppConfig.ollamaRestartDelay);
    await _initializeOllama();
  }

  Future<void> _clearDocuments() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Documents?'),
        content: const Text(
          'This will delete all stored documents and RAG data. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // 1. Dispose existing engine (closes DB connection)
        MobileRag.dispose();

        // 2. Delete database file
        final dir = await getApplicationDocumentsDirectory();
        final dbPath = '${dir.path}/${AppConfig.databaseName}';
        final dbFile = File(dbPath);

        if (await dbFile.exists()) {
          await dbFile.delete();
        }

        // 3. Re-initialize engine
        await MobileRag.initialize(
          tokenizerAsset: AppConfig.tokenizerAsset,
          modelAsset: AppConfig.modelAsset,
          databaseName: AppConfig.databaseName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Documents cleared successfully')),
          );
        }
      } catch (e) {
        debugPrint('🔴 Error clearing documents: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
        }

        // Try to re-initialize even if delete failed, to restore app state
        try {
          if (!MobileRag.isInitialized) {
            await MobileRag.initialize(
              tokenizerAsset: AppConfig.tokenizerAsset,
              modelAsset: AppConfig.modelAsset,
              databaseName: AppConfig.databaseName,
            );
          }
        } catch (reInitError) {
          debugPrint('🔴 Error re-initializing after failure: $reInitError');
        }
      }
    }
  }

  Future<void> _changeModel() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ModelSetupScreen()),
    );
    if (result != null) {
      setState(() {
        _hasModel = true;
        _selectedModel = result;
      });
    }
  }
}
