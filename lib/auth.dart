import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/services/fcm_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Laravel API base URL (includes /api/v1).
const String _apiBaseUrl = 'http://192.168.1.14:8000/api/v1';

const String _tokenKey = 'auth_token';
const String _customerCacheKey = 'auth_customer_cache';

/// Auth service that talks to Laravel API (login, register, logout).
class Auth {
  static String get apiBaseUrl => _apiBaseUrl;

  /// Token for Laravel `google-sign-in` / `google-sign-up`.
  ///
  /// Always prefer the **Firebase Auth ID token** (`user.getIdToken()`). The backend
  /// verifies it with Kreait / Firebase Admin (same project as this app). Sending the
  /// Google OAuth ID token from [GoogleSignInAuthentication] instead often yields
  /// "Invalid Google token" because its `aud` must match server `GOOGLE_*_CLIENT_ID` exactly.
  static Future<String?> idTokenForGoogleBackend({
    required GoogleSignInAuthentication googleAuth,
    required User firebaseUser,
  }) async {
    final firebaseToken = await firebaseUser.getIdToken(true);
    if (firebaseToken != null && firebaseToken.trim().isNotEmpty) {
      return firebaseToken.trim();
    }
    final g = googleAuth.idToken?.trim();
    if (g != null && g.isNotEmpty) {
      return g;
    }
    return null;
  }

  /// In-memory copy of the persisted token so hot paths (cart, favorites) avoid
  /// awaiting [SharedPreferences.getInstance] on every tap.
  static String? _memoryToken;

  /// Returns stored Bearer token or null.
  static Future<String?> getToken() async {
    if (_memoryToken != null) return _memoryToken;
    final prefs = await SharedPreferences.getInstance();
    _memoryToken = prefs.getString(_tokenKey);
    return _memoryToken;
  }

  /// API-session token accessor for protected Laravel endpoints.
  static Future<String?> getApiToken() async {
    return getToken();
  }

