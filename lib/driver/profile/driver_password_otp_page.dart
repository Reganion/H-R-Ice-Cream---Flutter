import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/profile/otp_input.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriverPasswordOtpPage extends StatefulWidget {
  final String email;

  const DriverPasswordOtpPage({super.key, required this.email});

  @override
  State<DriverPasswordOtpPage> createState() => _DriverPasswordOtpPageState();
}

class _DriverPasswordOtpPageState extends State<DriverPasswordOtpPage> {
  final List<String> _otp = ["", "", "", ""];
  bool _loading = false;
  bool _resending = false;
  int _resendSecondsLeft = 0;
  Timer? _resendTimer;
  String? _error;

  bool get _isFilled => _otp.every((v) => v.isNotEmpty);

  Future<void> _verifyOtp() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('driver_token') ?? '';
    if (token.isEmpty) throw Exception('Not authenticated. Please login again.');

    final response = await http.post(
      Uri.parse('${Auth.apiBaseUrl}/driver/change-password/verify-otp'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'otp': _otp.join()}),
    );
    final data = safeDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) return;
    throw Exception(extractApiMessage(data));
  }

  Future<void> _resendOtp() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('driver_token') ?? '';
    if (token.isEmpty) throw Exception('Not authenticated. Please login again.');

    final response = await http.post(
      Uri.parse('${Auth.apiBaseUrl}/driver/change-password/resend-otp'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final data = safeDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) return;
    throw Exception(extractApiMessage(data));
  }

  bool get _canResend => !_loading && !_resending && _resendSecondsLeft == 0;

  String get _resendLabel {
    if (_resending) return 'Resending...';
    if (_resendSecondsLeft > 0) {
      final minutes = (_resendSecondsLeft ~/ 60).toString().padLeft(2, '0');
      final seconds = (_resendSecondsLeft % 60).toString().padLeft(2, '0');
      return 'Resend OTP in $minutes:$seconds';
    }
    return 'Resend OTP';
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = 300);
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

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shownEmail =
        widget.email.trim().isEmpty ? 'your email' : widget.email.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 43,
                    height: 43,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF2F2F2),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 120),
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
                  style: const TextStyle(fontSize: 15, color: Color(0xFF505050)),
                  children: [
                    TextSpan(
                      text: shownEmail,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF1C1B1F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  4,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: OtpInput(
                      index: index,
                      onChanged: (value) {
                        setState(() => _otp[index] = value);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: (_isFilled && !_loading)
                      ? () async {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          try {
                            await _verifyOtp();
                            if (!mounted) return;
                            Navigator.pop(context, true);
                          } catch (e) {
                            if (!mounted) return;
                            setState(() {
                              _error = e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
                            });
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (_isFilled && !_loading)
                        ? const Color(0xFFE3001B)
                        : const Color(0xFFFF9CA7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: Text(_loading ? "Verifying..." : "Continue"),
                ),
              ),
              const SizedBox(height: 35),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn’t get OTP? ", style: TextStyle(fontSize: 14.85)),
                  GestureDetector(
                    onTap: !_canResend
                        ? null
                        : () async {
                            setState(() => _resending = true);
                            try {
                              await _resendOtp();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('A new OTP has been sent.'),
                                ),
                              );
                              _startResendCooldown();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().replaceFirst('Exception: ', ''),
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _resending = false);
                            }
                          },
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
}
