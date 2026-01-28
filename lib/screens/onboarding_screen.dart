/// Onboarding screen widget for first-time users.
/// Displays a 3-page guide: Welcome, Setup, and Quick Start.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Onboarding page data
class OnboardingPage {
  final String title;
  final Widget content;
  final IconData? icon;
  final Color? iconColor;

  const OnboardingPage({
    required this.title,
    required this.content,
    this.icon,
    this.iconColor,
  });
}

/// Main onboarding screen with PageView
class OnboardingScreen extends StatefulWidget {
  final bool isOllamaConnected;
  final bool hasModel;
  final String? selectedModel;
  final VoidCallback onStartChat;
  final VoidCallback onDownloadModel;
  final VoidCallback onSkip;
  final VoidCallback onRetryConnection;

  const OnboardingScreen({
    super.key,
    required this.isOllamaConnected,
    required this.hasModel,
    this.selectedModel,
    required this.onStartChat,
    required this.onDownloadModel,
    required this.onSkip,
    required this.onRetryConnection,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Skip button row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Page indicators
                  Row(
                    children: List.generate(3, (index) {
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Colors.purple
                              : Colors.grey[700],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  // Skip button
                  if (_currentPage < 2)
                    TextButton(
                      onPressed: () => _goToPage(2),
                      child: Text(
                        'Skip',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                ],
              ),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(),
                  _buildSetupPage(),
                  _buildQuickStartPage(),
                ],
              ),
            ),

            // Bottom navigation
            Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBottomButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    if (_currentPage == 0) {
      return FilledButton(
        onPressed: _nextPage,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: Colors.purple,
        ),
        child: const Text('Get Started', style: TextStyle(fontSize: 16)),
      );
    } else if (_currentPage == 1) {
      return FilledButton(
        onPressed: _nextPage,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: Colors.purple,
        ),
        child: const Text('Continue', style: TextStyle(fontSize: 16)),
      );
    } else {
      // Last page
      return Column(
        children: [
          if (widget.hasModel)
            FilledButton.icon(
              onPressed: widget.onStartChat,
              icon: const Icon(Icons.chat),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Colors.purple,
              ),
              label: const Text('Start Chat', style: TextStyle(fontSize: 16)),
            )
          else if (widget.isOllamaConnected)
            FilledButton.icon(
              onPressed: widget.onDownloadModel,
              icon: const Icon(Icons.download),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Colors.purple,
              ),
              label: const Text(
                'Download Model',
                style: TextStyle(fontSize: 16),
              ),
            )
          else
            FilledButton.icon(
              onPressed: widget.onRetryConnection,
              icon: const Icon(Icons.refresh),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: Colors.orange,
              ),
              label: const Text(
                'Retry Connection',
                style: TextStyle(fontSize: 16),
              ),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onSkip,
            child: Text(
              'Skip (Test RAG only)',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple[400]!, Colors.blue[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 60,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            'RAG + Ollama',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'On-device RAG chat powered by local LLM.\n'
            'Your documents stay private on your Mac.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[400],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          // Feature chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildFeatureChip(Icons.lock, 'Private'),
              _buildFeatureChip(Icons.speed, 'Fast'),
              _buildFeatureChip(Icons.wifi_off, 'Offline'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.purple[300]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildSetupPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'Setup Guide',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow these steps to get started',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 32),

          // Step 1: Install Ollama
          _buildSetupStep(
            step: 1,
            title: 'Install Ollama',
            description: 'Ollama runs LLM models locally on your Mac.',
            code: 'brew install ollama',
            isCompleted: widget.isOllamaConnected,
          ),
          const SizedBox(height: 24),

          // Step 2: Download embedding model
          _buildSetupStep(
            step: 2,
            title: 'Download Embedding Model',
            description: 'BGE-m3 model for document search (run in terminal).',
            code: './download_models.sh',
            isCompleted: true, // Assume completed if app runs
          ),
          const SizedBox(height: 24),

          // Step 3: Download LLM
          _buildSetupStep(
            step: 3,
            title: 'Download LLM Model',
            description: 'Download a language model via Ollama.',
            code: 'ollama pull gemma3:4b',
            isCompleted: widget.hasModel,
            note: widget.hasModel
                ? 'Using: ${widget.selectedModel}'
                : 'Or use the Download Model button',
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSetupStep({
    required int step,
    required String title,
    required String description,
    required String code,
    required bool isCompleted,
    String? note,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.grey[800]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Step indicator
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green : Colors.purple,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : Text(
                          '$step',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(color: Colors.grey[400], height: 1.4),
          ),
          const SizedBox(height: 12),
          // Code block
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied: $code'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: Colors.green[300],
                      ),
                    ),
                  ),
                  Icon(Icons.copy, size: 16, color: Colors.grey[600]),
                ],
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: TextStyle(
                color: isCompleted ? Colors.green[300] : Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickStartPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          const Text(
            'Quick Start',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How to use RAG + Ollama',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 32),

          // Tip 1: Add documents
          _buildTipCard(
            icon: Icons.attach_file,
            iconColor: Colors.blue,
            title: 'Add Documents',
            description:
                'Tap the 📎 button to add PDF, DOCX, or text files. '
                'Your documents are processed locally and stored securely.',
          ),
          const SizedBox(height: 16),

          // Tip 2: Ask questions
          _buildTipCard(
            icon: Icons.chat_bubble_outline,
            iconColor: Colors.green,
            title: 'Ask Questions',
            description:
                'Type your question and press Enter. '
                'The AI will search your documents and generate a response.',
          ),
          const SizedBox(height: 16),

          // Tip 3: Slash commands
          _buildTipCard(
            icon: Icons.bolt,
            iconColor: Colors.orange,
            title: 'Slash Commands',
            description:
                'Type / to see available commands:\n'
                '• /summary - Get a concise summary\n'
                '• /define - Get a definition\n'
                '• /more - Expand with general knowledge',
          ),
          const SizedBox(height: 16),

          // Tip 4: View sources
          _buildTipCard(
            icon: Icons.hub,
            iconColor: Colors.purple,
            title: 'View Sources',
            description:
                'Click the graph icon to see which document chunks '
                'were used to generate the response.',
          ),
          const SizedBox(height: 40),

          // Status indicator
          _buildStatusIndicator(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTipCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[400],
                    height: 1.5,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withValues(alpha: 0.2),
            Colors.blue.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            widget.hasModel
                ? Icons.check_circle
                : widget.isOllamaConnected
                ? Icons.warning
                : Icons.error,
            color: widget.hasModel
                ? Colors.green
                : widget.isOllamaConnected
                ? Colors.orange
                : Colors.red,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.hasModel
                      ? 'Ready to Chat!'
                      : widget.isOllamaConnected
                      ? 'Model Required'
                      : 'Ollama Not Running',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.hasModel
                      ? 'Using ${widget.selectedModel}'
                      : widget.isOllamaConnected
                      ? 'Download a model to enable AI responses'
                      : 'Start Ollama server first',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
