import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';
import 'package:ice_cream/driver/profile/profile_success_dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditPhoneNumberPage extends StatefulWidget {
  final String initialPhone;

  const EditPhoneNumberPage({super.key, this.initialPhone = ''});

  @override
  State<EditPhoneNumberPage> createState() => _EditPhoneNumberPageState();
}

class _EditPhoneNumberPageState extends State<EditPhoneNumberPage> {
  late final TextEditingController _controller;
  late final VoidCallback _listener;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPhone);
    _listener = () => setState(() {});
    _controller.addListener(_listener);
  }

  @override
  void dispose() {
    _controller.removeListener(_listener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const defaultPink = Color(0xFFFF9CA7);
    const activeRed = Color(0xFFE3001B);
    final canSubmit = _controller.text.trim().isNotEmpty && !_sending;
    final buttonColor = canSubmit ? activeRed : defaultPink;

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
                'Edit phone number',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1C1B1F),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Keep your phone number up to date.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF747474),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Phone number',
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
                    borderSide: const BorderSide(color: Color(0xFF8C8C8C), width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                ),
                style: const TextStyle(fontSize: 16, color: Color(0xFF1C1B1F)),
                keyboardType: TextInputType.phone,
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
                  onPressed: canSubmit
                      ? () async {
                          final newPhone = _controller.text.trim();
                          setState(() {
                            _sending = true;
                            _error = null;
                          });
                          try {
                            final updatedPhone = await _updatePhoneNumber(newPhone);
                            if (!mounted) return;
                            await showSuccessDialog(context);
                            if (!mounted) return;
                            Navigator.pop(context, updatedPhone);
                          } catch (e) {
                            if (!mounted) return;
                            setState(() {
                              _error = e.toString().replaceFirst('Exception: ', '');
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
                    _sending ? 'Updating...' : 'Update',
                    style: TextStyle(
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

  Future<String> _updatePhoneNumber(String newPhone) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('driver_token') ?? '';
    if (token.isEmpty) {
      throw Exception('Not authenticated. Please login again.');
    }

    final attempts = <_PhoneUpdateAttempt>[
      const _PhoneUpdateAttempt(
        method: 'POST',
        path: '/driver/change-phone',
        payload: {'phone': ''},
      ),
      const _PhoneUpdateAttempt(
        method: 'POST',
        path: '/driver/change-phone',
        payload: {'new_phone': ''},
      ),
      const _PhoneUpdateAttempt(
        method: 'PUT',
        path: '/driver/me',
        payload: {'phone': ''},
      ),
      const _PhoneUpdateAttempt(
        method: 'PATCH',
        path: '/driver/me',
        payload: {'phone': ''},
      ),
    ];

    String lastError = 'Request failed. Please try again.';

    for (final attempt in attempts) {
      final payload = Map<String, dynamic>.from(attempt.payload);
      final phoneKey = payload.keys.first;
      payload[phoneKey] = newPhone;

      final response = await _sendRequest(
        method: attempt.method,
        path: attempt.path,
        token: token,
        body: payload,
      );

      final data = safeDecode(response.body);
      final ok =
          (response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] != false;
      if (ok) {
        final driver = data['driver'];
        if (driver is Map<String, dynamic>) {
          await prefs.setString('driver_profile', jsonEncode(driver));
          final fromDriver = (driver['phone'] ?? '').toString().trim();
          return fromDriver.isNotEmpty ? fromDriver : newPhone;
        }

        final phoneFromData = (data['phone'] ?? '').toString().trim();
        return phoneFromData.isNotEmpty ? phoneFromData : newPhone;
      }

      lastError = extractApiMessage(data);
      if (response.statusCode != 404 && response.statusCode != 405) {
        break;
      }
    }

    throw Exception(lastError);
  }

  Future<http.Response> _sendRequest({
    required String method,
    required String path,
    required String token,
    required Map<String, dynamic> body,
  }) {
    final uri = Uri.parse('${Auth.apiBaseUrl}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    switch (method) {
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        return http.put(uri, headers: headers, body: jsonEncode(body));
      case 'PATCH':
        return http.patch(uri, headers: headers, body: jsonEncode(body));
      default:
        throw Exception('Unsupported request method.');
    }
  }
}

class _PhoneUpdateAttempt {
  final String method;
  final String path;
  final Map<String, dynamic> payload;

  const _PhoneUpdateAttempt({
    required this.method,
    required this.path,
    required this.payload,
  });
}
