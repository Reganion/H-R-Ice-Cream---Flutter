import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

Future<void> showSuccessDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.83),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Icon(
                Symbols.check_circle,
                size: 44,
                color: Color(0xFF22B345),
                fill: 1,
                weight: 400,
                grade: 0,
                opticalSize: 24,
              ),
              const SizedBox(height: 8),
              const Text(
                "Successfully Updated",
                style: TextStyle(fontSize: 19.85, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Your phone number has been successfully updated",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.23,
                  color: Color(0xFF5B5B5B),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showEmailSuccessDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.83),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Icon(
                Symbols.check_circle,
                size: 44,
                color: Color(0xFF22B345),
                fill: 1,
                weight: 400,
                grade: 0,
                opticalSize: 24,
              ),
              const SizedBox(height: 8),
              const Text(
                "Successfully Updated",
                style: TextStyle(fontSize: 19.85, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Your email has been successfully updated",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.23,
                  color: Color(0xFF5B5B5B),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showPasswordSuccessDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.83),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Icon(
                Symbols.check_circle,
                size: 44,
                color: Color(0xFF22B345),
                fill: 1,
                weight: 400,
                grade: 0,
                opticalSize: 24,
              ),
              const SizedBox(height: 8),
              const Text(
                "Successfully Updated",
                style: TextStyle(fontSize: 19.85, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Your password has been successfully updated",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.23,
                  color: Color(0xFF5B5B5B),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    },
  );
}
