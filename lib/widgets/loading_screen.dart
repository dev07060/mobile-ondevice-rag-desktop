/// Loading screen widget with status message.
/// Displays a centered loading indicator with an optional status message.

import 'package:flutter/material.dart';

/// A reusable loading screen widget
class LoadingScreen extends StatelessWidget {
  final String? statusMessage;

  const LoadingScreen({super.key, this.statusMessage});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(statusMessage ?? 'Checking status...'),
          ],
        ),
      ),
    );
  }
}
