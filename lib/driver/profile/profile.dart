import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/login.dart';
import 'package:ice_cream/services/fcm_push_service.dart';
import 'package:ice_cream/driver/profile/edit_email_address_page.dart';
import 'package:ice_cream/driver/profile/edit_password_page.dart';
import 'package:ice_cream/driver/profile/edit_phone_number_page.dart';
import 'package:ice_cream/driver/profile/profile_api_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Last saved `available` | `off_duty` for chip UI when status is on delivery (not sent by API).
const String _kPrefsDriverLastDutyUi = 'driver_last_duty_ui';

/// Static helpers for driver duty / availability UI (maps API `status` ↔ segments).
class _DriverDutyUi {
  _DriverDutyUi._();

  static const String kAvailable = 'available';
  static const String kOffDuty = 'off_duty';

  static String normalizedStatus(dynamic raw) {
    return (raw ?? '')
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll('-', '_');
  }

  static bool isOnRoute(dynamic raw) {
    final n = normalizedStatus(raw);
    if (n.isEmpty) return false;
    if (n.contains('not_on_route')) return false;
    return n == 'on_route' ||
        n == 'onroute' ||
        n.contains('on_route');
  }

  /// Out for delivery — cannot toggle duty until finished.
  static bool isOutForDelivery(dynamic raw) {
    final n = normalizedStatus(raw);
    if (n.isEmpty) return false;
    return n.contains('out_for_delivery') ||
        n.contains('outfordelivery') ||
        n.contains('out_of_delivery') ||
        n == 'out_for_delivery';
  }

  /// On route or actively delivering — availability controls stay disabled.
  static bool isDeliveryLocked(dynamic raw) {
    return isOnRoute(raw) || isOutForDelivery(raw);
  }

  static bool isOffDuty(dynamic raw) {
    final n = normalizedStatus(raw);
    return n == 'off_duty' || n == 'offduty' || n.contains('off_duty');
  }

  /// True = **Available** chip; false = **Off duty**. Pass only `available` / `off_duty` (or cached duty).
  static bool availableSegmentSelected(dynamic raw) {
    return !isOffDuty(raw);
  }

  static String statusForSegment({required bool available}) =>
      available ? kAvailable : kOffDuty;

  /// Short label when [isDeliveryLocked] (for subtitle under "Availability").
  static String deliveryLockSubtitle(dynamic raw) {
    if (isOutForDelivery(raw)) return 'Out for delivery';
    if (isOnRoute(raw)) return 'On route';
    return 'On delivery';
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  bool _loggingOut = false;
  bool _dutyUpdating = false;
  int _totalDelivered = 0;
  Map<String, dynamic> _driver = <String, dynamic>{};
  String _storedPassword = '';
  /// Last known `available` / `off_duty` for chip selection while status is on-route / out-for-delivery.
  String? _cachedDutyForUi;

  bool get _dutyControlsLocked =>
      _DriverDutyUi.isDeliveryLocked(_driver['status']);

  /// Status string used to paint Available vs Off duty (cached when delivery is locked).
  String get _dutyStatusForChips {
    if (_dutyControlsLocked) {
      return _cachedDutyForUi ?? _DriverDutyUi.kAvailable;
    }
    final s = _driver['status'];
    final n = _DriverDutyUi.normalizedStatus(s);
    if (n == _DriverDutyUi.kAvailable || n == _DriverDutyUi.kOffDuty) {
      return n;
    }
    return _DriverDutyUi.kAvailable;
  }

  Future<void> _rememberDutyFromStatus(dynamic status) async {
    if (_DriverDutyUi.isDeliveryLocked(status)) return;
    final n = _DriverDutyUi.normalizedStatus(status);
    if (n != _DriverDutyUi.kAvailable && n != _DriverDutyUi.kOffDuty) return;
    _cachedDutyForUi = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsDriverLastDutyUi, n);
  }

