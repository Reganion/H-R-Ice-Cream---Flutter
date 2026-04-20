import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/services/fcm_push_service.dart';
import 'package:ice_cream/client/forgot_password.dart';
import 'create_page.dart'; // or the correct file path
import 'landing_page.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';
import 'package:ice_cream/client/google_set_password_page.dart';
import 'package:ice_cream/client/push_home_or_terms.dart';
import 'package:ice_cream/config/google_oauth.dart';

enum SuffixIconType { clear, visibility }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showEmailClear = false;
  bool _showPasswordEye = false;

  bool _emailError = false;
  bool _passwordError = false;
  String? _passwordErrorMessage;

  // Persistent focus nodes
  final FocusNode _focusNodeEmail = FocusNode();
  final FocusNode _focusNodePassword = FocusNode();

  // Border colors
  Color _emailBorderColor = const Color(0xFFFAFAFA);
  Color _passwordBorderColor = const Color(0xFFFAFAFA);

  bool _isGoogleLoading = false;
  bool _isLoggingIn = false;
  bool _sessionResumeLoading = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryResumeCustomerSession());
    });

    _emailController.addListener(() {
      setState(() {
        _showEmailClear = _emailController.text.isNotEmpty;
      });
    });

    _passwordController.addListener(() {
      setState(() {
        _showPasswordEye = _passwordController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _focusNodeEmail.dispose();
    _focusNodePassword.dispose();
    super.dispose();
  }

  /// If a stored Laravel token exists and [GET /session] succeeds, skip the form.
  Future<void> _tryResumeCustomerSession() async {
    final token = (await Auth.getToken())?.trim() ?? '';
    if (token.isEmpty) return;

    setState(() => _sessionResumeLoading = true);
    try {
      final res = await http
          .get(
            Uri.parse('${Auth.apiBaseUrl}/session'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data['success'] == true) {
          final needsTerms = data['needs_terms_acceptance'] == true;
          unawaited(FcmPushService.syncCustomerToken());
          if (!mounted) return;
          await pushHomeOrTerms(context, needsTerms: needsTerms);
          return;
        }
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        await Auth.clearCustomerSessionLocal();
        return;
      }

      if (res.statusCode >= 500) {
        return;
      }

      await Auth.clearCustomerSessionLocal();
    } catch (_) {
      // Stay on login; user can retry manually.
    } finally {
      if (mounted) {
        setState(() => _sessionResumeLoading = false);
      }
    }
  }

final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: kGoogleOAuthServerClientId,
  );
Future<void> _signInWithGoogle() async {
  setState(() => _isGoogleLoading = true);

  try {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    if (googleUser == null) {
      setState(() => _isGoogleLoading = false);
      return;
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final googleCredential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await FirebaseAuth.instance.signInWithCredential(
      googleCredential,
    );
    final user = userCredential.user;
    if (user == null) {
      throw Exception("Google sign-in failed.");
    }

    final idToken = await Auth.idTokenForGoogleBackend(
      googleAuth: googleAuth,
      firebaseUser: user,
    );
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google session token is missing.');
    }
    final result = await Auth().googleSignIn(
      idToken: idToken,
    );
    if (!context.mounted) return;
    final needsPasswordSetup = result['needs_password_setup'] == true;
    if (needsPasswordSetup) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GoogleSetPasswordPage(
            sessionToken: idToken,
            useSignUpEndpoint: false,
          ),
        ),
      );
    } else {
      final needsTerms = result['needs_terms_acceptance'] == true;
      await pushHomeOrTerms(context, needsTerms: needsTerms);
    }
  } catch (e) {
    if (!mounted) return;
    final text = _friendlyGoogleAuthError(e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  } finally {
    if (mounted) setState(() => _isGoogleLoading = false);
  }
}

