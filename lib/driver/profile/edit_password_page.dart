import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/profile/driver_password_otp_page.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';
import 'package:ice_cream/driver/profile/profile_success_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditPasswordPage extends StatefulWidget {
  final String initialPassword;
  final String currentEmail;

  const EditPasswordPage({
    super.key,
    this.initialPassword = '',
    this.currentEmail = '',
  });

  @override
  State<EditPasswordPage> createState() => _EditPasswordPageState();
}

class _EditPasswordPageState extends State<EditPasswordPage> {
  late final TextEditingController _currentPasswordController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _retypePasswordController;
  late final VoidCallback _listener;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureRetype = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _retypePasswordController = TextEditingController();
    _listener = () => setState(() {});
    _currentPasswordController.addListener(_listener);
    _newPasswordController.addListener(_listener);
    _retypePasswordController.addListener(_listener);
  }

  @override
  void dispose() {
    _currentPasswordController.removeListener(_listener);
    _newPasswordController.removeListener(_listener);
    _retypePasswordController.removeListener(_listener);
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _retypePasswordController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return _currentPasswordController.text.trim().isNotEmpty &&
        _newPasswordController.text.trim().isNotEmpty &&
        _retypePasswordController.text.trim().isNotEmpty &&
        !_sending;
  }

  Future<void> _sendOtp() async {
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final retypePassword = _retypePasswordController.text.trim();
    if (newPassword != retypePassword) {
      throw Exception('New password and retype password do not match.');
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('driver_token') ?? '';
    if (token.isEmpty) {
      throw Exception('Not authenticated. Please login again.');
    }

    final response = await http.post(
      Uri.parse('${Auth.apiBaseUrl}/driver/change-password/send-otp'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirmation': retypePassword,
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
                'Change password',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1B1F),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter current, new, retype password then verify OTP in email.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF747474),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 28),
              _passwordField(
                controller: _currentPasswordController,
                hintText: 'Current password',
                obscureText: _obscureCurrent,
                onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: _newPasswordController,
                hintText: 'New password',
                obscureText: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: _retypePasswordController,
                hintText: 'Retype password',
                obscureText: _obscureRetype,
                onToggle: () => setState(() => _obscureRetype = !_obscureRetype),
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
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute<bool>(
                                builder: (_) => DriverPasswordOtpPage(
                                  email: widget.currentEmail,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            if (ok == true) {
                              await showPasswordSuccessDialog(context);
                              if (!mounted) return;
                              Navigator.pop(
                                context,
                                _newPasswordController.text.trim(),
                              );
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

  Widget _passwordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF696969),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
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
          borderSide: const BorderSide(color: Color(0xFF8C8C8C), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      style: const TextStyle(fontSize: 16, color: Color(0xFF1C1B1F)),
    );
  }
}
