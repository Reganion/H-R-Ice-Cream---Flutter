import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';
import 'package:ice_cream/config/google_oauth.dart';
import 'package:ice_cream/client/google_set_password_page.dart';
import 'package:ice_cream/client/push_home_or_terms.dart';
import 'login_page.dart'; // or the correct file path
import 'dart:async';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  bool _obscurePassword = true;

  final TextEditingController _firstController = TextEditingController();
  final TextEditingController _lastController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureConfirmPassword = true;
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _showConfirmPasswordEye = false;
  bool _showPasswordEye = false;
  bool _firstError = false;
  bool _lastError = false;
  bool _emailError = false;
  bool _passwordError = false;
  bool _confirmPasswordError = false;
  final FocusNode _focusNodeFirst = FocusNode();
  final FocusNode _focusNodeLast = FocusNode();
  final FocusNode _focusNodeEmail = FocusNode();
  final FocusNode _focusNodePassword = FocusNode();
  final FocusNode _focusNodeConfirmPassword = FocusNode();
  bool _isGoogleLoading = false;
  bool _registering = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: kGoogleOAuthServerClientId,
  );

  @override
  void dispose() {
    _focusNodeFirst.dispose();
    _focusNodeLast.dispose();
    _focusNodeEmail.dispose();
    _focusNodePassword.dispose();
    _focusNodeConfirmPassword.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Show/hide eye for Confirm Password
    _confirmPasswordController.addListener(() {
      setState(() {
        _showConfirmPasswordEye = _confirmPasswordController.text.isNotEmpty;
      });
    });

    // Show/hide eye for Create Password
    _passwordController.addListener(() {
      setState(() {
        _showPasswordEye = _passwordController.text.isNotEmpty;
      });
    });
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

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
        throw Exception("Google sign-up failed.");
      }

      final idToken = await Auth.idTokenForGoogleBackend(
        googleAuth: googleAuth,
        firebaseUser: user,
      );
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google session token is missing.');
      }

      Map<String, dynamic> result;
      try {
        result = await Auth().googleSignUp(
          idToken: idToken,
        );
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('already exists') || msg.contains('google-sign-in')) {
          result = await Auth().googleSignIn(
            idToken: idToken,
          );
        } else {
          rethrow;
        }
      }

      if (!context.mounted) return;
      final needsPasswordSetup = result['needs_password_setup'] == true;
      if (needsPasswordSetup) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GoogleSetPasswordPage(
              sessionToken: idToken,
              useSignUpEndpoint: true,
            ),
          ),
        );
      } else {
        final needsTerms = result['needs_terms_acceptance'] == true;
        await pushHomeOrTerms(context, needsTerms: needsTerms);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyGoogleAuthError(e)),
        ),
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
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
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
                      const SizedBox(height: 40),

                      // LOGO
                      Transform.translate(
                        offset: const Offset(-3, 0), // move left by 5 pixels
                        child: const Text(
                          'H&R',
                          style: TextStyle(
                            color: Color(0xFFE3001B),
                            fontSize: 36,
                            fontFamily: "NationalPark",
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                            height: 0.9, // reduces space below the text
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(
                        height: 1,
                      ), // smaller spacing between the texts
                      Transform.translate(
                        offset: const Offset(
                          0,
                          -3,
                        ), // move ICE CREAM up by 5 pixels
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
                          'Create your Account',
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- First Name + Last Name Row ---
                      // --- First Name + Last Name Row ---
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              "First Name",
                              _firstController,
                              _firstError,
                              (v) => setState(() => _firstError = v),
                              _firstBorderColor,
                              (color) =>
                                  setState(() => _firstBorderColor = color),
                              focusNode: _focusNodeFirst,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInput(
                              "Last Name",
                              _lastController,
                              _lastError,
                              (v) => setState(() => _lastError = v),
                              _lastBorderColor,
                              (color) =>
                                  setState(() => _lastBorderColor = color),
                              focusNode: _focusNodeLast,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // --- Email Address ---
                      _buildInput(
                        "Email Address",
                        _emailController,
                        _emailError,
                        (v) => setState(() => _emailError = v),
                        _emailBorderColor,
                        (color) => setState(() => _emailBorderColor = color),
                        focusNode: _focusNodeEmail,
                      ),

                      const SizedBox(height: 16),
                      // --- Create Password ---
                      _buildInput(
                        "Create Password",
                        _passwordController,
                        _passwordError,
                        (v) => setState(() => _passwordError = v),
                        _passwordBorderColor,
                        (color) => setState(() => _passwordBorderColor = color),
                        obscureText: _obscurePassword,
                        showSuffixIcon: _showPasswordEye,
                        onSuffixIconTap: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        focusNode: _focusNodePassword,
                      ),

                      const SizedBox(height: 16),

                      // --- Confirm Password ---
                      _buildInput(
                        "Confirm Password",
                        _confirmPasswordController,
                        _confirmPasswordError,
                        (v) => setState(() => _confirmPasswordError = v),
                        _confirmPasswordBorderColor,
                        (color) =>
                            setState(() => _confirmPasswordBorderColor = color),
                        obscureText: _obscureConfirmPassword,
                        showSuffixIcon: _showConfirmPasswordEye,
                        onSuffixIconTap: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                        focusNode: _focusNodeConfirmPassword,
                      ),

                      const SizedBox(height: 20),

                      // BUTTON CREATE
                      SizedBox(
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _registering
                              ? null
                              : () async {
                                  setState(() {
                                    _firstError = _firstController.text.isEmpty;
                                    _lastError = _lastController.text.isEmpty;
                                    _emailError = _emailController.text.isEmpty;
                                    _passwordError = _passwordController.text.isEmpty;
                                    _confirmPasswordError =
                                        _confirmPasswordController.text.isEmpty;
                                  });

                                  if (_passwordController.text !=
                                      _confirmPasswordController.text) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Passwords do not match"),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!_firstError &&
                                      !_lastError &&
                                      !_emailError &&
                                      !_passwordError &&
                                      !_confirmPasswordError) {
                                    setState(() => _registering = true);
                                    try {
                                      final result = await Auth().register(
                                        firstName: _firstController.text.trim(),
                                        lastName: _lastController.text.trim(),
                                        email: _emailController.text.trim(),
                                        password: _passwordController.text.trim(),
                                        passwordConfirmation:
                                            _confirmPasswordController.text.trim(),
                                      );
                                      final email = result['email'] as String? ??
                                          _emailController.text.trim();
                                      if (!mounted) return;
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OTPcode(email: email),
                                        ),
                                      );
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
                                      if (mounted) setState(() => _registering = false);
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
                          child: _registering
                              ? const AppLoadingOnBrand(size: 22)
                              : const Text(
                                  'Create',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // DIVIDER
                      Row(
                        children: const [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text("Or, Sign Up with"),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 30),

                      SizedBox(
                        height: 55,
                        child: OutlinedButton(
                          onPressed: _isGoogleLoading ? null : _signUpWithGoogle,
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
                                      "Sign Up with Google",
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

                      // Login Link - at bottom
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Already have an account? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginPage(),
                                ),
                              );
                            },
                            child: const Text(
                              "Login",
                              style: TextStyle(
                                color: Color(0xFFE3001C),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }


  Widget _buildInput(
    String label,
    TextEditingController controller,
    bool errorFlag,
    Function(bool) onErrorChange,
    Color borderColor,
    Function(Color) onBorderChange, {
    bool obscureText = false,
    VoidCallback? onSuffixIconTap, // new
    bool showSuffixIcon = false, // new
    FocusNode? focusNode,
  }) {
    focusNode ??= FocusNode();

    focusNode.addListener(() {
      if (focusNode!.hasFocus && !errorFlag) {
        onBorderChange(const Color(0xFF4F4F4F));
      } else if (!focusNode.hasFocus && !errorFlag && controller.text.isEmpty) {
        onBorderChange(const Color(0xFFFAFAFA));
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
            focusNode: focusNode,
            controller: controller,
            obscureText: obscureText,
            style: const TextStyle(fontSize: 14),
            cursorColor: Colors.black,
            cursorHeight: 18,
            cursorWidth: 2,
            cursorRadius: const Radius.circular(3),
            onChanged: (text) {
              if (errorFlag && text.isNotEmpty) {
                onErrorChange(false);
              }
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
        if (errorFlag)
          Transform.translate(
            offset: const Offset(0, 6), // moves error text UP by 4px
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 0, horizontal: 4),
              child: Text(
                "This field is required",
                style: TextStyle(fontSize: 12, color: Color(0xFFE3001C)),
              ),
            ),
          ),
      ],
    );
  }

  Color _firstBorderColor = const Color(0xFFFAFAFA);
  Color _lastBorderColor = const Color(0xFFFAFAFA);
  Color _emailBorderColor = const Color(0xFFFAFAFA);
  Color _passwordBorderColor = const Color(0xFFFAFAFA);
  Color _confirmPasswordBorderColor = const Color(0xFFFAFAFA);
}

class OTPcode extends StatefulWidget {
  const OTPcode({
    super.key,
    required this.email,
    this.password,
  });

  final String email;
  /// If set, after verify success we auto-login and go to HomePage (login flow).
  final String? password;

  @override
  State<OTPcode> createState() => _OTPcodeState();
}

class _OTPcodeState extends State<OTPcode> {
  List<String> otp = ["", "", "", ""];
  bool _isVerifying = false;
  bool _isResending = false;

  bool get isFilled =>
      otp.every((digit) => digit.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset:
          true, // allows the body to resize when keyboard shows
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 10),
              // BACK BUTTON
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 43,
                    height: 43,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF2F2F2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 150),
              const Text(
                "Enter OTP Code",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1C),
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  text: "We sent code to ",
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF505050),
                    fontWeight: FontWeight.normal,
                  ),
                  children: [
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF1C1B1F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 50),

              /// OTP INPUT BOXES
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _otpBox(index),
                  );
                }),
              ),
              const SizedBox(height: 30),

              /// CONTINUE BUTTON
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: (isFilled && !_isVerifying)
                      ? () async {
                          setState(() => _isVerifying = true);
                          try {
                            final otpCode = otp.join();
                            await Auth().verifyOtp(
                              email: widget.email,
                              otp: otpCode,
                            );
                            if (!mounted) return;
                            if (widget.password != null) {
                              final loginResult = await Auth().login(
                                email: widget.email,
                                password: widget.password!,
                              );
                              if (!context.mounted) return;
                              final needsTerms =
                                  loginResult['needs_terms_acceptance'] == true;
                              await pushHomeOrTerms(
                                context,
                                needsTerms: needsTerms,
                              );
                            } else {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const VerifyPage(),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
                            setState(() => _isVerifying = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is Exception
                                      ? e.toString().replaceFirst('Exception: ', '')
                                      : 'Error: $e',
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith<Color>((
                      states,
                    ) {
                      if (isFilled) {
                        return const Color(0xFFE3001B); // active color
                      }
                      return const Color(0xFFFF9CA7); // disabled color
                    }),
                    shape: MaterialStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    elevation: MaterialStateProperty.all(0),
                  ),
                  child: _isVerifying
                      ? const AppLoadingOnBrand()
                      : const Text(
                          "Continue",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 35),

              /// RESEND OTP
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't get OTP? ", style: TextStyle(fontSize: 14.85)),
                  GestureDetector(
                    onTap: _isResending
                        ? null
                        : () async {
                            setState(() => _isResending = true);
                            try {
                              await Auth().resendOtp(email: widget.email);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "A new code has been sent to your email.",
                                  ),
                                ),
                              );
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
                              if (mounted) setState(() => _isResending = false);
                            }
                          },
                    child: _isResending
                        ? const SizedBox(
                            height: 22,
                            child: AppLoadingIndicator(size: 20),
                          )
                        : const Text(
                            'Resend OTP',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFFE3001B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index) {
    return Container(
      width: 60,
      height: 65,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        cursorColor: Colors.black,
        cursorHeight: 18, // make it taller
        cursorWidth: 2, // thicker than default
        cursorRadius: const Radius.circular(3), // rounded edges â†’ â€œtearâ€ shape
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(
          counterText: "",
          border: InputBorder.none,
        ),
        onChanged: (value) {
          setState(() => otp[index] = value);

          if (value.isNotEmpty && index < 3) {
            FocusScope.of(context).nextFocus();
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).previousFocus();
          }
        },
      ),
    );
  }
}

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key});

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  int _dotCount = 0;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();

    // Animated dots
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _dotCount = (_dotCount + 1) % 4;
      });
    });

    // Simulate verification (short loading)
    Future.delayed(const Duration(seconds: 2), () {
      _dotTimer?.cancel();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CongratPage()),
      );
    });
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String dots = '.' * _dotCount;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Verifying$dots',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF102864),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please wait',
              style: TextStyle(fontSize: 15, color: Color(0xFF1C1B1F)),
            ),
          ],
        ),
      ),
    );
  }
}

class CongratPage extends StatelessWidget {
  const CongratPage({super.key});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: height, // ðŸ‘ˆ keeps portrait layout unchanged
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // âœ… SUCCESS IMAGE
                  Image.asset(
                    'lib/client/images/CL_page/success_account.png',
                    width: 376,
                    height: 296.13,
                  ),

                  // âœ… TEXT
                  Column(
                    children: const [
                      Text(
                        'Congratulations!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF102864),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'You have successfully created your',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1C1B1F),
                        ),
                      ),
                      Text(
                        'account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1C1B1F),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 100),

                  // âœ… LOGIN BUTTON
                  SizedBox(
                    width: 290,
                    height: 59,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF102864),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30), // ðŸ‘ˆ prevents bottom cut-off
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
