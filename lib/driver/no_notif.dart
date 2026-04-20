import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class noNotificationsPage extends StatelessWidget {
  const noNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF2F2F2),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 21,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    "Notifications",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {},
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: const Icon(
                        Symbols.delete,
                        size: 22,
                        color: Color(0xFFC7C7C7),
                        fill: 0,
                        weight: 600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Notifications bell and text (same as client no_notifications)
            Expanded(
              child: Align(
                alignment: const Alignment(0, -0.25),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'lib/client/messages/images/no_notif.png',
                      width: 170,
                      height: 170,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.notifications_none_rounded,
                        size: 120,
                        color: Color(0xFFB3B3B3),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Notifications will appear here',
                      style: TextStyle(
                        fontSize: 18.22,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1C1B1F),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Watch this space for offers, updates, and more.',
                      style: TextStyle(
                        fontSize: 13.66,
                        color: Color(0xFF747474),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
