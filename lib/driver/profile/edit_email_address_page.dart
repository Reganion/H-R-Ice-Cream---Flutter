import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/profile/driver_email_otp_page.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';
import 'package:ice_cream/driver/profile/profile_success_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditEmailAddressPage extends StatefulWidget {
  final String initialEmail;

  const EditEmailAddressPage({super.key, this.initialEmail = ''});

  @override
  State<EditEmailAddressPage> createState() => _EditEmailAddressPageState();
}

class _EditEmailAddressPageState extends State<EditEmailAddressPage> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final VoidCallback _listener;
  bool _sending = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _passwordController = TextEditingController();
    _listener = () => setState(() {});
    _emailController.addListener(_listener);
    _passwordController.addListener(_listener);
  }

  @override
  void dispose() {
    _emailController.removeListener(_listener);
    _passwordController.removeListener(_listener);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return _emailController.text.trim().isNotEmpty &&
        _passwordController.text.trim().isNotEmpty &&
        !_sending;
  }

  Future<void> _sendOtp() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('driver_token') ?? '';
    if (token.isEmpty) {
      throw Exception('Not authenticated. Please login again.');
    }

    final response = await http.post(
      Uri.parse('${Auth.apiBaseUrl}/driver/change-email/send-otp'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'current_password': _passwordController.text.trim(),
        'new_email': _emailController.text.trim(),
      }),
    );

    final data = safeDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) return;
    throw Exception(extractApiMessage(data));
  }

  @override
  Widget build(BuildContext context) {
    const defaultPink = Color(0xFFFF9CA7);
    const activeRed = Color(0xFFE3001B);
    final buttonColor = _canSubmit ? activeRed : defaultPink;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 43,
                    height: 43,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF2F2F2),
                    ),
                    alignment: Alignment.center,
                    child:
                        const Icon(Icons.close, size: 20, color: Color(0xFF414141)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Edit email address',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1B1F),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter current password then verify OTP sent to your new email.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF747474),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Current password',
                  hintStyle: const TextStyle(
                    color: Color(0xFF696969),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: const Color(0xFF777777),
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8C8C8C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8C8C8C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF8C8C8C), width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                ),
                style: const TextStyle(fontSize: 16, color: Color(0xFF1C1B1F)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  hintText: 'New email',
                  hintStyle: const TextStyle(
                    color: Color(0xFF696969),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8C8C8C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8C8C8C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF8C8C8C), width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                ),
                style: const TextStyle(fontSize: 16, color: Color(0xFF1C1B1F)),
                keyboardType: TextInputType.emailAddress,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit
                      ? () async {
                          setState(() {
                            _sending = true;
                            _error = null;
                          });
                          try {
                            await _sendOtp();
                            if (!mounted) return;
                            final updatedEmail = await Navigator.push<String>(
                              context,
                              MaterialPageRoute<String>(
                                builder: (_) => DriverEmailOtpPage(
                                  pendingEmail: _emailController.text.trim(),
                                ),
                              ),
                            );
                            if (!mounted) return;
                            if (updatedEmail != null &&
                                updatedEmail.trim().isNotEmpty) {
                              await showEmailSuccessDialog(context);
                              if (!mounted) return;
                              Navigator.pop(context, updatedEmail.trim());
                            }
                          } catch (e) {
                            if (!mounted) return;
                            setState(() {
                              _error = e.toString().replaceFirst(
                                'Exception: ',
                                '',
                              );
                            });
                          } finally {
                            if (mounted) setState(() => _sending = false);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _sending ? 'Sending OTP...' : 'Update',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