String _friendlyGoogleAuthError(Object error) {
  final raw = error.toString();
  final compact = raw.toLowerCase().replaceAll(' ', '');
  final isApi10 = compact.contains('apiexception:10') ||
      compact.contains('statuscode:10') ||
      compact.contains('developer_error');
  if (isApi10) {
    return 'Google Sign-In is not configured for this Android build yet. '
        'Add this app\'s SHA-1/SHA-256 in Firebase for package com.example.ice_cream, '
        'download the latest google-services.json, then rebuild the app.';
  }
  if (error is PlatformException && error.code == 'network_error') {
    return 'Google Sign-In failed because of a network issue. Please check your internet and try again.';
  }
  if (error is Exception) {
    return raw.replaceFirst('Exception: ', '');
  }
  return raw;
}


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () {
                final nav = Navigator.of(context);
                // Pop preserves the existing LandingPage so intro state is not reset
                // and IgnorePointer / splash do not block buttons again.
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  nav.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LandingPage()),
                    (route) => false,
                  );
                }
              },
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      // Logo
                      Transform.translate(
                        offset: const Offset(-3, 0),
                        child: const Text(
                          'H&R',
                          style: TextStyle(
                            color: Color(0xFFE3001B),
                            fontSize: 36,
                            fontFamily: "NationalPark",
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                            height: 0.9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Transform.translate(
                        offset: const Offset(0, -3),
                        child: const Text(
                          'ICE CREAM',
                          style: TextStyle(
                            color: Color(0xFFE3001B),
                            fontSize: 16,
                            fontFamily: "NationalPark",
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 40),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Login to your Account',
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Email input
                      _buildInput(
                        label: "Email Address",
                        controller: _emailController,
                        errorFlag: _emailError,
                        onErrorChange: (v) => setState(() => _emailError = v),
                        borderColor: _emailBorderColor,
                        onBorderChange: (color) =>
                            setState(() => _emailBorderColor = color),
                        focusNode: _focusNodeEmail,
                        showSuffixIcon: _showEmailClear,
                        suffixIconType: SuffixIconType.clear,
                        errorMessage: "This field is required.",
                        obscureText: false,
                        onSuffixIconTap: () {
                          setState(() {
                            _emailController.clear();
                            _showEmailClear = false;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      // Password input
                      _buildInput(
                        label: "Password",
                        controller: _passwordController,
                        errorFlag: _passwordError,
                        onErrorChange: (v) => setState(() {
                          _passwordError = v;
                          if (!v) _passwordErrorMessage = null;
                        }),
                        borderColor: _passwordBorderColor,
                        onBorderChange: (color) =>
                            setState(() => _passwordBorderColor = color),
                        focusNode: _focusNodePassword,
                        showSuffixIcon: _showPasswordEye,
                        suffixIconType: SuffixIconType.visibility,
                        errorMessage:
                            _passwordErrorMessage ?? "This field is required.",
                        obscureText: _obscurePassword,
                        onSuffixIconTap: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),

                      const SizedBox(height: 1),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ForgotPasswordPage(),
                              ),
                            );
                          },
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(
                              color: Color(0xFFE3001C),
                              fontFamily: "NationalPark",
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoggingIn
                              ? null
                              : () async {
                                  setState(() {
                                    _emailError = _emailController.text.isEmpty;
                                    _passwordError = _passwordController.text.isEmpty;
                                    _passwordErrorMessage = _passwordError
                                        ? "This field is required."
                                        : null;
                                  });

                                  if (!_emailError && !_passwordError) {
                                    setState(() => _isLoggingIn = true);
                                    try {
                                      final result = await Auth().login(
                                        email: _emailController.text.trim(),
                                        password: _passwordController.text.trim(),
                                      );

                                      if (result['success'] == true) {
                                        if (!context.mounted) return;
                                        final needsTerms =
                                            result['needs_terms_acceptance'] ==
                                                true;
                                        await pushHomeOrTerms(
                                          context,
                                          needsTerms: needsTerms,
                                        );
                                        return;
                                      }

                                      if (result['needsOtp'] == true) {
                                        final email = result['email'] as String? ??
                                            _emailController.text.trim();
                                        if (!context.mounted) return;
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => OTPcode(
                                              email: email,
                                              password: _passwordController.text.trim(),
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      final msg = e is Exception
                                          ? e.toString().replaceFirst('Exception: ', '')
                                          : 'Invalid email or password';
                                      setState(() {
                                        _passwordError = true;
                                        _passwordErrorMessage = msg;
                                      });
                                    } finally {
                                      if (mounted) setState(() => _isLoggingIn = false);
                                    }
                                  }
                                },

                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE3001C),
                            disabledBackgroundColor: const Color(0xFFFF9CA8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoggingIn
                              ? const AppLoadingOnBrand(size: 22)
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 30),
                      // Or Sign In with
                      Row(
                        children: const [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text('Or, Sign In with'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton(
                          onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isGoogleLoading
                              ? const AppLoadingIndicator()
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'lib/client/images/CL_page/ggl.png',
                                      height: 50,
                                      width: 50,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Sign In with Google',
                                      style: TextStyle(
                                        fontSize: 14.27,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 7),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SignUpPage(),
                                ),
                              );
                            },
                            child: const Text(
                              'Sign up',
                              style: TextStyle(
                                color: Color(0xFFE3001C),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
        ),
        if (_sessionResumeLoading)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: AppLoadingCenter(size: 40, strokeWidth: 2.5),
            ),
          ),
      ],
    );
  }

  // --- Reusable Input Builder for LoginPage ---
  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    required bool errorFlag,
    String? errorMessage,
    required Function(bool) onErrorChange,
    required Color borderColor,
    required Function(Color) onBorderChange,
    required FocusNode focusNode,
    bool obscureText = false,
    bool showSuffixIcon = false,
    SuffixIconType suffixIconType = SuffixIconType.visibility,
    VoidCallback? onSuffixIconTap,
  }) {
    focusNode.addListener(() {
      if (focusNode.hasFocus && !errorFlag) {
        onBorderChange(const Color(0xFF4F4F4F)); // dark gray on focus
      } else if (!focusNode.hasFocus && !errorFlag && controller.text.isEmpty) {
        onBorderChange(const Color(0xFFFAFAFA)); // light gray when unfocused
      }
    });

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
              if (errorFlag && text.isNotEmpty) onErrorChange(false);
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
                        suffixIconType == SuffixIconType.clear
                            ? Icons.close
                            : (obscureText
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                        size: 22,
                      ),
                      onPressed: onSuffixIconTap,
                    )
                  : null,
            ),
          ),
        ),
        if (errorFlag)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorMessage ?? "This field is required.",
              style: const TextStyle(fontSize: 12, color: Color(0xFFE3001C)),
            ),
          ),
      ],
    );
  }
}
