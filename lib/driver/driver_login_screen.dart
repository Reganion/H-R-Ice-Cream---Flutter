import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/landing_page.dart';
import 'package:ice_cream/driver/forgot_password.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';
import 'package:ice_cream/driver/shipments.dart';
import 'package:ice_cream/services/fcm_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shared input background for inputs and the page.
const Color driverLoginInputBgColor = Colors.white;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _emailErrorText;
  String? _passwordErrorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    final emailEmpty = email.isEmpty;
    final passEmpty = password.isEmpty;

    setState(() {
      if (emailEmpty && passEmpty) {
        _emailErrorText = 'This field is required.';
        _passwordErrorText = 'This field is required.';
      } else if (!emailEmpty && passEmpty) {
        _emailErrorText = null;
        _passwordErrorText = 'Please enter your password';
      } else if (emailEmpty && !passEmpty) {
        _emailErrorText = 'Please enter your email address';
        _passwordErrorText = null;
      } else {
        _emailErrorText = null;
        _passwordErrorText = null;
      }
    });

    if (emailEmpty || passEmpty) return;

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse('${Auth.apiBaseUrl}/driver/login');
      final res = await http.post(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, String>{
          'email': email,
          'password': password,
        }),
      );

      final data = safeDecode(res.body);

      if (res.statusCode == 200 && (data['success'] == true)) {
        final token = data['token'] as String?;
        final driver = data['driver'] as Map<String, dynamic>?;

        if (token != null && token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('driver_token', token);
          await prefs.setString('driver_password', password);
          if (driver != null) {
            await prefs.setString('driver_profile', jsonEncode(driver));
          }
          unawaited(FcmPushService.syncDriverToken());
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ShipmentsPage(),
          ),
        );
        return;
      }

      // Laravel validation errors (422)
      if (res.statusCode == 422 && data['errors'] is Map<String, dynamic>) {
        final errors = data['errors'] as Map<String, dynamic>;
        setState(() {
          final emailErrors = errors['email'];
          if (emailErrors is List && emailErrors.isNotEmpty) {
            _emailErrorText = emailErrors.first.toString();
          }
          final passErrors = errors['password'];
          if (passErrors is List && passErrors.isNotEmpty) {
            _passwordErrorText = passErrors.first.toString();
          }
        });
        return;
      }

      // 401 wrong credentials, 403 inactive account — API returns { success, message }
      if (res.statusCode == 401 ||
          res.statusCode == 403 ||
          (data['success'] == false && data['message'] != null)) {
        final msg = extractApiMessage(data);
        setState(() {
          _emailErrorText = null;
          _passwordErrorText = msg;
        });
        return;
      }

      setState(() {
        _emailErrorText = null;
        _passwordErrorText = extractApiMessage(data);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not connect to server. Please check your connection.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: driverLoginInputBgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: driverLoginInputBgColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            final nav = Navigator.of(context);
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
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 0),

                  const _HRLogo(),
                  const SizedBox(height: 26),

                  const Text(
                    'Welcome Rider',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1B1F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hello there, sign in to continue',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF1C1B1F),
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 64),

                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (_emailErrorText != null) {
                        setState(() => _emailErrorText = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Email Address',
                      hintStyle: const TextStyle(
                        color: Color(0xFF626262),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      errorText: _emailErrorText,
                      errorStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE3001C),
                      ),
                      filled: true,
                      fillColor: driverLoginInputBgColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _emailErrorText != null
                              ? const Color(0xFFE3001C)
                              : const Color(0xFF8C8C8C),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _emailErrorText != null
                              ? const Color(0xFFE3001C)
                              : const Color(0xFF8C8C8C),
                          width: 1,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFFE3001C),
                          width: 1,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFFE3001C),
                          width: 1,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    onChanged: (_) {
                      if (_passwordErrorText != null) {
                        setState(() => _passwordErrorText = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: const TextStyle(
                        color: Color(0xFF626262),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      errorText: _passwordErrorText,
                      errorStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE3001C),
                      ),
                      filled: true,
                      fillColor: driverLoginInputBgColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _passwordErrorText != null
                              ? const Color(0xFFE3001C)
                              : const Color(0xFF8C8C8C),
                          width: 1.2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: _passwordErrorText != null
                              ? const Color(0xFFE3001C)
                              : const Color(0xFF8C8C8C),
                          width: 1.2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFFE3001C),
                          width: 1.2,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFFE3001C),
                          width: 1.2,
                        ),
                      ),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: IconButton(
                          splashRadius: 20,
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF9B9B9B),
                            size: 22,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE3001B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgotPasswordDPage(),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFE30000),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE3001B),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HRLogo extends StatelessWidget {
  const _HRLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
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
      ],
    );
  }
}

/// Shown after a successful password reset via Laravel/Firestore driver API.
class CongratsDPage extends StatelessWidget {
  const CongratsDPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'lib/driver/LF_images/fpsuccess.jpg',
                    width: 260,
                    height: 260,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 140,
                      color: Color(0xFF22B345),
                    ),
                  ),
                  Column(
                    children: const [
                      Text(
                        'Your password has been',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        'changed successfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 130),
                  SizedBox(
                    width: 170,
                    height: 57,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005AE6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                          side: const BorderSide(
                            color: Colors.white,
                            width: 1,
                          ),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Back to login',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
