import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:ice_cream/auth.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:ice_cream/client/create_page.dart';
import 'package:ice_cream/client/home_page.dart';
import 'package:ice_cream/client/landing_page.dart';
import 'package:ice_cream/client/login_page.dart';
import 'package:ice_cream/client/order/manage_address.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _account;
  bool _loading = true;
  bool _loggingOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await Auth.getToken();
    final cached = await Auth.getCachedCustomer();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _account = cached;
          _error = cached != null && cached.isNotEmpty
              ? 'Session expired. Please log in again.'
              : 'Session ended. Log in to view your profile.';
          _loading = false;
        });
      }
      return;
    }
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _account = cached;
        _loading = false;
      });
    }
    // Google Firebase ID tokens are JWTs (contain dots) and are not valid for
    // Laravel /account. Keep cached session data instead of forcing a 401 refresh.
    if (token.contains('.')) return;
    try {
      final account = await Auth().fetchAccount();
      if (mounted) {
        setState(() {
          _account = account;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          if (cached != null && cached.isNotEmpty) _account = cached;
          _loading = false;
        });
      }
    }
  }

  String _displayName() {
    if (_account == null) return 'Loading...';
    final first = _account!['firstname'] as String? ?? '';
    final last = _account!['lastname'] as String? ?? '';
    return '${first.trim()} ${last.trim()}'.trim().isEmpty ? 'Profile' : '${first.trim()} ${last.trim()}'.trim();
  }

  Widget _profileAvatar() {
    final imageUrl = _account?['image_url'] as String?;
    final imagePath = _account?['image'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 55,
        backgroundImage: NetworkImage(imageUrl),
      );
    }
    if (imagePath != null && imagePath.isNotEmpty) {
      final baseUrl = Auth.apiBaseUrl.replaceAll('/api/v1', '');
      return CircleAvatar(
        radius: 55,
        backgroundImage: NetworkImage('$baseUrl/$imagePath'),
      );
    }
    return const CircleAvatar(
      radius: 55,
      backgroundImage: AssetImage("lib/client/profile/images/prof.png"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                MediaQuery.of(context).orientation == Orientation.landscape;

            if (!isLandscape) {
              // PORTRAIT: Make scrollable to prevent bottom overflow.
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                  // --- Close Button (Updated) ---
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 20, right: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () {
                            final nav = Navigator.of(context);
                            if (nav.canPop()) {
                              nav.pop();
                            } else {
                              nav.pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => const HomePage(),
                                ),
                              );
                            }
                          },
                          child: Container(
                            height: 42,
                            width: 42,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF2F2F2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // --- Profile Image ---
                  if (_loading)
                    const SizedBox(
                      height: 110,
                      child: AppLoadingCenter(),
                    )
                  else
                    _profileAvatar(),

                  const SizedBox(height: 15),

                  // --- Name ---
                  Text(
                    _displayName(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1C1B1F),
                    ),
                  ),
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_error == 'Session expired. Please log in again.' ||
                        _error == 'Session ended. Log in to view your profile.')
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            ).then((_) {
                              if (mounted) _loadAccount();
                            });
                          },
                          child: const Text('Log in again'),
                        ),
                      ),
                  ],

                  const SizedBox(height: 25),

                  // --- Setting Tiles ---
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.person,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "Account information",
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ViewProfilePage(),
                        ),
                      );
                      if (mounted) _loadAccount();
                    },
                  ),
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.location_on,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "Address Details",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddressDetailsPage(),
                        ),
                      );
                    },
                  ),
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.key,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "Change password",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChangePPasswordPage(),
                        ),
                      );
                    },
                  ),
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.info,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "App Info",
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => const AppInfoDialog(),
                      );
                    },
                  ),
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.policy,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "Privacy Policy",
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => const PrivacyPolicyDialog(),
                      );
                    },
                  ),
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.help,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "FAQ",
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => const FaqDialog(),
                      );
                    },
                  ),
                  _settingsTile(
                    iconWidget: const Icon(
                      Symbols.delete,
                      size: 23,
                      color: Colors.black87,
                      fill: 0,
                      weight: 300,
                      grade: 0,
                      opticalSize: 24,
                    ),
                    text: "Delete account",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DeleteAccount(),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  // --- Logout Button ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE3001B),
                          disabledForegroundColor: const Color(0xFFE3001B),
                          side: const BorderSide(color: Color(0xFFE3001B), width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _loggingOut
                            ? null
                            : () async {
                                setState(() => _loggingOut = true);
                                try {
                                  await Auth().signOut();
                                  if (!mounted) return;
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (_) => const LoginPage()),
                                    (route) => false,
                                  );
                                } catch (_) {
                                  if (mounted) setState(() => _loggingOut = false);
                                }
                              },
                        child: _loggingOut
                            ? const AppLoadingIndicator()
                            : const Text(
                                'Log out',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFE3001B),
                                  fontWeight: FontWeight.w400,
                                ),
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
            } else {
              // LANDSCAPE: Prevent bottom overflow using a ScrollView.
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // --- Close Button (Updated) ---
                        Padding(
                          padding: const EdgeInsets.only(top: 10, left: 20, right: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () {
                                final nav = Navigator.of(context);
                                if (nav.canPop()) {
                                  nav.pop();
                                } else {
                                  nav.pushReplacement(
                                    MaterialPageRoute(
                                      builder: (context) => const HomePage(),
                                    ),
                                  );
                                }
                                },
                                child: Container(
                                  height: 42,
                                  width: 42,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF2F2F2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, size: 22),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 25),

                        // --- Profile Image ---
                        if (_loading)
                          const SizedBox(
                            height: 110,
                            child: AppLoadingCenter(),
                          )
                        else
                          _profileAvatar(),

                        const SizedBox(height: 15),

                        // --- Name ---
                        Text(
                          _displayName(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1C1B1F),
                          ),
                        ),

                        const SizedBox(height: 25),

                        // --- Setting Tiles ---
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.person,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "Account information",
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ViewProfilePage(),
                              ),
                            );
                            if (mounted) _loadAccount();
                          },
                        ),
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.location_on,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "Address Details",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AddressDetailsPage(),
                              ),
                            );
                          },
                        ),
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.key,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "Change password",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChangePPasswordPage(),
                              ),
                            );
                          },
                        ),
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.info,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "App Info",
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => const AppInfoDialog(),
                            );
                          },
                        ),
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.policy,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "Privacy Policy",
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => const PrivacyPolicyDialog(),
                            );
                          },
                        ),
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.help,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "FAQ",
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => const FaqDialog(),
                            );
                          },
                        ),
                        _settingsTile(
                          iconWidget: const Icon(
                            Symbols.delete,
                            size: 23,
                            color: Colors.black87,
                            fill: 0,
                            weight: 300,
                            grade: 0,
                            opticalSize: 24,
                          ),
                          text: "Delete account",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DeleteAccount(),
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFE3001B),
                                disabledForegroundColor: const Color(0xFFE3001B),
                                side: const BorderSide(color: Color(0xFFE3001B), width: 1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _loggingOut
                                  ? null
                                  : () async {
                                      setState(() => _loggingOut = true);
                                      try {
                                        await Auth().signOut();
                                        if (!mounted) return;
                                        Navigator.pushAndRemoveUntil(
                                          context,
                                          MaterialPageRoute(builder: (_) => const LandingPage()),
                                          (route) => false,
                                        );
                                      } catch (_) {
                                        if (mounted) setState(() => _loggingOut = false);
                                      }
                                    },
                              child: _loggingOut
                                  ? const AppLoadingIndicator()
                                  : const Text(
                                      'Log out',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFFE3001B),
                                        fontWeight: FontWeight.w400,
                                      ),
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
          },
        ),
      ),
    );
  }

  Widget _settingsTile({
    required Widget iconWidget,
    required String text,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              iconWidget,
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 15,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Address Selection page: loads real address from API (GET /account), Edit/Add call PUT /address.
/// When [forCheckout] is true, back button pops with the currently selected address (for use on Place Order).
class AddressDetailsPage extends StatefulWidget {
  const AddressDetailsPage({super.key, this.forCheckout = false});

  final bool forCheckout;

  /// Build address map from API account (for display on checkout or elsewhere).
  static Map<String, dynamic> addressMapFromAccount(Map<String, dynamic> account) {
    final first = account['firstname'] as String? ?? '';
    final last = account['lastname'] as String? ?? '';
    final contact = (account['contact_no'] ?? '').toString().trim();
    final street = (account['street_name'] ?? '').toString().trim();
    final province = (account['province'] ?? '').toString().trim();
    final city = (account['city'] ?? '').toString().trim();
    final barangay = (account['barangay'] ?? '').toString().trim();
    final postalCode = (account['postal_code'] ?? '').toString().trim();
    final label = (account['label_as'] ?? 'Home').toString().trim();
    final fullAddress = (account['full_address'] ?? '').toString();
    return {
      'firstName': first,
      'lastName': last,
      'contact': contact,
      'street': street,
      'province': province.isEmpty ? 'Cebu' : province,
      'city': city.isEmpty ? 'Mandaue' : city,
      'barangay': barangay,
      'postalCode': postalCode.isEmpty ? (city.toLowerCase().contains('lapu') ? '6015' : '6014') : postalCode,
      'label': label.isEmpty ? 'Home' : label,
      'fullAddress': fullAddress.isNotEmpty ? fullAddress : '$street, $barangay, $city${city.isNotEmpty ? ' City' : ''}, $province, $postalCode'.replaceAll(RegExp(r',\s*,'), ',').trim(),
    };
  }

  @override
  State<AddressDetailsPage> createState() => _AddressDetailsPageState();
}

class _AddressDetailsPageState extends State<AddressDetailsPage> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  String? _error;

  /// Map API address (from GET /addresses) to display format.
  static Map<String, dynamic> _apiAddressToDisplay(Map<String, dynamic> a) {
    final first = (a['firstname'] ?? '').toString().trim();
    final last = (a['lastname'] ?? '').toString().trim();
    final contact = (a['contact_no'] ?? '').toString().trim();
    final street = (a['street_name'] ?? '').toString().trim();
    final province = (a['province'] ?? 'Cebu').toString().trim();
    final city = (a['city'] ?? '').toString().trim();
    final barangay = (a['barangay'] ?? '').toString().trim();
    final postalCode = (a['postal_code'] ?? '').toString().trim();
    final label = (a['label_as'] ?? 'Home').toString().trim();
    final fullAddress = (a['full_address'] ?? '').toString().trim();
    final id = a['id'];
    final isDefault = a['is_default'] == true;
    return {
      'id': id,
      'firstName': first,
      'lastName': last,
      'contact': contact,
      'street': street,
      'province': province.isEmpty ? 'Cebu' : province,
      'city': city,
      'barangay': barangay,
      'postalCode': postalCode.isEmpty ? (city.toLowerCase().contains('lapu') ? '6015' : '6014') : postalCode,
      'label': label.isEmpty ? 'Home' : label,
      'fullAddress': fullAddress.isNotEmpty ? fullAddress : '$street, $barangay, $city${city.isNotEmpty ? ' City' : ''}, ${province.isEmpty ? 'Cebu' : province}, $postalCode'.replaceAll(RegExp(r',\s*,'), ', ').trim(),
      'is_default': isDefault,
    };
  }

  /// [showFullScreenLoading] — only for the first load; after add/edit/refresh use `false`
  /// so the list stays visible and `setState` reliably updates when returning from the form.
  Future<void> _loadAddresses({bool showFullScreenLoading = true}) async {
    if (!mounted) return;
    if (showFullScreenLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final list = await Auth().getAddresses();
      if (!mounted) return;
      final display = list.map(_apiAddressToDisplay).toList();
      int selected = 0;
      for (int i = 0; i < display.length; i++) {
        if (display[i]['is_default'] == true) {
          selected = i;
          break;
        }
      }
      setState(() {
        _addresses = display;
        _selectedIndex = display.isEmpty ? 0 : selected.clamp(0, display.length - 1);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        if (showFullScreenLoading) _addresses = [];
        _loading = false;
      });
    }
  }

  /// Laravel may return the row as `data` or nested under `address`.
  static Map<String, dynamic>? _unwrapAddressApiMap(Map<String, dynamic> raw) {
    final nested = raw['address'];
    if (nested is Map<String, dynamic>) return Map<String, dynamic>.from(nested);
    if (raw.containsKey('street_name') || raw.containsKey('firstname') || raw.containsKey('id')) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> _saveAddressFromForm(Map<String, dynamic> result) async {
    try {
      final firstname = (result['firstName'] ?? '').toString().trim();
      final lastname = (result['lastName'] ?? '').toString().trim();
      final contactNo = (result['contact'] ?? '').toString().trim();
      final province = (result['province'] ?? '').toString().trim();
      final city = (result['city'] ?? '').toString().trim();
      final barangay = (result['barangay'] ?? '').toString().trim();
      final postalCode = (result['postalCode'] ?? '').toString().trim();
      final streetName = (result['street'] ?? '').toString().trim();
      final labelAs = (result['label'] ?? '').toString().trim();
      final id = result['id'];
      late final Map<String, dynamic> apiPayload;
      if (id != null) {
        final idStr = id.toString();
        if (idStr.isEmpty) {
          apiPayload = await Auth().addAddress(firstname: firstname.isEmpty ? null : firstname, lastname: lastname.isEmpty ? null : lastname, contactNo: contactNo.isEmpty ? null : contactNo, province: province.isEmpty ? null : province, city: city.isEmpty ? null : city, barangay: barangay.isEmpty ? null : barangay, postalCode: postalCode.isEmpty ? null : postalCode, streetName: streetName.isEmpty ? null : streetName, labelAs: labelAs.isEmpty ? null : labelAs, isDefault: _addresses.isEmpty);
        } else {
          apiPayload = await Auth().updateAddressById(idStr, firstname: firstname.isEmpty ? null : firstname, lastname: lastname.isEmpty ? null : lastname, contactNo: contactNo.isEmpty ? null : contactNo, province: province.isEmpty ? null : province, city: city.isEmpty ? null : city, barangay: barangay.isEmpty ? null : barangay, postalCode: postalCode.isEmpty ? null : postalCode, streetName: streetName.isEmpty ? null : streetName, labelAs: labelAs.isEmpty ? null : labelAs);
        }
      } else {
        apiPayload = await Auth().addAddress(firstname: firstname.isEmpty ? null : firstname, lastname: lastname.isEmpty ? null : lastname, contactNo: contactNo.isEmpty ? null : contactNo, province: province.isEmpty ? null : province, city: city.isEmpty ? null : city, barangay: barangay.isEmpty ? null : barangay, postalCode: postalCode.isEmpty ? null : postalCode, streetName: streetName.isEmpty ? null : streetName, labelAs: labelAs.isEmpty ? null : labelAs, isDefault: _addresses.isEmpty);
      }
      if (!mounted) return;
      final row = _unwrapAddressApiMap(apiPayload);
      if (row != null) {
        final display = _apiAddressToDisplay(row);
        setState(() {
          final i = _addresses.indexWhere((e) => e['id'] != null && e['id'].toString() == display['id'].toString());
          if (i >= 0) {
            _addresses = List<Map<String, dynamic>>.from(_addresses);
            _addresses[i] = display;
          } else {
            _addresses = [..._addresses, display];
          }
        });
      }
      // Reload after the route transition so GET sees the latest row; keep list on screen (no full-screen loader).
      if (!mounted) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAddresses(showFullScreenLoading: false).then((_) {
          if (!mounted || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Address saved successfully.'), behavior: SnackBarBehavior.floating),
          );
        });
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _onSelectAddress(int index) async {
    setState(() => _selectedIndex = index);
    final a = _addresses[index];
    if (a['is_default'] == true) return;
    final id = a['id'];
    if (id == null) return;
    try {
      await Auth().setDefaultAddress(id.toString());
      if (mounted) await _loadAddresses(showFullScreenLoading: false);
    } catch (_) {
      if (mounted) await _loadAddresses(showFullScreenLoading: false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  String _phoneDisplay(String contact) {
    final s = contact.replaceAll(RegExp(r'[\s\-+()]'), '');
    if (s.length >= 10) {
      return "(+63) ${s.substring(0, 3)} ${s.substring(3, 6)} ${s.substring(6)}";
    }
    return contact;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 43,
        leading: Transform.translate(
          offset: const Offset(20, 0),
          child: SizedBox(
            child: Material(
              color: const Color(0xFFF2F2F2),
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (widget.forCheckout && _addresses.isNotEmpty) {
                    Navigator.pop(context, _addresses[_selectedIndex]);
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: const Center(child: Icon(Icons.arrow_back, size: 20, color: Colors.black)),
              ),
            ),
          ),
        ),
        title: const Text(
          "Address Selection",
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18, color: Colors.black),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                "Address",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF505050)),
              ),
            ),
            Expanded(
              child: _loading
                  ? const AppLoadingCenter()
                  : RefreshIndicator(
                      onRefresh: () => _loadAddresses(showFullScreenLoading: false),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: _addresses.isEmpty ? 1 : _addresses.length,
                        itemBuilder: (context, index) {
                          if (_addresses.isEmpty) {
                            return SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.35,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Text(
                                    _error ?? 'No saved addresses yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _error != null ? Colors.red : const Color(0xFF505050),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          final a = _addresses[index];
                          final name = "${a["firstName"] ?? ""} ${a["lastName"] ?? ""}".trim();
                          final phone = _phoneDisplay((a["contact"] ?? "").toString());
                          final fullAddress = a["fullAddress"] as String? ?? "";
                          final isSelected = _selectedIndex == index;
                          return Padding(
                            key: ValueKey<Object?>(a['id'] ?? 'addr_$index'),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE0E0E0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () => _onSelectAddress(index),
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          margin: const EdgeInsets.only(top: 2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected ? const Color(0xFFE3001B) : const Color(0xFF9D9D9D),
                                              width: 2,
                                            ),
                                            color: isSelected ? const Color(0xFFE3001B) : Colors.transparent,
                                          ),
                                          child: isSelected
                                              ? const Center(child: Icon(Icons.circle, size: 8, color: Colors.white))
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name.isEmpty ? "—" : name,
                                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1C1B1F)),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () async {
                                                    final initial = Map<String, dynamic>.from(a);
                                                    final result = await Navigator.push<Map<String, dynamic>>(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => AddressFormPage(initialAddress: initial),
                                                      ),
                                                    );
                                                    if (result != null && mounted) {
                                                      await _saveAddressFromForm(result);
                                                    }
                                                  },
                                                  child: const Text(
                                                    "Edit",
                                                    style: TextStyle(fontSize: 14, color: Color(0xFF898989), fontWeight: FontWeight.w500),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              phone,
                                              style: const TextStyle(fontSize: 13, color: Color(0xFF505050)),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              fullAddress,
                                              style: const TextStyle(fontSize: 13, color: Color(0xFF1C1B1F), height: 1.35),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (a['is_default'] == true) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFE3001B)),
                                                ),
                                                child: const Text(
                                                  "Default",
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF1C1B1F)),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddressFormPage(initialAddress: null),
                    ),
                  );
                  if (result != null && mounted) {
                    await _saveAddressFromForm(result);
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE3001B),
                  side: const BorderSide(color: Color(0xFFE3001B)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, size: 22, color: Color(0xFFE3001B)),
                label: const Text("Add a new address", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFFE3001B))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ViewProfilePage extends StatefulWidget {
  const ViewProfilePage({super.key});

  @override
  State<ViewProfilePage> createState() => _ViewProfilePageState();
}

class _ViewProfilePageState extends State<ViewProfilePage> {
  Map<String, dynamic>? _account;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await Auth.getToken();
    final cached = await Auth.getCachedCustomer();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _account = cached;
          _error = cached != null && cached.isNotEmpty
              ? 'Session expired. Please log in again.'
              : 'Session ended. Log in to view your profile.';
          _loading = false;
        });
      }
      return;
    }
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _account = cached;
        _loading = false;
      });
    }
    // Google Firebase ID tokens are JWTs (contain dots) and are not valid for
    // Laravel /account. Keep cached session data instead of forcing a 401 refresh.
    if (token.contains('.')) return;
    try {
      final account = await Auth().fetchAccount();
      if (mounted) {
        setState(() {
          _account = account;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          if (cached != null && cached.isNotEmpty) _account = cached;
          _loading = false;
        });
      }
    }
  }

  Widget _profileAvatar(Map<String, dynamic> account) {
    final imageUrl = account['image_url'] as String?;
    final imagePath = account['image'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 55,
        backgroundImage: NetworkImage(imageUrl),
      );
    }
    if (imagePath != null && imagePath.isNotEmpty) {
      final baseUrl = Auth.apiBaseUrl.replaceAll('/api/v1', '');
      return CircleAvatar(
        radius: 55,
        backgroundImage: NetworkImage('$baseUrl/$imagePath'),
      );
    }
    return const CircleAvatar(
      radius: 55,
      backgroundImage: AssetImage("lib/client/profile/images/prof.png"),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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

              const SizedBox(height: 40),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: AppLoadingCenter(),
                )
              else if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _loadAccount,
                          child: const Text('Retry'),
                        ),
                        if (_error == 'Session expired. Please log in again.' ||
                            _error == 'Session ended. Log in to view your profile.') ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginPage(),
                                ),
                              ).then((_) {
                                if (mounted) _loadAccount();
                              });
                            },
                            child: const Text('Log in again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else if (_account != null) ...[
                // PROFILE PHOTO (CENTER)
                Center(
                  child: _profileAvatar(_account!),
                ),

                const SizedBox(height: 30),

                // NAME ROW
                Row(
                  children: [
                    Expanded(
                      child: _fieldColumn(
                        label: "First name",
                        value: _account!['firstname'] as String? ?? '',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _fieldColumn(
                        label: "Last name",
                        value: _account!['lastname'] as String? ?? '',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // PHONE + EMAIL ROW
                Row(
                  children: [
                    Expanded(
                      child: _fieldColumn(
                        label: "Phone number",
                        value: _account!['contact_no'] as String? ?? '—',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _fieldColumn(
                        label: "Email address",
                        value: _account!['email'] as String? ?? '—',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                // BUTTON
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final updated = await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditProfilePage(account: _account!),
                          ),
                        );
                        if (updated != null && mounted) {
                          setState(() {
                            _account = updated;
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        backgroundColor: Color(0xFF007CFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Edit Profile",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // FIELD COMPONENT
  Widget _fieldColumn({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            maxLines: 1, // only one line
            overflow: TextOverflow.ellipsis, // show dots if text overflows
          ),
        ),
      ],
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> account;

  const EditProfilePage({super.key, required this.account});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _firstnameController;
  late TextEditingController _lastnameController;
  late TextEditingController _contactNoController;
  late TextEditingController _emailController;
  String? _selectedImagePath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstnameController = TextEditingController(text: widget.account['firstname'] as String? ?? '');
    _lastnameController = TextEditingController(text: widget.account['lastname'] as String? ?? '');
    _contactNoController = TextEditingController(text: widget.account['contact_no'] as String? ?? '');
    _emailController = TextEditingController(text: widget.account['email'] as String? ?? '');
  }

  @override
  void dispose() {
    _firstnameController.dispose();
    _lastnameController.dispose();
    _contactNoController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (xFile != null && mounted) {
      setState(() => _selectedImagePath = xFile.path);
    }
  }

  Widget _profileAvatar() {
    if (_selectedImagePath != null) {
      return CircleAvatar(
        radius: 55,
        backgroundImage: FileImage(File(_selectedImagePath!)),
      );
    }
    final imageUrl = widget.account['image_url'] as String?;
    final imagePath = widget.account['image'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 55,
        backgroundImage: NetworkImage(imageUrl),
      );
    }
    if (imagePath != null && imagePath.isNotEmpty) {
      final baseUrl = Auth.apiBaseUrl.replaceAll('/api/v1', '');
      return CircleAvatar(
        radius: 55,
        backgroundImage: NetworkImage('$baseUrl/$imagePath'),
      );
    }
    return const CircleAvatar(
      radius: 55,
      backgroundImage: AssetImage("lib/client/profile/images/prof.png"),
    );
  }

  Future<void> _saveChanges() async {
    final firstname = _firstnameController.text.trim();
    final lastname = _lastnameController.text.trim();
    final contactNo = _contactNoController.text.trim();

    if (firstname.isEmpty || lastname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First name and last name are required')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await Auth().updateProfile(
        firstname: firstname,
        lastname: lastname,
        contactNo: contactNo.isEmpty ? null : contactNo,
        imagePath: _selectedImagePath,
      );
      if (mounted) {
        Navigator.pop(context, updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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

              const SizedBox(height: 40),

              // PROFILE PHOTO (CENTER)
              Center(
                child: Stack(
                  children: [
                    _profileAvatar(),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFF5F5F5),
                          child: const Icon(
                            Symbols.add_a_photo,
                            size: 20,
                            color: Color(0xFF1C1B1F),
                            fill: 0,
                            weight: 400,
                            grade: 0,
                            opticalSize: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // NAME ROW
              Row(
                children: [
                  Expanded(
                    child: _EditColumn(label: "First name", controller: _firstnameController),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _EditColumn(label: "Last name", controller: _lastnameController),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // PHONE + EMAIL ROW (email read-only)
              Row(
                children: [
                  Expanded(
                    child: _EditColumn(label: "Phone number", controller: _contactNoController),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _EditColumn(
                      label: "Email address",
                      controller: _emailController,
                      readOnly: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              // BUTTON
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE3001B)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "Discard",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFFE3001B),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      backgroundColor: const Color(0xFF007CFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _saving
                        ? const AppLoadingIndicator(color: Colors.white, size: 20, strokeWidth: 2)
                        : const Text(
                            "Save Changes",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w400,
                            ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // FIELD COMPONENT
  Widget _EditColumn({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD7D7D7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD7D7D7)),
            ),
          ),
          maxLines: 1,
        ),
      ],
    );
  }
}



class ChangePPasswordPage extends StatefulWidget {
  const ChangePPasswordPage({super.key});

  @override
  State<ChangePPasswordPage> createState() => _ChangePPasswordPageState();
}

class _ChangePPasswordPageState extends State<ChangePPasswordPage> {
  final TextEditingController emailController = TextEditingController();
  bool hasText = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Listen to input changes
    emailController.addListener(() {
      setState(() {
        hasText = emailController.text.isNotEmpty;
        _error = null;
      });
    });

    // Pre-fill email with logged-in user
    _loadLoggedInEmail();
  }

  Future<void> _loadLoggedInEmail() async {
    final cached = await Auth.getCachedCustomer();
    final email = cached?['email'] as String?;
    if (email != null && email.isNotEmpty && mounted) {
      emailController.text = email.trim();
      setState(() => hasText = true);
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
                  "Change Password",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1C),
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  "Enter your email address to continue",
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

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: (hasText && !_sending)
                        ? () async {
                            setState(() {
                              _sending = true;
                              _error = null;
                            });
                            try {
                              await Auth().changePasswordSendOtp(
                                email: emailController.text.trim(),
                              );
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OTPscode(
                                    email: emailController.text.trim(),
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _error = e.toString().replaceFirst('Exception: ', '');
                                  _sending = false;
                                });
                              }
                            } finally {
                              if (mounted) setState(() => _sending = false);
                            }
                          }
                        : null,
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
                    child: _sending
                        ? const AppLoadingOnBrand()
                        : const Text(
                            'Continue',
                            style: TextStyle(
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

class OTPscode extends StatefulWidget {
  const OTPscode({super.key, required this.email});
  final String email;

  @override
  State<OTPscode> createState() => _OTPscodeState();
}

class _OTPscodeState extends State<OTPscode> {
  List<String> otp = ["", "", "", ""];
  bool _verifying = false;
  String? _error;

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
                  onPressed: (isFilled && !_verifying)
                      ? () async {
                          setState(() {
                            _verifying = true;
                            _error = null;
                          });
                          try {
                            await Auth().changePasswordVerifyOtp(
                              otp: otp.join(),
                            );
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChangePasswordPage(),
                              ),
                            );
                          } catch (e) {
                            if (mounted) {
                              setState(() {
                                _error = e.toString().replaceFirst('Exception: ', '');
                                _verifying = false;
                              });
                            }
                          } finally {
                            if (mounted) setState(() => _verifying = false);
                          }
                        }
                      : null,
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith<Color>((
                      states,
                    ) {
                      if (isFilled && !_verifying) {
                        return const Color(0xFFE3001B);
                      }
                      return const Color(0xFFFF9CA7);
                    }),
                    shape: MaterialStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    elevation: MaterialStateProperty.all(0),
                  ),
                  child: _verifying
                      ? const AppLoadingOnBrand()
                      : const Text(
                          'Continue',
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
                  Text("Didn’t get OTP? ", style: TextStyle(fontSize: 14.85)),
                  GestureDetector(
                    onTap: _verifying ? null : () async {
                      try {
                        await Auth().changePasswordResendOtp(email: widget.email);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('A new code has been sent to your email.')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                          );
                        }
                      }
                    },
                    child: const Text(
                      "Resend OTP",
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
        cursorHeight: 18,
        cursorWidth: 2,
        cursorRadius: const Radius.circular(3),
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


class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController currentPasswordController =
      TextEditingController();
  bool _saving = false;
  bool get _isContinueEnabled {
    return newPasswordController.text.isNotEmpty &&
        confirmPasswordController.text.isNotEmpty &&
        currentPasswordController.text.isNotEmpty;
  }

  bool _obscureNewPassword = true;
  bool _obscureCurrentPassword = true;
  bool _obscureConfirmPassword = true;
  bool keepMeLoggedIn = true;
  bool _showPasswordEyee = false;
  bool _currentPasswordEyee = false;
  bool _showConfirmPasswordEyee = false;

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

    currentPasswordController.addListener(() {
      setState(() {
        _currentPasswordEyee = currentPasswordController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    currentPasswordController.dispose();
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
              crossAxisAlignment: CrossAxisAlignment.start,
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

                const SizedBox(height: 40), // 🔥 SAME SPACING AS FORGOT PAGE

                const Text(
                  "Change password",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1B1F),
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  "Your password must be at least 6 characters",

                  style: TextStyle(fontSize: 15, color: Color(0xFF1C1B1F)),
                ),

                const SizedBox(height: 30),

                // current PASSWORD
                Container(
                  decoration: _shadowBox(),
                  child: TextField(
                    controller: currentPasswordController,
                    obscureText: _obscureCurrentPassword,
                    style: const TextStyle(fontSize: 14),
                    cursorColor: Colors.black,
                    cursorHeight: 18,
                    decoration: InputDecoration(
                      hintText: "Current password",
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
                      suffixIcon: _currentPasswordEyee
                          ? IconButton(
                              icon: Icon(
                                _obscureCurrentPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 22,
                                color: _obscureCurrentPassword
                                    ? const Color(0xFF565656)
                                    : const Color(
                                        0xFF565656,
                                      ), // red when visible
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureCurrentPassword =
                                      !_obscureCurrentPassword;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // new PASSWORD
                Container(
                  decoration: _shadowBox(),
                  child: TextField(
                    controller: newPasswordController,
                    obscureText: _obscureNewPassword,
                    style: const TextStyle(fontSize: 14),
                    cursorColor: Colors.black,
                    cursorHeight: 18,
                    decoration: InputDecoration(
                      hintText: "New password",
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
                                        0xFF565656,
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
                    decoration: InputDecoration(
                      hintText: "Re-type new password",
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
                                        0xFF565656,
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

                const SizedBox(height: 20),
                // Keep me logged in
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: keepMeLoggedIn,
                        onChanged: (v) => setState(() => keepMeLoggedIn = v ?? true),
                        activeColor: const Color(0xFFE3001B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => keepMeLoggedIn = !keepMeLoggedIn),
                      child: const Text(
                        'Keep me logged in',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1C1B1F),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: AbsorbPointer(
                    absorbing: !_isContinueEnabled || _saving,
                    child: ElevatedButton(
                      onPressed: _isContinueEnabled && !_saving
                          ? () async {
                              final current = currentPasswordController.text;
                              final newPass = newPasswordController.text;
                              final confirm = confirmPasswordController.text;
                              if (newPass != confirm) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('New passwords do not match.')),
                                );
                                return;
                              }
                              setState(() => _saving = true);
                              try {
                                final result = await Auth().changePasswordUpdate(
                                  currentPassword: current,
                                  password: newPass,
                                  passwordConfirmation: confirm,
                                  keepLoggedIn: keepMeLoggedIn,
                                );
                                if (!mounted) return;
                                final loggedOut = result['logged_out'] == true;
                                if (loggedOut && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password updated. Please log in again.')),
                                  );
                                }
                                if (!mounted) return;
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChangeSuccessPage(loggedOut: loggedOut),
                                  ),
                                  (route) => false,
                                );
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _saving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                                  );
                                }
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isContinueEnabled && !_saving
                            ? const Color(0xFFE3001B)
                            : const Color(0xFFFF9CA7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _saving
                          ? const AppLoadingOnBrand()
                          : const Text(
                              'Change password',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFFFFFFFF),
                              ),
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
// Border Box style (no shadow)
BoxDecoration _shadowBox() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: const Color(0xFFA9A9A9), // dark gray border
      width: 1, // border thickness
    ),
  );
}

class ChangeSuccessPage extends StatelessWidget {
  const ChangeSuccessPage({super.key, required this.loggedOut});
  /// True if user chose to be logged out after password change; false if "keep logged in".
  final bool loggedOut;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    void goNext() async {
      if (loggedOut) {
        await Auth().signOut();
        if (!context.mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
          (route) => false,
        );
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFC5C8FF),
      body: SafeArea(
        child: isLandscape
            ? // LANDSCAPE
            SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: size.height - MediaQuery.of(context).padding.vertical,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Center(
                            child: Image.asset(
                              'lib/client/profile/images/ChangePpassword.jpg',
                              width: size.width * 0.4,
                              height: size.height * 0.3,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'Password changed successfully!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 220,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: goNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF804EFF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : // PORTRAIT
            SizedBox(
                height: size.height,
                width: size.width,
                child: Column(
                  children: [
                    const SizedBox(height: 30),
                    Center(
                      child: Image.asset(
                        'lib/client/profile/images/ChangePpassword.jpg',
                        width: 376,
                        height: 376,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'Password changed successfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 320,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: goNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF804EFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
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

class DeleteAccount extends StatefulWidget {
  const DeleteAccount({super.key});

  @override
  State<DeleteAccount> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends State<DeleteAccount> {
  String? selectedReason;
  String? otherReasonText;

  final List<String> reasons = [
    "I no longer use this app",
    "I have another account",
    "Privacy concerns",
    "I receive too many notifications or emails",
    "I found better prices or services elsewhere",
    "I'm not satisfied with the app experience",
    "Checkout or payment problems",
    "Delivery or order issues",
    "Other (please specify)",
  ];

  @override
  Widget build(BuildContext context) {
    // Check if the "Other (please specify)" is selected
    final bool isOtherSelected = selectedReason == reasons.last;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              /// --- CUSTOM BACK BUTTON ---
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

              const SizedBox(height: 0),

              const Text(
                "Delete account",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 0),

              const Text(
                "If you need to delete an account and you're prompted to provide a reason.",
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF1C1B1F),
                  fontWeight: FontWeight.w400,
                ),
              ),

              const SizedBox(height: 5),

              /// --- REASON OPTIONS ---
              Expanded(
                child: ListView(
                  children: [
                    ...List.generate(
                      reasons.length,
                      (index) {
                        bool isSelected = selectedReason == reasons[index];
                        bool showTextField = isSelected && reasons[index] == reasons.last;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedReason = reasons[index];
                              if (selectedReason != reasons.last) {
                                otherReasonText = null;
                              }
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: isSelected
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
                                  dense: true,
                                  leading: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF007CFF)
                                              : const Color(0xFF434343),
                                          width: 1,
                                        ),
                                      ),
                                      child: isSelected
                                          ? Center(
                                              child: Container(
                                                width: 7,
                                                height: 7,
                                                decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Color(0xFF007CFF),
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  title: Transform.translate(
                                    offset: const Offset(-10, 0),
                                    child: Text(
                                      reasons[index],
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  minLeadingWidth: 7,
                                  onTap: null, // Handled by GestureDetector
                                ),
                                if (showTextField)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                      bottom: 10,
                                      top: 0,
                                    ),
                                    child: Transform.translate(
                                      offset: const Offset(0, -3),
                                      child: Stack(
                                        children: [
                                          SizedBox(
                                            // Increased the minimum height for the box
                                            height: 70, // Slightly taller than default TextField min height (2 lines ~48)
                                            child: TextField(
                                              autofocus: true,
                                              minLines: 3, // Increased minLines from 2 to 3 for more height
                                              maxLines: 4,
                                              maxLength: 150,
                                              decoration: InputDecoration(
                                                hintText: 'Write a message here',
                                                hintStyle: const TextStyle(fontSize: 12),
                                                filled: true,
                                                fillColor: const Color(0xFFE9E9E9),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(5),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFCACACA),
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(5),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFCACACA),
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(5),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFCACACA),
                                                  ),
                                                ),
                                                isDense: true,
                                                counterText: "", // Hide default counter
                                              ),
                                              style: const TextStyle(fontSize: 12),
                                              onChanged: (value) {
                                                setState(() {
                                                  otherReasonText = value;
                                                });
                                              },
                                            ),
                                          ),
                                          Positioned(
                                            right: 15, // was 8, moved further left
                                            bottom: 8,
                                            child: Text(
                                              '${(otherReasonText ?? '').length}/150',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF7C7C7C),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              /// --- CONTINUE BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 55,
                child: AbsorbPointer(
                  absorbing: selectedReason == null || (isOtherSelected && (otherReasonText == null || otherReasonText!.trim().isEmpty)),
                  child: ElevatedButton(
                    onPressed: () {
                      final other = (otherReasonText ?? '').trim();
                      final selected = (selectedReason ?? '').trim();
                      final reason = isOtherSelected ? other : selected;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DeleteConfirmPage(
                            reason: reason.isEmpty ? null : reason,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (selectedReason == null || (isOtherSelected && (otherReasonText == null || otherReasonText!.trim().isEmpty)))
                          ? const Color(0xFFFF9CA7)
                          : const Color(0xFFE3001B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "Continue",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFFFFFFFF),
                      ),
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

class DeleteConfirmPage extends StatefulWidget {
  const DeleteConfirmPage({super.key, this.reason});
  final String? reason;

  @override
  State<DeleteConfirmPage> createState() => _DeleteConfirmPageState();
}

class _DeleteConfirmPageState extends State<DeleteConfirmPage> {
  bool _obscurePassword = true;
  final TextEditingController _passwordController = TextEditingController();
  bool _showPasswordEye = false;
  bool _passwordError = false;
  String? _passwordErrorMessage;
  bool _deleting = false;
  final FocusNode _focusNodePassword = FocusNode();
  Color _passwordBorderColor = const Color(0xFFA9A9A9);

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      setState(() {
        _showPasswordEye = _passwordController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNodePassword.dispose();
    super.dispose();
  }

  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    required bool errorFlag,
    required Function(bool) onErrorChange,
    required Color borderColor,
    required Function(Color) onBorderChange,
    required FocusNode focusNode,
    bool obscureText = false,
    bool showSuffixIcon = false,
    VoidCallback? onSuffixIconTap,
  }) {
    focusNode.addListener(() {
      if (focusNode.hasFocus && !errorFlag) {
        onBorderChange(const Color(0xFFA9A9A9));
      } else if (!focusNode.hasFocus && !errorFlag && controller.text.isEmpty) {
        onBorderChange(const Color(0xFFA9A9A9));
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
              onBorderChange(const Color(0xFFA9A9A9));
              setState(() {});
            },
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(
                color: Color(0xFF565656),
                fontSize: 14,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFA9A9A9), width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFA9A9A9), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFA9A9A9), width: 1),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE3001C)),
              ),
              suffixIcon: showSuffixIcon
                  ? IconButton(
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 22,
                        color: obscureText
                            ? const Color(0xFF565656)
                            : const Color(0xFF565656),
                      ),
                      onPressed: onSuffixIconTap,
                    )
                  : null,
            ),
          ),
        ),
        if (errorFlag)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 3),
            child: Text(
              _passwordErrorMessage ?? "Please enter your password.",
              style: const TextStyle(
                color: Color(0xFFE3001C),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      resizeToAvoidBottomInset: true, // enables resizing to avoid overflow when keyboard appears
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Add a scroll view so the content can be scrolled up when the keyboard shows.
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                // add a bit extra to ensure there's some padding below bottom buttons
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - MediaQuery.of(context).padding.vertical,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      /// --- CUSTOM BACK BUTTON (same as _DeleteAccountState) ---
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
                      const SizedBox(height: 13),
                      const Center(
                        child: Text(
                          "Delete account",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Please note this is permanent and can’t be undone. To confirm deleting your account, please enter your password below.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF1C1B1F),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 60),
                      const Text(
                        "Please re-enter your password to delete",
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF1C1B1F),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: _buildInput(
                          label: "Password",
                          controller: _passwordController,
                          errorFlag: _passwordError,
                          onErrorChange: (v) => setState(() {
                            _passwordError = v;
                            if (!v) _passwordErrorMessage = null;
                          }),
                          borderColor: _passwordBorderColor,
                          onBorderChange: (color) => setState(() => _passwordBorderColor = color),
                          focusNode: _focusNodePassword,
                          showSuffixIcon: _showPasswordEye,
                          obscureText: _obscurePassword,
                          onSuffixIconTap: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _deleting
                              ? null
                              : () async {
                                  final password = _passwordController.text.trim();
                                  if (password.isEmpty) {
                                    setState(() {
                                      _passwordError = true;
                                      _passwordErrorMessage = "Please enter your password.";
                                    });
                                    return;
                                  }
                                  setState(() => _deleting = true);
                                  try {
                                    await Auth().deleteAccount(
                                      password: password,
                                      reason: widget.reason,
                                    );
                                    if (!mounted) return;
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const DeleteSuccessPage(),
                                      ),
                                      (route) => false,
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() {
                                      _deleting = false;
                                      _passwordError = true;
                                      _passwordErrorMessage =
                                          e.toString().replaceFirst('Exception: ', '');
                                    });
                                  }
                                },
                          style: ButtonStyle(
                            backgroundColor: MaterialStateProperty.resolveWith<Color>(
                              (Set<MaterialState> states) {
                                if (states.contains(MaterialState.disabled)) {
                                  return const Color(0xFFFF9CA7);
                                }
                                return const Color(0xFFE3001B);
                              },
                            ),
                            shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            elevation: MaterialStateProperty.all<double>(0),
                          ),
                          child: _deleting
                              ? const AppLoadingOnBrand()
                              : const Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 13),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _deleting
                              ? null
                              : () {
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFAFAFA),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                              side: const BorderSide(
                                color: Color(0xFF6C6C6C),
                                width: 1,
                              ),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: Colors.black,
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
          },
        ),
      ),
    );
  }
}

class DeleteSuccessPage extends StatelessWidget {
  const DeleteSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF), // <-- Use a blue background so white text is visible
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'lib/client/profile/images/delete_success.jpg',
                    width: 376,
                    height: 376,
                  ),
                 
                  // Show the success text as white, on blue, clearly visible
                  Column(
                    children: const [
                      Text(
                        'Your account has been deleted',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1C1B1F) ,
                        ),
                      ),
                      Text(
                        'successfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1C1B1F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 120),
                  SizedBox(
                    width: 170,
                    height: 57,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SignUpPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007CFF),
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
                        'Create new',
                        style: TextStyle(
                          fontSize: 16  ,
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

class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 22, color: Color(0xFF007CFF)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Privacy Policy',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF1C1B1F)),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            splashRadius: 20,
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(
          'Your privacy matters to us. We only collect information required to process your orders, manage deliveries, and provide support.\n\n• Data we may collect: name, contact number, address, email, and order history.\n• Payment handling: payments are processed through supported secure channels.\n• Data sharing: we do not sell your personal data. Limited sharing only happens with trusted partners when needed to fulfill your order or comply with legal obligations.\n\nBy using this app, you acknowledge and agree to this Privacy Policy.',
          style: const TextStyle(
            fontSize: 14.2,
            height: 1.55,
            color: Color(0xFF404040),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007CFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class FaqDialog extends StatelessWidget {
  const FaqDialog({super.key});

  Widget _faqItem({
    required String question,
    required String answer,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8ECF3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: const TextStyle(
                fontSize: 14.8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1B1F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              answer,
              style: const TextStyle(
                fontSize: 13.8,
                height: 1.5,
                color: Color(0xFF4D4D4D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          const Icon(Icons.help_outline_rounded, size: 22, color: Color(0xFF007CFF)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Frequently Asked Questions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1C1B1F)),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            splashRadius: 20,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _faqItem(
                question: 'How do I place an order?',
                answer: 'Proceed to checkout and confirm your order. Select your preferred date and time, choose a payment method, and ensure your delivery address is correct. If you choose GCash, a QR Ph code will be generated for payment. For cash payments, no down payment is required.',
              ),
              _faqItem(
                question: 'How can I track my order?',
                answer: 'Go to your Order History, then select "Track Order" to view the current status of your order.',
              ),
              _faqItem(
                question: 'Can I update my flavor?',
                answer: 'Yes, you can update your flavor by contacting chat support.',
              ),
              _faqItem(
                question: 'How do I return the gallon?',
                answer: 'Once the gallon is empty, simply wait for the driver to pick it up.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007CFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class AppInfoDialog extends StatelessWidget {
  const AppInfoDialog({super.key});

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF007CFF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6A6A6A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1C1B1F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          const Icon(Icons.info_outline, size: 22, color: Color(0xFF007CFF)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'App Information',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF1C1B1F)),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            splashRadius: 20,
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow(
              icon: Icons.icecream_outlined,
              label: 'Application',
              value: 'H&R Ice Cream',
            ),
            _infoRow(
              icon: Icons.update_outlined,
              label: 'Version',
              value: '1.0.0',
            ),
            _infoRow(
              icon: Icons.build_circle_outlined,
              label: 'Purpose',
              value: 'Order, track, and manage your ice cream deliveries.',
            ),
            const SizedBox(height: 4),
            const Text(
              'For support, please use the in-app help channels or contact customer support.',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF4D4D4D)),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF007CFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

