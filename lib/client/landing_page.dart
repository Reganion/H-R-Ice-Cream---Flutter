import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/driver/login.dart';
import 'package:ice_cream/driver/shipments.dart';
import 'package:ice_cream/services/fcm_push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ice_cream/client/widgets/hr_connectivity_dialog.dart';
import 'login_page.dart';
import 'push_home_or_terms.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introAnim;
  late final Animation<double> _introCurve;
  late final Animation<Offset> _slideIn;
  late final Animation<Offset> _splashOut;

  bool _driverEntryLoading = false;
  bool _customerEntryLoading = false;

  static const List<String> _precacheAssets = [
    'lib/client/images/landing_page/froz1.png',
    'lib/client/images/landing_page/froz2.png',
    'lib/client/images/landing_page/icecream5.png',
    'lib/client/images/landing_page/icecream3.png',
    'lib/client/images/landing_page/snowing2.png',
    'lib/client/images/landing_page/icecream6.png',
    'lib/client/images/landing_page/froz6.png',
    'lib/client/images/landing_page/snowing4.png',
    'lib/client/images/landing_page/froz5.png',
    'lib/client/images/landing_page/froz4.png',
    'lib/client/images/landing_page/icecream4.png',
    'lib/client/images/landing_page/snowing3.png',
    'lib/client/images/landing_page/froz3.png',
    'lib/client/images/landing_page/icecream2.png',
    'lib/client/images/landing_page/icecream1.png',
  ];

  static const Duration _introFade = Duration(milliseconds: 700);
  static const Duration _minSplash = Duration(milliseconds: 950);

  @override
  void initState() {
    super.initState();
    _introAnim = AnimationController(vsync: this, duration: _introFade);
    _introCurve = CurvedAnimation(
      parent: _introAnim,
      curve: Curves.easeOutCubic,
    );
    _slideIn = Tween<Offset>(
      begin: const Offset(0.14, 0),
      end: Offset.zero,
    ).animate(_introCurve);
    _splashOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.1, 0),
    ).animate(_introCurve);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runIntro());
  }

  @override
  void dispose() {
    _introAnim.dispose();
    super.dispose();
  }

  /// Loads images without blocking [_runIntro]; failures are ignored.
  Future<void> _precacheAssetsInBackground() async {
    try {
      await Future.wait(
        _precacheAssets.map(
          (path) => precacheImage(AssetImage(path), context),
        ),
      );
    } catch (_) {
      // Missing asset or bad context — landing still usable.
    }
  }

  Future<void> _clearStoredDriverSession(SharedPreferences prefs) async {
    await prefs.remove('driver_token');
    await prefs.remove('driver_profile');
    await prefs.remove('driver_password');
  }

  void _pushCustomerLoginPage() {
    Navigator.push<void>(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (_, animation, __) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutQuad,
              ),
            ),
            child: const LoginPage(),
          );
        },
      ),
    );
  }

  /// If a customer token exists and [GET /session] succeeds, home or terms; else [LoginPage].
  Future<void> _openCustomerEntry() async {
    if (_customerEntryLoading) return;
    setState(() => _customerEntryLoading = true);

    try {
      final token = (await Auth.getToken())?.trim() ?? '';
      if (token.isEmpty) {
        if (!mounted) return;
        _pushCustomerLoginPage();
        return;
      }

      try {
        final res = await http
            .get(
              Uri.parse('${Auth.apiBaseUrl}/session'),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic> && decoded['success'] == true) {
            final needsTerms = decoded['needs_terms_acceptance'] == true;
            unawaited(FcmPushService.syncCustomerToken());
            if (!mounted) return;
            await pushHomeOrTerms(context, needsTerms: needsTerms);
            return;
          }
        }

        if (res.statusCode == 401 || res.statusCode == 403) {
          await Auth.clearCustomerSessionLocal();
          if (!mounted) return;
          _pushCustomerLoginPage();
          return;
        }

        if (res.statusCode >= 500) {
          if (!mounted) return;
          await HrConnectivityDialog.showServerUnavailable(context);
          return;
        }

        await Auth.clearCustomerSessionLocal();
        if (!mounted) return;
        _pushCustomerLoginPage();
      } catch (e) {
        if (!mounted) return;
        await HrConnectivityDialog.showForError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _customerEntryLoading = false);
      }
    }
  }

  /// If a driver token exists and the API session is valid, open [ShipmentsPage];
  /// otherwise [LoginScreen]. Network failures keep the user on landing with a snackbar
  /// (navigating to [LoginScreen] would clear the token in its [initState]).
  Future<void> _openDriverEntry() async {
    if (_driverEntryLoading) return;
    setState(() => _driverEntryLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString('driver_token') ?? '').trim();
      if (token.isEmpty) {
        if (!mounted) return;
        Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        return;
      }

      try {
        final res = await http
            .get(
              Uri.parse('${Auth.apiBaseUrl}/driver/session'),
              headers: {
                'Accept': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is Map<String, dynamic> && decoded['success'] == true) {
            unawaited(FcmPushService.syncDriverToken());
            if (!mounted) return;
            Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (context) => const ShipmentsPage()),
            );
            return;
          }
        }

        if (res.statusCode == 401 || res.statusCode == 403) {
          await _clearStoredDriverSession(prefs);
          if (!mounted) return;
          Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
          return;
        }

        if (res.statusCode >= 500) {
          if (!mounted) return;
          await HrConnectivityDialog.showServerUnavailable(context);
          return;
        }

        await _clearStoredDriverSession(prefs);
        if (!mounted) return;
        Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      } catch (e) {
        if (!mounted) return;
        await HrConnectivityDialog.showForError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _driverEntryLoading = false);
      }
    }
  }

  Future<void> _runIntro() async {
    if (!mounted) return;
    // Precache in the background. Awaiting every image blocked the intro and
    // left IgnorePointer(ignoring: !_introAnim.isCompleted) true indefinitely
    // when any precache stalled or was slow after navigating back to landing.
    unawaited(_precacheAssetsInBackground());
    try {
      await Future<void>.delayed(_minSplash);
    } catch (_) {
      // Still show landing if delayed.
    }
    if (!mounted) return;
    _introAnim.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            SlideTransition(
              position: _slideIn,
              child: FadeTransition(
                opacity: _introCurve,
                child: ListenableBuilder(
                  listenable: _introAnim,
                  builder: (context, child) {
                    return IgnorePointer(
                      ignoring: !_introAnim.isCompleted,
                      child: child!,
                    );
                  },
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                      // ------------------ RED TOP SECTION WITH CURVE ------------------
                      ClipPath(
                        clipper: BottomCurveClipper(),
                        child: Container(
                          width: double.infinity,
                          height: 440,
                          color: const Color(0xFFE3001B),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                top: -13,
                                left: -8,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz1.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: -8,
                                left: 15,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz2.png',
                                  width: 55,
                                  height: 55,
                                ),
                              ),
                              Positioned(
                                top: -38,
                                right: 28,
                                child: Image.asset(
                                  'lib/client/images/landing_page/icecream5.png',
                                  width: 215,
                                  height: 215,
                                ),
                              ),
                              Positioned(
                                top: -28,
                                left: 30,
                                child: Image.asset(
                                  'lib/client/images/landing_page/icecream3.png',
                                  width: 140,
                                  height: 140,
                                ),
                              ),
                              Positioned(
                                top: -4,
                                left: 127,
                                child: Image.asset(
                                  'lib/client/images/landing_page/snowing2.png',
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                              Positioned(
                                top: -12,
                                right: 40,
                                child: Image.asset(
                                  'lib/client/images/landing_page/icecream6.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: -3,
                                right: 0,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz6.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: 10,
                                right: 15,
                                child: Image.asset(
                                  'lib/client/images/landing_page/snowing4.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ),
                              Positioned(
                                top: 40,
                                right: -16,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz5.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ),
                              Positioned(
                                top: 50,
                                right: 80,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz4.png',
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                              Positioned(
                                top: 18,
                                right: 166,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz4.png',
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                              Positioned(
                                top: 25,
                                right: 200,
                                child: Image.asset(
                                  'lib/client/images/landing_page/icecream4.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: 55,
                                right: 165,
                                child: Image.asset(
                                  'lib/client/images/landing_page/snowing3.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: 48,
                                left: 73,
                                child: Image.asset(
                                  'lib/client/images/landing_page/froz3.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: 35,
                                left: 33,
                                child: Image.asset(
                                  'lib/client/images/landing_page/icecream2.png',
                                  width: 50,
                                  height: 50,
                                ),
                              ),
                              Positioned(
                                top: 35,
                                left: -43,
                                child: Image.asset(
                                  'lib/client/images/landing_page/snowing4.png',
                                  width: 90,
                                  height: 90,
                                ),
                              ),
                              Positioned(
                                top: 80,
                                left: -23,
                                child: Image.asset(
                                  'lib/client/images/landing_page/icecream1.png',
                                  width: 90,
                                  height: 90,
                                ),
                              ),

                              // ------------------ H&R LOGO ------------------
                              Container(
                                width: 260,
                                height: 200,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.only(bottom: 0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment
                                      .start, // aligns children to left
                                  children: const [
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: 22,
                                      ), // move left by 10 pixels
                                      child: Text(
                                        "H&R",
                                        style: TextStyle(
                                          fontFamily: "NationalPark",
                                          fontSize: 65,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0,
                                          height: 0.9,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 1),
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: 10,
                                      ), // match alignment with H&R
                                      child: Text(
                                        "ICE CREAM",
                                        style: TextStyle(
                                          fontFamily: "NationalPark",
                                          fontSize: 25,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 4,
                                          color: Colors.white,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ------------------ TEXT SECTION ------------------
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: "Your scoop ",
                              style: TextStyle(
                                color: Color(0xFFE3001B),
                                fontFamily: "Inter",
                                fontSize: 20.29,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: "is just a click away!",
                              style: TextStyle(
                                color: Color(0xFF313131),
                                fontFamily: "Inter",
                                fontSize: 20.29,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        "Bringing sweetness straight to your door.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF313131),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // ------------------ SIMPLE ORDER NOW BUTTON ------------------
                      IgnorePointer(
                        ignoring: _customerEntryLoading,
                        child: GestureDetector(
                          onTap: _openCustomerEntry,
                          child: Container(
                            width: 221,
                            height: 59,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3001B),
                              borderRadius: BorderRadius.circular(40),
                            ),
                            alignment: Alignment.center,
                            child: _customerEntryLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Color(0xFFFFFFFF),
                                    ),
                                  )
                                : const Text(
                                    "Login as Customer",
                                    style: TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 16.76,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ------------------ NEW BUTTON BELOW ORDER NOW BUTTON ------------------
                      IgnorePointer(
                        ignoring: _driverEntryLoading,
                        child: GestureDetector(
                          onTap: _openDriverEntry,
                          child: Container(
                            width: 221,
                            height: 59,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFFFFFF,
                              ), // background color white
                              borderRadius: BorderRadius.circular(40),
                              border: Border.all(
                                color: const Color(
                                  0xFFE3001B,
                                ), // border color #E3001B
                                width: 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: _driverEntryLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Color(0xFFE3001B),
                                    ),
                                  )
                                : const Text(
                                    "Login as Driver",
                                    style: TextStyle(
                                      color: Color(
                                        0xFFE3001B,
                                      ), // text color #E3001B
                                      fontSize: 16.76,
                                      fontWeight: FontWeight.w600,
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
            ),
            ListenableBuilder(
              listenable: _introAnim,
              builder: (context, child) {
                return IgnorePointer(
                  ignoring: _introAnim.isCompleted,
                  child: child!,
                );
              },
              child: SlideTransition(
                position: _splashOut,
                child: FadeTransition(
                  opacity: ReverseAnimation(_introCurve),
                  child: const _LandingSplashOverlay(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen splash while landing assets load (solid brand color, no logo).
class _LandingSplashOverlay extends StatelessWidget {
  const _LandingSplashOverlay();

  static const Color _brand = Color(0xFFE3001B);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _brand,
      child: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3.2,
          ),
        ),
      ),
    );
  }
}

// bottom curve clipper unchanged
class BottomCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();

    path.lineTo(0, size.height - 20);

    path.quadraticBezierTo(
      size.width / 2,
      size.height - 130,
      size.width,
      size.height - 20,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
