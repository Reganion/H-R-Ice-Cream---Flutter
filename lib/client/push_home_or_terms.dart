import 'package:flutter/material.dart';
import 'package:ice_cream/client/home_page.dart' deferred as home;
import 'package:ice_cream/client/terms_acceptance_page.dart';

/// Navigates to [HomePage]. If [needsTerms] is true, shows the terms dialog on the
/// current screen (login, sign-up, OTP, etc.) **before** replacing the route with home.
Future<void> pushHomeOrTerms(
  BuildContext context, {
  required bool needsTerms,
}) async {
  if (needsTerms) {
    final accepted = await showTermsAcceptanceDialog(context);
    if (!context.mounted) return;
    if (accepted != true) return;
  }
  await home.loadLibrary();
  if (!context.mounted) return;
  Navigator.pushReplacement(
    context,
    MaterialPageRoute<void>(
      builder: (_) => home.HomePage(),
    ),
  );
}
