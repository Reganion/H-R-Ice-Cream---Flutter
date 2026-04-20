import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'no_messages_empty_state.dart';

class noMessagePage extends StatelessWidget {
  const noMessagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: const Color(0xFFFAFAFA),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1C1B1F),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => (),
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
            const Expanded(
              child: NoMessagesEmptyState(),
            ),
          ],
        ),
      ),
    );
  }
}
