import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/driver_login_screen.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';

class ForgotPasswordDPage extends StatefulWidget {
  const ForgotPasswordDPage({super.key});

  @override
  State<ForgotPasswordDPage> createState() => _ForgotPasswordDPageState();
}

class _ForgotPasswordDPageState extends State<ForgotPasswordDPage> {
  final TextEditingController emailController = TextEditingController();
  bool hasText = false;
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    // Listen to input changes
    emailController.addListener(() {
      setState(() {
        hasText = emailController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _sendForgotPasswordOtp() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorText = 'Please enter your email address.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${Auth.apiBaseUrl}/driver/forgot-password'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email}),
      );
      final data = safeDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OTPDcode(email: email)),
        );
        return;
      }

      setState(() {
        _errorText = extractApiMessage(data);
      });
    } catch (_) {
      setState(() {
        _errorText = 'Could not connect to server. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),

                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
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

                const SizedBox(height: 140),

                const Text(
                  "Forgot Password",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1C),
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  "Enter your email address to receive a reset link and regain access to your account.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF505050)),
                ),

                const SizedBox(height: 40),

                Container(
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
                    controller: emailController,
                    cursorColor: Colors.black,
                    cursorHeight: 18,
                    cursorWidth: 2,
                    cursorRadius: const Radius.circular(3),
                    decoration: InputDecoration(
                      hintText: "Email address",
                      hintStyle: const TextStyle(
                        color: Color(0xFF505050),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed:
                        (hasText && !_loading) ? _sendForgotPasswordOtp : null,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.disabled)) {
                            return const Color(0xFFFF9CA8); // disabled color
                          }
                          return const Color(0xFFE3001B); // enabled color
                        },
                      ),
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      elevation: MaterialStateProperty.all(0),
                    ),
                    child: Text(
                      _loading ? "Sending..." : "Continue",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OTPDcode extends StatefulWidget {
  final String email;

  const OTPDcode({super.key, required this.email});

  @override
  State<OTPDcode> createState() => _OTPDcodeState();
}

class _OTPDcodeState extends State<OTPDcode> {
  List<String> otp = ["", "", "", ""]; // store OTP digits
  bool _loading = false;
  bool _resending = false;
  String? _errorText;
  int _resendSecondsLeft = 0;
  Timer? _resendTimer;

  bool get isFilled =>
      otp.every((digit) => digit.isNotEmpty); // check if all boxes are filled

  bool get _canResend => !_loading && !_resending && _resendSecondsLeft == 0;

  String get _resendLabel {
    if (_resending) return 'Resending...';
    if (_resendSecondsLeft > 0) {
      final mm = (_resendSecondsLeft ~/ 60).toString().padLeft(2, '0');
      final ss = (_resendSecondsLeft % 60).toString().padLeft(2, '0');
      return 'Resend OTP in $mm:$ss';
    }
    return 'Resend OTP';
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        setState(() => _resendSecondsLeft = 0);
        timer.cancel();
      } else {
        setState(() => _resendSecondsLeft--);
      }
    });
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${Auth.apiBaseUrl}/driver/forgot-password/verify-otp'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': widget.email, 'otp': otp.join()}),
      );
      final data = safeDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResetPasswordDPage(email: widget.email),
          ),
        );
        return;
      }
      setState(() => _errorText = extractApiMessage(data));
    } catch (_) {
      setState(() {
        _errorText = 'Could not connect to server. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _resending = true);
    try {
      final res = await http.post(
        Uri.parse('${Auth.apiBaseUrl}/driver/forgot-password/resend-otp'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': widget.email}),
      );
      final data = safeDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (data['message'] as String?) ?? 'A new OTP has been sent.',
            ),
          ),
        );
        _startResendCooldown();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractApiMessage(data))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to server. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

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
                text: const TextSpan(
                  text: "We sent code to ",
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF505050),
                    fontWeight: FontWeight.normal,
                  ),
                  children: [
                    TextSpan(
                      text: "",
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF1C1B1F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.email,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF1C1B1F),
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
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
                  onPressed:
                      (isFilled && !_loading) ? _verifyOtp : null, // disable
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
                  child: Text(
                    _loading ? "Verifying..." : "Continue",
                    style: const TextStyle(
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
                  const Text("Didn’t get OTP? ", style: TextStyle(fontSize: 14.85)),
                  GestureDetector(
                    onTap: _canResend ? _resendOtp : null,
                    child: Text(
                      _resendLabel,
                      style: TextStyle(
                        fontSize: 15,
                        color: _canResend
                            ? const Color(0xFFE3001B)
                            : const Color(0xFF8D8D8D),
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
        cursorRadius: const Radius.circular(3), // rounded edges → “tear” shape
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

class ResetPasswordDPage extends StatefulWidget {
  final String email;

  const ResetPasswordDPage({super.key, required this.email});

  @override
  State<ResetPasswordDPage> createState() => _ResetPasswordDPageState();
}

class _ResetPasswordDPageState extends State<ResetPasswordDPage> {
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool get _isContinueEnabled {
    return newPasswordController.text.isNotEmpty &&
        confirmPasswordController.text.isNotEmpty;
  }

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _showPasswordEyee = false;
  bool _showConfirmPasswordEyee = false;
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    // Listener for new password field
    newPasswordController.addListener(() {
      setState(() {
        _showPasswordEyee = newPasswordController.text.isNotEmpty;
      });
    });

    // Listener for confirm password field
    confirmPasswordController.addListener(() {
      setState(() {
        _showConfirmPasswordEyee = confirmPasswordController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
            ), // 🔥 SAME AS FORGOT PAGE
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),

                // 🔥 SAME BACK ARROW AS FORGOT PASSWORD PAGE
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
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

                const SizedBox(height: 120), // 🔥 SAME SPACING AS FORGOT PAGE

                const Text(
                  "Reset Password",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1C),
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "Enter your new password",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF505050)),
                ),

                const SizedBox(height: 50),

                // create new PASSWORD
                Container(
                  decoration: _shadowBox(),
                  child: TextField(
                    controller: newPasswordController,
                    obscureText: _obscureNewPassword,
                    style: const TextStyle(fontSize: 14),
                    cursorColor: Colors.black,
                    cursorHeight: 18,
                    cursorWidth: 2,
                    cursorRadius: const Radius.circular(3),
                    decoration: InputDecoration(
                      hintText: "Create new password",
                      hintStyle: const TextStyle(fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _showPasswordEyee
                          ? IconButton(
                              icon: Icon(
                                _obscureNewPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 22,
                                color: _obscureNewPassword
                                    ? const Color(0xFF565656)
                                    : const Color(
                                        0xFFE3001C,
                                      ), // red when visible
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureNewPassword = !_obscureNewPassword;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // re-enter new PASSWORD
                Container(
                  decoration: _shadowBox(),
                  child: TextField(
                    controller: confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    style: const TextStyle(fontSize: 14), // <<< MATCH
                    cursorColor: Colors.black,
                    cursorHeight: 18,
                    cursorWidth: 2,
                    cursorRadius: const Radius.circular(3),
                    decoration: InputDecoration(
                      hintText: "Re-enter new password",
                      hintStyle: const TextStyle(fontSize: 14), // <<< MATCH
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _showConfirmPasswordEyee
                          ? IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 22,
                                color: _obscureConfirmPassword
                                    ? const Color(0xFF565656)
                                    : const Color(
                                        0xFFE3001C,
                                      ), // red when visible
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                if (_errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: (!_isContinueEnabled || _loading)
                        ? null
                        : () async {
                            final newPassword = newPasswordController.text.trim();
                            final confirmPassword = confirmPasswordController.text
                                .trim();

                            if (newPassword.length < 6) {
                              setState(() {
                                _errorText =
                                    'New password must be at least 6 characters.';
                              });
                              return;
                            }
                            if (newPassword != confirmPassword) {
                              setState(() {
                                _errorText =
                                    'New password and retype password do not match.';
                              });
                              return;
                            }

                            setState(() {
                              _loading = true;
                              _errorText = null;
                            });

                            try {
                              final res = await http.post(
                                Uri.parse(
                                  '${Auth.apiBaseUrl}/driver/forgot-password/reset-password',
                                ),
                                headers: const {
                                  'Accept': 'application/json',
                                  'Content-Type': 'application/json',
                                },
                                body: jsonEncode({
                                  'email': widget.email,
                                  'new_password': newPassword,
                                  'new_password_confirmation': confirmPassword,
                                }),
                              );
                              final data = safeDecode(res.body);

                              if (res.statusCode == 200 &&
                                  data['success'] == true) {
                                if (!context.mounted) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const CongratsDPage(),
                                  ),
                                );
                                return;
                              }

                              setState(() => _errorText = extractApiMessage(data));
                            } catch (_) {
                              setState(() {
                                _errorText =
                                    'Could not connect to server. Please try again.';
                              });
                            } finally {
                              if (mounted) {
                                setState(() => _loading = false);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_isContinueEnabled && !_loading)
                          ? const Color(0xFFE3001B) // red when enabled
                          : const Color(0xFFFF9CA7), // pink when "disabled"
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _loading ? "Updating..." : "Continue",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Shadow Box style
BoxDecoration _shadowBox() {
  return BoxDecoration(
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
  );
}