  String get _name => (_driver['name'] ?? '').toString().trim();
  String get _phone => (_driver['phone'] ?? '').toString().trim();
  String get _email => (_driver['email'] ?? '').toString().trim();
  String get _password {
    final fromDriver = (_driver['password'] ?? '').toString();
    if (fromDriver.isNotEmpty) return fromDriver;
    return _storedPassword;
  }
  String get _licenseNo => (_driver['license_no'] ?? '').toString().trim();
  String get _licenseType => (_driver['license_type'] ?? '').toString().trim();
  String? get _imageUrl {
    final v = _driver['image_url'] ?? _driver['image'];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _saveDriverProfileCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_profile', jsonEncode(_driver));
  }

  /// Called when the user taps **Available** — syncs duty with the server (`PATCH /driver/me`).
  Future<void> _onAvailablePressed() async {
    await _setDutyAvailability(available: true);
  }

  /// Called when the user taps **Off duty** — syncs duty with the server (`PATCH /driver/me`).
  Future<void> _onOffDutyPressed() async {
    await _setDutyAvailability(available: false);
  }

  Future<void> _setDutyAvailability({required bool available}) async {
    if (_dutyUpdating) return;
    if (_dutyControlsLocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot change duty while ${_DriverDutyUi.deliveryLockSubtitle(_driver['status'])}.',
          ),
        ),
      );
      return;
    }

    final next = _DriverDutyUi.statusForSegment(available: available);
    final cur = _DriverDutyUi.normalizedStatus(_driver['status']);
    if (cur == next) return;

    final previousStatus = _driver['status'];
    setState(() => _dutyUpdating = true);
    try {
      _driver['status'] = next;
      if (!mounted) return;
      setState(() {});
      await _saveDriverProfileCache();

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('driver_token');
      if (token == null || token.isEmpty) {
        _driver['status'] = previousStatus;
        if (mounted) {
          setState(() {});
          await _saveDriverProfileCache();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not signed in. Please log in again.')),
          );
        }
        return;
      }

      try {
        final res = await http.patch(
          Uri.parse('${Auth.apiBaseUrl}/driver/me'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'status': next}),
        );
        final data = safeDecode(res.body);
        final ok = res.statusCode == 200 && data['success'] != false;

        if (ok) {
          final driver = data['driver'];
          if (driver is Map<String, dynamic>) {
            if ((driver['password'] ?? '').toString().isEmpty &&
                _storedPassword.isNotEmpty) {
              driver['password'] = _storedPassword;
            }
            if (!mounted) return;
            setState(() => _driver = driver);
            await prefs.setString('driver_profile', jsonEncode(driver));
            await _rememberDutyFromStatus(driver['status']);
            if (mounted) setState(() {});
          }
          return;
        }

        _driver['status'] = previousStatus;
        if (!mounted) return;
        setState(() {});
        await _saveDriverProfileCache();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extractApiMessage(data))),
        );
      } catch (_) {
        _driver['status'] = previousStatus;
        if (!mounted) return;
        setState(() {});
        await _saveDriverProfileCache();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update availability. Check your connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _dutyUpdating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('driver_token');
      final cached = prefs.getString('driver_profile');
      _storedPassword = prefs.getString('driver_password') ?? '';
      _cachedDutyForUi = prefs.getString(_kPrefsDriverLastDutyUi);

      if (cached != null && cached.isNotEmpty) {
        try {
          final map = jsonDecode(cached) as Map<String, dynamic>;
          if ((map['password'] ?? '').toString().isEmpty &&
              _storedPassword.isNotEmpty) {
            map['password'] = _storedPassword;
          }
          if (mounted) setState(() => _driver = map);
          await _rememberDutyFromStatus(map['status']);
          if (mounted) setState(() {});
        } catch (_) {}
      }

      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final responses = await Future.wait([
        http.get(
          Uri.parse('${Auth.apiBaseUrl}/driver/me'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
        http.get(
          Uri.parse('${Auth.apiBaseUrl}/driver/shipments').replace(
            queryParameters: {'tab': 'completed'},
          ),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      ]);

      final meRes = responses[0];
      final completedRes = responses[1];
      if (!mounted) return;

      if (meRes.statusCode == 200) {
        final meData = jsonDecode(meRes.body) as Map<String, dynamic>;
        final driver = meData['driver'];
        if (driver is Map<String, dynamic>) {
          if ((driver['password'] ?? '').toString().isEmpty &&
              _storedPassword.isNotEmpty) {
            driver['password'] = _storedPassword;
          }
          _driver = driver;
          await prefs.setString('driver_profile', jsonEncode(driver));
          await _rememberDutyFromStatus(driver['status']);
        }
      }

      if (completedRes.statusCode == 200) {
        final shipData = jsonDecode(completedRes.body) as Map<String, dynamic>;
        final count = shipData['count'];
        _totalDelivered = count is num ? count.toInt() : 0;
      }

      setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('driver_token');
      await FcmPushService.clearDriverToken();
      if (token != null && token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('${Auth.apiBaseUrl}/driver/logout'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );
        } catch (_) {}
      }
      await prefs.remove('driver_token');
      await prefs.remove('driver_profile');
      await prefs.remove('driver_password');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE3001B);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER (red with big rounded bottom)
            SizedBox(
              height: 180,
              child: Stack(
                children: [
                  // red background
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: red,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(48),
                          bottomRight: Radius.circular(48),
                        ),
                      ),
                    ),
                  ),

                  // top row: back + title
                  Positioned(
                    left: 14,
                    top: 14,
                    right: 14,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(999),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Profile",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // avatar
                  Positioned(
                    left: 22,
                    top: 83,
                    child: Container(
                      width: 69,
                      height: 69,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFE0E0),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _imageUrl != null && _imageUrl!.startsWith('http')
                          ? Image.network(
                              _imageUrl!,
                              width: 69,
                              height: 69,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  width: 69,
                                  height: 69,
                                  child: Icon(
                                    Icons.person,
                                    size: 32,
                                    color: Color(0xFFE30613),
                                  ),
                                );
                              },
                            )
                          : Image.asset(
                              "lib/driver/profile/images/kyley.png",
                              width: 69,
                              height: 69,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  width: 69,
                                  height: 69,
                                  child: Icon(
                                    Icons.person,
                                    size: 32,
                                    color: Color(0xFFE30613),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),

                  // name + phone
                  Positioned(
                    left: 110,
                    top: 90,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name.isNotEmpty ? _name : "H&R Driver",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _phone.isNotEmpty ? _phone : "—",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // BODY
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: red,
                        backgroundColor: Color(0xFFF2F2F2),
                      ),
                    ),
                  // stats row – one card with divider in the middle
                  Container(
                    constraints: const BoxConstraints(minHeight: 82),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEFEFEF)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 4),
                                const Text(
                                  "Total Delivered",
                                  style: TextStyle(
                                    color: Color(0xFF8B8B8B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$_totalDelivered",
                                  style: TextStyle(
                                    color: red,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Container(
                            width: 1,
                            color: const Color(0xFFE5E5E5),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Availability",
                                  style: TextStyle(
                                    color: Color(0xFF8B8B8B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (_dutyControlsLocked)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _DriverDutyUi.deliveryLockSubtitle(
                                          _driver['status'],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Opacity(
                                        opacity: 0.45,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _DutyChoiceButton(
                                                label: "Available",
                                                selected:
                                                    _DriverDutyUi.availableSegmentSelected(
                                                  _dutyStatusForChips,
                                                ),
                                                red: red,
                                                enabled: false,
                                                onTap: () {},
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: _DutyChoiceButton(
                                                label: "Off duty",
                                                selected: !_DriverDutyUi
                                                    .availableSegmentSelected(
                                                  _dutyStatusForChips,
                                                ),
                                                red: red,
                                                enabled: false,
                                                onTap: () {},
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else if (_dutyUpdating)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: red,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _DutyChoiceButton(
                                          label: "Available",
                                          selected:
                                              _DriverDutyUi.availableSegmentSelected(
                                            _dutyStatusForChips,
                                          ),
                                          red: red,
                                          enabled: true,
                                          onTap: _onAvailablePressed,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _DutyChoiceButton(
                                          label: "Off duty",
                                          selected: !_DriverDutyUi
                                              .availableSegmentSelected(
                                            _dutyStatusForChips,
                                          ),
                                          red: red,
                                          enabled: true,
                                          onTap: _onOffDutyPressed,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // details card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEFEFEF)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          label: "Phone Number",
                          value: _phone.isNotEmpty ? _phone : "—",
                          trailingText: "Change",
                          showDivider: true,
                          onTap: () async {
                            final updatedPhone = await Navigator.push<String>(
                              context,
                              MaterialPageRoute<String>(
                                builder: (context) => EditPhoneNumberPage(
                                  initialPhone: _phone,
                                ),
                              ),
                            );
                            if (updatedPhone == null ||
                                updatedPhone.trim().isEmpty) {
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              _driver['phone'] = updatedPhone.trim();
                            });
                            await _saveDriverProfileCache();
                          },
                        ),
                        _InfoRow(
                          label: "Email",
                          value: _email.isNotEmpty ? _email : "—",
                          trailingText: "Change",
                          showDivider: true,
                          onTap: () async {
                            final updatedEmail = await Navigator.push<String>(
                              context,
                              MaterialPageRoute<String>(
                                builder: (context) => EditEmailAddressPage(
                                  initialEmail: _email,
                                ),
                              ),
                            );
                            if (updatedEmail == null ||
                                updatedEmail.trim().isEmpty) {
                              return;
                            }
                            if (!mounted) return;
                            setState(() {
                              _driver['email'] = updatedEmail.trim();
                            });
                            await _saveDriverProfileCache();
                          },
                        ),
                        _InfoRow(
                          label: "Password",
                          value: _password.isNotEmpty ? "••••••••" : "—",
                          trailingText: "Change",
                          showDivider: true,
                          onTap: () async {
                            final updatedPassword = await Navigator.push<String>(
                              context,
                              MaterialPageRoute<String>(
                                builder: (context) => EditPasswordPage(
                                  initialPassword: _password,
                                  currentEmail: _email,
                                ),
                              ),
                            );

                            if (updatedPassword == null ||
                                updatedPassword.trim().isEmpty) {
                              return;
                            }

                            final trimmed = updatedPassword.trim();
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('driver_password', trimmed);
                            if (!mounted) return;
                            setState(() {
                              _storedPassword = trimmed;
                              _driver['password'] = trimmed;
                            });
                            await _saveDriverProfileCache();
                          },
                        ),
                        _InfoRow(
                          label: "License No:",
                          value: _licenseNo.isNotEmpty ? _licenseNo : "—",
                          trailingText: null,
                          showDivider: true,
                        ),
                        _InfoRow(
                          label: "License Type:",
                          value: _licenseType.isNotEmpty ? _licenseType : "—",
                          trailingText: null,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 111),
                

                  // logout button (outlined pill)
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: red, width: 1),
                        shape: const StadiumBorder(),
                        foregroundColor: red,
                        backgroundColor: Colors.white,
                        disabledForegroundColor: red,
                        disabledBackgroundColor: Colors.white,
                      ),
                      onPressed: _loggingOut ? () {} : _logout,
                      child: _loggingOut
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: red,
                              ),
                            )
                          : const Text(
                              "Log out",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DutyChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color red;
  final bool enabled;
  final VoidCallback onTap;

  const _DutyChoiceButton({
    required this.label,
    required this.selected,
    required this.red,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? red : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? red : const Color(0xFFE5E5E5),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF4A4A4A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String? trailingText;
  final bool showDivider;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.trailingText,
    required this.showDivider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF007CFF);

    Widget rowContent = SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF797979),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailingText != null) ...[
            const SizedBox(width: 14),
            Text(
              trailingText!,
              style: const TextStyle(
                color: blue,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          onTap != null
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: rowContent,
                )
              : rowContent,
          if (showDivider)
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F1F1)),
        ],
      ),
    );
  }
}
