import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/push_home_or_terms.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';
import 'package:ice_cream/config/google_oauth.dart';

/// After Google OAuth, collect password + confirmation before calling Laravel
/// `google-sign-in` / `google-sign-up` with optional password fields.
class GoogleSetPasswordPage extends StatefulWidget {
  const GoogleSetPasswordPage({
    super.key,
    required this.sessionToken,
    required this.useSignUpEndpoint,
    this.acceptTerms = false,
  });

  /// Backend ID token (Google OAuth or Firebase ID token).
  final String sessionToken;

  /// `true`: try [Auth.googleSignUp] first, then [Auth.googleSignIn] if account exists.
  /// `false`: [Auth.googleSignIn] only.
  final bool useSignUpEndpoint;

  /// Sent as `accept_terms` so the server can set [terms_accepted_at] when the user consents.
  final bool acceptTerms;

  @override
  State<GoogleSetPasswordPage> createState() => _GoogleSetPasswordPageState();
}

class _GoogleSetPasswordPageState extends State<GoogleSetPasswordPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final FocusNode _focusPassword = FocusNode();
  final FocusNode _focusConfirm = FocusNode();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: kGoogleOAuthServerClientId,
  );

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _showPasswordEye = false;
  bool _showConfirmEye = false;

  bool _passwordError = false;
  bool _confirmError = false;
  String? _confirmErrorMessage;

  Color _passwordBorderColor = const Color(0xFFFAFAFA);
  Color _confirmBorderColor = const Color(0xFFFAFAFA);

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      setState(() => _showPasswordEye = _passwordController.text.isNotEmpty);
    });
    _confirmController.addListener(() {
      setState(() => _showConfirmEye = _confirmController.text.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _focusPassword.dispose();
    _focusConfirm.dispose();
    super.dispose();
  }

  Future<void> _cancelAndPop() async {
    await _googleSignIn.signOut();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    final pass = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (pass.isEmpty) {
      setState(() {
        _passwordError = true;
        _confirmError = false;
        _confirmErrorMessage = null;
      });
      return;
    }
    if (pass.length < 6) {
      setState(() {
        _passwordError = true;
        _confirmError = false;
        _confirmErrorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters.'),
        ),
      );
      return;
    }
    if (confirm.isEmpty) {
      setState(() {
        _passwordError = false;
        _confirmError = true;
        _confirmErrorMessage = 'This field is required.';
      });
      return;
    }
    if (pass != confirm) {
      setState(() {
        _passwordError = false;
        _confirmError = true;
        _confirmErrorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _passwordError = false;
      _confirmError = false;
      _confirmErrorMessage = null;
      _submitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final freshIdToken = await user.getIdToken(true);
      if (freshIdToken == null || freshIdToken.isEmpty) {
        throw Exception('Unable to refresh sign-in token');
      }

      Map<String, dynamic> result;
      if (widget.useSignUpEndpoint) {
        try {
          result = await Auth().googleSignUp(
            idToken: freshIdToken,
            password: pass,
            passwordConfirmation: confirm,
            acceptTerms: widget.acceptTerms,
          );
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('already exists') || msg.contains('google-sign-in')) {
            result = await Auth().googleSignIn(
              idToken: freshIdToken,
              password: pass,
              passwordConfirmation: confirm,
              acceptTerms: widget.acceptTerms,
            );
          } else {
            rethrow;
          }
        }
      } else {
        result = await Auth().googleSignIn(
          idToken: freshIdToken,
          password: pass,
          passwordConfirmation: confirm,
          acceptTerms: widget.acceptTerms,
        );
      }

      if (!context.mounted) return;
      final needsTerms = result['needs_terms_acceptance'] == true;
      await pushHomeOrTerms(context, needsTerms: needsTerms);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : 'Error: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_cancelAndPop());
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: _cancelAndPop,
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Set your password',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1C),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.useSignUpEndpoint
                              ? 'Add a password for your new account. You can use it to sign in with email anytime.'
                              : 'Add a password to your account so you can sign in with email as well.',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF505050),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildPasswordField(
                          label: 'Password',
                          controller: _passwordController,
                          errorFlag: _passwordError,
                          focusNode: _focusPassword,
                          borderColor: _passwordBorderColor,
                          onBorderChange: (c) =>
                              setState(() => _passwordBorderColor = c),
                          obscureText: _obscurePassword,
                          showSuffixIcon: _showPasswordEye,
                          onSuffixIconTap: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          onErrorClear: () =>
                              setState(() => _passwordError = false),
                        ),
                        const SizedBox(height: 16),
                        _buildPasswordField(
                          label: 'Retype Password',
                          controller: _confirmController,
                          errorFlag: _confirmError,
                          errorMessage: _confirmErrorMessage,
                          focusNode: _focusConfirm,
                          borderColor: _confirmBorderColor,
                          onBorderChange: (c) =>
                              setState(() => _confirmBorderColor = c),
                          obscureText: _obscureConfirm,
                          showSuffixIcon: _showConfirmEye,
                          onSuffixIconTap: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                          onErrorClear: () => setState(() {
                            _confirmError = false;
                            _confirmErrorMessage = null;
                          }),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
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
                                    'Continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool errorFlag,
    String? errorMessage,
    required FocusNode focusNode,
    required Color borderColor,
    required void Function(Color) onBorderChange,
    required bool obscureText,
    required bool showSuffixIcon,
    required VoidCallback onSuffixIconTap,
    required VoidCallback onErrorClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.3),
                spreadRadius: 1,
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Focus(
            onFocusChange: (hasFocus) {
              if (hasFocus && !errorFlag) {
                onBorderChange(const Color(0xFF4F4F4F));
              } else if (!hasFocus &&
                  !errorFlag &&
                  controller.text.isEmpty) {
                onBorderChange(const Color(0xFFFAFAFA));
              }
            },
            child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            style: const TextStyle(fontSize: 14),
            cursorColor: Colors.black,
            cursorHeight: 18,
            cursorWidth: 2,
            cursorRadius: const Radius.circular(3),
            onChanged: (text) {
              if (errorFlag && text.isNotEmpty) onErrorClear();
              onBorderChange(const Color(0xFF4F4F4F));
            },
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(
                fontSize: 14.27,
                color: Color(0xFF727272),
              ),
              floatingLabelStyle: TextStyle(
                fontSize: 17,
                color: errorFlag
                    ? const Color(0xFFE3001C)
                    : const Color(0xFF4F4F4F),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: errorFlag ? const Color(0xFFE3001C) : borderColor,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: errorFlag ? const Color(0xFFE3001C) : borderColor,
                  width: 1,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 16,
              ),
              suffixIcon: showSuffixIcon
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 22,
                      ),
                      onPressed: onSuffixIconTap,
                    )
                  : null,
            ),
          ),
          ),
        ),
        if (errorFlag)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorMessage ?? 'This field is required.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFE3001C)),
            ),
          ),
      ],
    );
  }
}
