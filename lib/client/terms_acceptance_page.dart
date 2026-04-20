import 'package:flutter/material.dart';
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';

/// Modal terms dialog. Returns `true` if accepted. Cannot be dismissed without accepting.
Future<bool?> showTermsAcceptanceDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _TermsAcceptanceDialog(),
  );
}

class _TermsAcceptanceDialog extends StatefulWidget {
  const _TermsAcceptanceDialog();

  @override
  State<_TermsAcceptanceDialog> createState() => _TermsAcceptanceDialogState();
}

class _TermsAcceptanceDialogState extends State<_TermsAcceptanceDialog> {
  bool _agreed = false;
  bool _submitting = false;

  Future<void> _accept() async {
    if (!_agreed) return;
    setState(() => _submitting = true);
    try {
      await Auth().acceptTermsAgreement();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : '$e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Terms & Conditions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF1C1C1C),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'H&R Ice Cream',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFE3001B),
                        fontFamily: 'NationalPark',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please review and accept our terms before using the app.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade800,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      '1. Agreement',
                      'By creating an account or signing in, you agree to these Terms and Conditions and our use of your information as needed to process orders, deliveries, and support for H&R Ice Cream.',
                    ),
                    _section(
                      '2. Orders & payments',
                      'When you place an order through the app, you agree to pay the prices and fees shown at checkout. We may cancel or refuse orders in case of unavailability, errors, or suspected fraud, and we will notify you when possible.',
                    ),
                    _section(
                      '3. Account & security',
                      'You are responsible for keeping your login details confidential and for activity under your account. Notify us promptly if you believe someone else has accessed your account.',
                    ),
                    _section(
                      '4. Marketing & notifications',
                      'We may send you order updates and service messages. Where allowed, we may also share offers or news about H&R Ice Cream; you can adjust notification preferences in your device or account settings where available.',
                    ),
                    _section(
                      '5. Limitation',
                      'To the fullest extent permitted by law, H&R Ice Cream is not liable for indirect or consequential losses arising from use of the app or our products, except where liability cannot be excluded by law.',
                    ),
                    _section(
                      '6. Changes',
                      'We may update these terms from time to time. Continued use of the app after changes means you accept the updated terms. If we require a new acceptance, we will ask you in the app before you continue.',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreed,
                      activeColor: const Color(0xFFE3001C),
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _agreed = v ?? false),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'I have read and agree to the Terms and Conditions above.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_submitting || !_agreed) ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE3001C),
                    disabledBackgroundColor: const Color(0xFFFF9CA8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const AppLoadingOnBrand(size: 22)
                      : const Text(
                          'Accept and continue',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