  static Future<void> _clearToken() async {
    _memoryToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Returns cached customer map from last successful login/fetchAccount, or null.
  static Future<Map<String, dynamic>?> getCachedCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_customerCacheKey);
    if (json == null || json.isEmpty) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>?;
      return map;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCustomerCache(Map<String, dynamic> customer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customerCacheKey, jsonEncode(customer));
  }

  /// Single prefs round-trip for login / Google (faster than separate token + customer writes).
  static Future<void> _persistTokensAndCustomer({
    String? token,
    Map<String, dynamic>? customer,
  }) async {
    if ((token == null || token.isEmpty) &&
        (customer == null || customer.isEmpty)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (token != null && token.isNotEmpty) {
      _memoryToken = token;
      await prefs.setString(_tokenKey, token);
    }
    if (customer != null && customer.isNotEmpty) {
      await prefs.setString(_customerCacheKey, jsonEncode(customer));
    }
  }

  static Future<void> _clearCustomerCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customerCacheKey);
  }

  /// Clears stored customer token and profile cache without calling the API (e.g. invalid/expired session).
  static Future<void> clearCustomerSessionLocal() async {
    await _clearToken();
    await _clearCustomerCache();
  }

  /// Save token/customer to local storage (used by non-standard login flows like Google login).
  static Future<void> saveSession({
    required String token,
    Map<String, dynamic>? customer,
  }) async {
    await _persistTokensAndCustomer(token: token, customer: customer);
  }

  /// Whether the customer must accept terms (empty [terms_accepted_at] on server).
  static bool customerNeedsTermsAcceptance(Map<String, dynamic>? customer) {
    if (customer == null || customer.isEmpty) return false;
    if (customer['needs_terms_acceptance'] == false) return false;
    if (customer['needs_terms_acceptance'] == true) return true;
    final at = customer['terms_accepted_at'];
    if (at is String && at.trim().isNotEmpty) return false;
    return true;
  }

  /// Google sign-in via Laravel API; persists Laravel session token + customer.
  /// Optional [password] / [passwordConfirmation] match Laravel `password` + `password_confirmation`.
  /// [acceptTerms] when true sends `accept_terms` so the server can set [terms_accepted_at] at signup.
  Future<Map<String, dynamic>> googleSignIn({
    required String idToken,
    String? password,
    String? passwordConfirmation,
    bool acceptTerms = false,
  }) async {
    return _googleAuth(
      path: '/google-sign-in',
      idToken: idToken,
      password: password,
      passwordConfirmation: passwordConfirmation,
      acceptTerms: acceptTerms,
    );
  }

  /// Google sign-up via Laravel API; persists Laravel session token + customer.
  Future<Map<String, dynamic>> googleSignUp({
    required String idToken,
    String? password,
    String? passwordConfirmation,
    bool acceptTerms = false,
  }) async {
    return _googleAuth(
      path: '/google-sign-up',
      idToken: idToken,
      password: password,
      passwordConfirmation: passwordConfirmation,
      acceptTerms: acceptTerms,
    );
  }

  Future<Map<String, dynamic>> _googleAuth({
    required String path,
    required String idToken,
    String? password,
    String? passwordConfirmation,
    bool acceptTerms = false,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl$path');
    final body = <String, dynamic>{'id_token': idToken};
    if (acceptTerms) {
      body['accept_terms'] = true;
    }
    if (password != null && password.isNotEmpty) {
      body['password'] = password;
      body['password_confirmation'] =
          (passwordConfirmation != null && passwordConfirmation.isNotEmpty)
              ? passwordConfirmation
              : password;
    }
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      final token = _extractToken(data);
      final customerRaw = data['customer'] ?? data['account'];
      final customer = customerRaw is Map<String, dynamic>
          ? Map<String, dynamic>.from(customerRaw)
          : <String, dynamic>{};
      await _persistTokensAndCustomer(
        token: token,
        customer: customer.isNotEmpty ? customer : null,
      );
      unawaited(FcmPushService.syncCustomerToken());
      final needsTerms = data['needs_terms_acceptance'] == true ||
          (customer.isNotEmpty && customerNeedsTermsAcceptance(customer));
      return {
        'success': true,
        'customer': customer,
        'is_new_customer': data['is_new_customer'] == true,
        'needs_password_setup': data['needs_password_setup'] == true,
        'needs_terms_acceptance': needsTerms,
      };
    }

    final msg = _extractValidationMessage(data);
    throw Exception(msg.isNotEmpty ? msg : (_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Google authentication failed.'));
  }

  /// Extracts auth token from API response (supports token, access_token, auth_token, and nested data).
  static String? _extractToken(Map<String, dynamic> data) {
    const topKeys = ['token', 'access_token', 'auth_token', 'bearer_token'];
    for (final k in topKeys) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
    }
    final nested = data['data'];
    if (nested is Map<String, dynamic>) {
      for (final k in topKeys) {
        final v = nested[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  /// Login. On success saves token and returns customer map. Throws on error.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/login');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    // On 200: save token and customer whenever present (some APIs omit "success" or use different keys)
    if (response.statusCode == 200) {
      final token = _extractToken(data);
      final customer = data['customer'] ?? data['user'] ?? data['account'];
      final customerMap = customer is Map<String, dynamic>
          ? customer
          : (data['data'] is Map<String, dynamic>
              ? (data['data']['customer'] ?? data['data']['user'] ?? data['data']['account'])
              : null);
      final customerData = customerMap is Map<String, dynamic>
          ? customerMap
          : <String, dynamic>{};
      await _persistTokensAndCustomer(
        token: token,
        customer: customerData.isNotEmpty ? customerData : null,
      );
      // Treat as success if API says so, or we got a token, or we got customer (so profile works)
      final isSuccess = data['success'] == true || token != null || customerData.isNotEmpty;
      if (isSuccess) {
        // Do not await: FCM getToken can retry for many seconds and blocked navigation to home.
        unawaited(FcmPushService.syncCustomerToken());
        final needsTerms = data['needs_terms_acceptance'] == true ||
            customerNeedsTermsAcceptance(
              customerData.isNotEmpty ? customerData : null,
            );
        return {
          'success': true,
          'customer': customerData,
          'needs_terms_acceptance': needsTerms,
        };
      }
    }

    // 403: email not verified, must verify OTP first.
    // Do not require success == false: if the key is missing, null == false is false and
    // we would throw below—blocking navigation to OTP / resend.
    if (response.statusCode == 403) {
      final raw = data['email'];
      final email = raw is String ? raw.trim() : '';
      if (email.isNotEmpty) {
        return {'success': false, 'needsOtp': true, 'email': email};
      }
    }

    if (response.statusCode == 422) {
      final msg = _extractValidationMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Invalid email or password.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Login failed.');
  }

  /// Register. On success returns email + customer (no token until OTP verified). Throws on error.
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? contactNo,
    bool acceptTerms = false,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/register');
    final body = {
      'firstname': firstName,
      'lastname': lastName,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation,
      if (contactNo != null && contactNo.isNotEmpty) 'contact_no': contactNo,
      if (acceptTerms) 'accept_terms': true,
    };
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 201 && (data['success'] == true)) {
      return {
        'success': true,
        'email': data['email'] as String? ?? email,
        'customer': data['customer'] as Map<String, dynamic>? ?? <String, dynamic>{},
      };
    }

    if (response.statusCode == 422) {
      final msg = _extractValidationMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Validation failed.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Registration failed.');
  }

  /// Verify OTP. On success returns message; then client can call login.
  Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/verify-otp');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      return {'success': true, 'message': _extractMessage(data), 'email': email};
    }

    if (response.statusCode == 404 || response.statusCode == 422) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Invalid or expired code.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Verification failed.');
  }

  /// Resend OTP to email.
  Future<Map<String, dynamic>> resendOtp({required String email}) async {
    final uri = Uri.parse('$_apiBaseUrl/resend-otp');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      return {'success': true, 'message': _extractMessage(data), 'email': email};
    }

    if (response.statusCode == 404) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Account not found.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not send code.');
  }

  /// Record terms acceptance for the logged-in customer. POST /api/v1/terms/accept.
  Future<Map<String, dynamic>> acceptTermsAgreement() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated.');
    }
    final uri = Uri.parse('$_apiBaseUrl/terms/accept');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'accept_terms': true}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      final customerRaw = data['customer'];
      if (customerRaw is Map<String, dynamic>) {
        await _saveCustomerCache(Map<String, dynamic>.from(customerRaw));
      }
      return {
        'success': true,
        'needs_terms_acceptance': data['needs_terms_acceptance'] == true,
      };
    }

    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not save terms acceptance.');
  }

  // --- Forgot password (email → OTP → verify → reset) ---

  /// Forgot password: send OTP to email.
  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final uri = Uri.parse('$_apiBaseUrl/forgot-password');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      return {'success': true, 'message': _extractMessage(data), 'email': data['email'] as String? ?? email};
    }

    if (response.statusCode == 404) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'No account found with this email address.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not send verification code.');
  }

  /// Forgot password: resend OTP.
  Future<Map<String, dynamic>> resendForgotPasswordOtp({required String email}) async {
    final uri = Uri.parse('$_apiBaseUrl/forgot-password/resend-otp');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      return {'success': true, 'message': _extractMessage(data), 'email': email};
    }

    if (response.statusCode == 404) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'No account found with this email address.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not send the new code.');
  }

  /// Forgot password: verify OTP and get reset_token.
  Future<Map<String, dynamic>> verifyForgotPasswordOtp({
    required String email,
    required String otp,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/forgot-password/verify-otp');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      final resetToken = data['reset_token'] as String?;
      if (resetToken == null || resetToken.isEmpty) {
        throw Exception('Invalid response from server.');
      }
      return {'success': true, 'reset_token': resetToken, 'expires_in_minutes': data['expires_in_minutes']};
    }

    if (response.statusCode == 404 || response.statusCode == 422) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Invalid or expired code.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Verification failed.');
  }

  /// Forgot password: set new password using reset_token.
  Future<Map<String, dynamic>> resetPassword({
    required String resetToken,
    required String password,
    required String passwordConfirmation,
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/forgot-password/reset-password');
    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'reset_token': resetToken,
          'password': password,
          'password_confirmation': passwordConfirmation,
        }),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      return {'success': true, 'message': _extractMessage(data)};
    }

    if (response.statusCode == 422) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Invalid or expired reset token. Please start again.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not update password.');
  }

  /// Fetch logged-in account info. GET /api/v1/account with Bearer token.
  /// Returns account map: id, firstname, lastname, email, contact_no, image, image_url, status.
  /// Throws if not authenticated or token invalid.
  Future<Map<String, dynamic>> fetchAccount() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated.');
    }

    final uri = Uri.parse('$_apiBaseUrl/account');
    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      final account = data['account'] ?? data['customer'];
      if (account is Map<String, dynamic>) {
        await _saveCustomerCache(account);
        return account;
      }
    }

    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not fetch account.');
  }

  /// Update address. PUT or POST /api/v1/address with Bearer token.
  /// Body: province, city, barangay, postal_code, street_name, label_as (all optional but at least one required).
  Future<Map<String, dynamic>> updateAddress({
    String? province,
    String? city,
    String? barangay,
    String? postalCode,
    String? streetName,
    String? labelAs,
    String? reason,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated.');
    }

    final body = <String, dynamic>{};
    if (province != null && province.isNotEmpty) body['province'] = province;
    if (city != null && city.isNotEmpty) body['city'] = city;
    if (barangay != null && barangay.isNotEmpty) body['barangay'] = barangay;
    if (postalCode != null && postalCode.isNotEmpty) body['postal_code'] = postalCode;
    if (streetName != null && streetName.isNotEmpty) body['street_name'] = streetName;
    if (labelAs != null && labelAs.isNotEmpty) body['label_as'] = labelAs;
    if (reason != null && reason.isNotEmpty) body['reason'] = reason;

    if (body.isEmpty) {
      throw Exception('Provide at least one address field to update.');
    }

    final uri = Uri.parse('$_apiBaseUrl/address');
    final response = await http.put(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      final customer = data['customer'];
      if (customer is Map<String, dynamic>) {
        await _saveCustomerCache(customer);
        return customer;
      }
    }

    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not update address.');
  }

  // --- Customer addresses (customer_addresses table): GET list, POST add, PUT update, DELETE, set default ---

  /// List all addresses. GET /api/v1/addresses. Returns list of address maps.
  Future<List<Map<String, dynamic>>> getAddresses() async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/addresses');
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode != 200 || data['success'] != true) {
      final msg = _extractMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Could not load addresses.');
    }
    final inner = data['data'];
    final list = inner is Map<String, dynamic> ? inner['addresses'] : null;
    if (list is! List) return [];
    return list.map((e) => e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
  }

  /// Add a new address. POST /api/v1/addresses. Saves to customer_addresses table.
  Future<Map<String, dynamic>> addAddress({
    String? firstname,
    String? lastname,
    String? contactNo,
    String? province,
    String? city,
    String? barangay,
    String? postalCode,
    String? streetName,
    String? labelAs,
    bool? isDefault,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final body = <String, dynamic>{};
    if (firstname != null && firstname.isNotEmpty) body['firstname'] = firstname;
    if (lastname != null && lastname.isNotEmpty) body['lastname'] = lastname;
    if (contactNo != null && contactNo.isNotEmpty) body['contact_no'] = contactNo;
    if (province != null && province.isNotEmpty) body['province'] = province;
    if (city != null && city.isNotEmpty) body['city'] = city;
    if (barangay != null && barangay.isNotEmpty) body['barangay'] = barangay;
    if (postalCode != null && postalCode.isNotEmpty) body['postal_code'] = postalCode;
    if (streetName != null && streetName.isNotEmpty) body['street_name'] = streetName;
    if (labelAs != null && labelAs.isNotEmpty) body['label_as'] = labelAs;
    if (isDefault != null) body['is_default'] = isDefault;
    final uri = Uri.parse('$_apiBaseUrl/addresses');
    final response = await http.post(
      uri,
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 201 && (data['success'] == true)) {
      final d = data['data'];
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    }
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not add address.');
  }

  /// Update an address. PUT /api/v1/addresses/{id}.
  Future<Map<String, dynamic>> updateAddressById(String id, {
    String? firstname,
    String? lastname,
    String? contactNo,
    String? province,
    String? city,
    String? barangay,
    String? postalCode,
    String? streetName,
    String? labelAs,
    bool? isDefault,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final body = <String, dynamic>{};
    if (firstname != null && firstname.isNotEmpty) body['firstname'] = firstname;
    if (lastname != null && lastname.isNotEmpty) body['lastname'] = lastname;
    if (contactNo != null && contactNo.isNotEmpty) body['contact_no'] = contactNo;
    if (province != null && province.isNotEmpty) body['province'] = province;
    if (city != null && city.isNotEmpty) body['city'] = city;
    if (barangay != null && barangay.isNotEmpty) body['barangay'] = barangay;
    if (postalCode != null && postalCode.isNotEmpty) body['postal_code'] = postalCode;
    if (streetName != null && streetName.isNotEmpty) body['street_name'] = streetName;
    if (labelAs != null && labelAs.isNotEmpty) body['label_as'] = labelAs;
    if (isDefault != null) body['is_default'] = isDefault;
    final uri = Uri.parse('$_apiBaseUrl/addresses/$id');
    final response = await http.put(
      uri,
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) {
      final d = data['data'];
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    }
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 404) throw Exception('Address not found.');
    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not update address.');
  }

  /// Delete an address. DELETE /api/v1/addresses/{id}.
  Future<void> deleteAddress(String id) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/addresses/$id');
    final response = await http.delete(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) return;
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 404) throw Exception('Address not found.');
    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not delete address.');
  }

  /// Set an address as default. POST /api/v1/addresses/{id}/default.
  Future<void> setDefaultAddress(String id) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/addresses/$id/default');
    final response = await http.post(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) return;
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 404) throw Exception('Address not found.');
    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not set default address.');
  }

  /// Update profile. POST /api/v1/profile/update with Bearer token.
  /// Pass imagePath (file path from image_picker) for file upload, or imageBase64 for JSON.
  Future<Map<String, dynamic>> updateProfile({
    required String firstname,
    required String lastname,
    String? contactNo,
    String? imagePath,
    String? imageBase64,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated.');
    }

    final uri = Uri.parse('$_apiBaseUrl/profile/update');

    if (imagePath != null) {
      // Multipart upload
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      request.fields['firstname'] = firstname;
      request.fields['lastname'] = lastname;
      request.fields['contact_no'] = contactNo ?? '';
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = _decodeJson(response.body);

      if (response.statusCode == 200 && (data['success'] == true)) {
        final customer = data['customer'];
        return customer is Map<String, dynamic> ? customer : <String, dynamic>{};
      }
      if (response.statusCode == 422) {
        final msg = _extractValidationMessage(data);
        throw Exception(msg.isNotEmpty ? msg : 'Validation failed.');
      }
      throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Update failed.');
    }

    // JSON body (no file or base64)
    final body = <String, dynamic>{
      'firstname': firstname,
      'lastname': lastname,
      'contact_no': contactNo ?? '',
      if (imageBase64 != null && imageBase64.isNotEmpty)
        'image': 'data:image/jpeg;base64,$imageBase64',
    };

    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      _throwConnectionError(e);
    }

    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      final customer = data['customer'];
      return customer is Map<String, dynamic> ? customer : <String, dynamic>{};
    }

    if (response.statusCode == 401) {
      await _clearToken();
      throw Exception('Session expired. Please log in again.');
    }

    if (response.statusCode == 422) {
      final msg = _extractValidationMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Validation failed.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Update failed.');
  }

  /// Change password step 1: send OTP to logged-in customer email.
  /// POST /api/v1/change-password/send-otp with Bearer token, body: { "email": "..." }
  Future<void> changePasswordSendOtp({required String email}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/change-password/send-otp');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'email': email}),
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) return;
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 422) {
      throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Invalid request.');
    }
    throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Could not send code.');
  }

  /// Change password step 2: verify OTP. POST /api/v1/change-password/verify-otp with Bearer token, body: { "otp": "1234" }
  Future<void> changePasswordVerifyOtp({required String otp}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/change-password/verify-otp');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'otp': otp}),
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) return;
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 422) {
      throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Invalid or expired code.');
    }
    throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Verification failed.');
  }

  /// Change password: resend OTP. POST /api/v1/change-password/resend-otp with Bearer token, body: { "email": "..." }
  Future<void> changePasswordResendOtp({required String email}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/change-password/resend-otp');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'email': email}),
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) return;
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 422) {
      throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Invalid request.');
    }
    throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Could not resend code.');
  }

  /// Change password step 3: set new password. Must have called verify-otp first.
  /// POST /api/v1/change-password/update with Bearer token, body: current_password, password, password_confirmation, keep_logged_in
  /// Returns { success, message, logged_out?, token?, customer? }
  Future<Map<String, dynamic>> changePasswordUpdate({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
    required bool keepLoggedIn,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');
    final uri = Uri.parse('$_apiBaseUrl/change-password/update');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'keep_logged_in': keepLoggedIn,
      }),
    );
    final data = _decodeJson(response.body);
    if (response.statusCode == 200 && (data['success'] == true)) {
      if (data['logged_out'] == true) {
        await _clearToken();
        await _clearCustomerCache();
      } else if (data['customer'] is Map<String, dynamic> && data['customer'] != null) {
        await _saveCustomerCache(data['customer'] as Map<String, dynamic>);
      }
      return data;
    }
    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }
    if (response.statusCode == 422) {
      throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Update failed.');
    }
    throw Exception(_extractMessage(data).isNotEmpty ? _extractMessage(data) : 'Could not update password.');
  }

  /// Permanently delete account. DELETE /api/v1/account with Bearer token.
  /// Body: { "password": "...", "reason": "..." } where reason is optional.
  Future<void> deleteAccount({
    required String password,
    String? reason,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated.');

    final uri = Uri.parse('$_apiBaseUrl/account');
    final body = <String, dynamic>{'password': password};
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }

    final response = await http.delete(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    final data = _decodeJson(response.body);

    if (response.statusCode == 200 && (data['success'] == true)) {
      await _clearToken();
      await _clearCustomerCache();
      return;
    }

    if (response.statusCode == 401) {
      await _clearToken();
      await _clearCustomerCache();
      throw Exception('Session expired. Please log in again.');
    }

    if (response.statusCode == 422) {
      final msg = _extractValidationMessage(data);
      throw Exception(msg.isNotEmpty ? msg : 'Could not delete account.');
    }

    final msg = _extractMessage(data);
    throw Exception(msg.isNotEmpty ? msg : 'Could not delete account.');
  }

  /// End session: call API logout then clear local token and customer cache
  /// so profile shows "Session ended" (not "Session expired") after logging out.
  Future<void> signOut() async {
    final token = await getToken();
    await FcmPushService.clearCustomerToken();
    if (token != null && token.isNotEmpty) {
      final uri = Uri.parse('$_apiBaseUrl/logout');
      try {
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (_) {
        // Offline or server error: still clear local state
      }
    }
    await _clearToken();
    await _clearCustomerCache();
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractMessage(Map<String, dynamic> data) {
    final msg = data['message'];
    if (msg is String) return msg;
    return '';
  }

  Never _throwConnectionError(Object e) {
    final msg = e.toString();
    if (msg.contains('Connection refused') || msg.contains('SocketException')) {
      throw Exception(
        'Cannot connect. Run Laravel: php artisan serve. '
        'On physical device: set _usePhysicalDevice = true and _pcIp in lib/auth.dart, then: php artisan serve --host=0.0.0.0',
      );
    }
    throw e;
  }

  String _extractValidationMessage(Map<String, dynamic> data) {
    final errors = data['errors'];
    if (errors is! Map<String, dynamic>) return _extractMessage(data);
    for (final key in ['email', 'password', 'message']) {
      final list = errors[key];
      if (list is List && list.isNotEmpty && list.first is String) {
        return list.first as String;
      }
    }
    final firstKey = errors.keys.isNotEmpty ? errors.keys.first : null;
    if (firstKey != null) {
      final list = errors[firstKey];
      if (list is List && list.isNotEmpty && list.first is String) {
        return list.first as String;
      }
    }
    return _extractMessage(data);
  }
}
