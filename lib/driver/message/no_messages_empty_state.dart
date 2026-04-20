import 'package:flutter/material.dart';

/// Illustration + title + subtitle for empty driver message lists.
class NoMessagesEmptyState extends StatelessWidget {
  const NoMessagesEmptyState({
    super.key,
    this.title = 'No messages',
    this.subtitle = 'You don\'t have any messages at the\nmoment, check back later',
    this.imageAsset = 'lib/client/messages/images/no_chat.png',
  });

  final String title;
  final String subtitle;
  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            imageAsset,
            width: 170,
            height: 170,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 120,
              color: Color(0xFFB3B3B3),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1B1F),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Color(0xFF7B7B7B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
