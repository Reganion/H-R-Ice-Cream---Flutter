import 'package:flutter/material.dart';
import 'package:ice_cream/auth.dart';
import 'package:ice_cream/client/login_page.dart';
import 'package:ice_cream/client/widgets/app_loading.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController emailController = TextEditingController();
  bool hasText = false;
  bool _isLoading = false;

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
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: (hasText && !_isLoading)
                        ? () async {
                            final email = emailController.text.trim();
                            setState(() => _isLoading = true);
                            try {
                              await Auth().forgotPassword(email: email);
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordOtpPage(email: email),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e is Exception
                                        ? e.toString().replaceFirst('Exception: ', '')
                                        : 'Error: $e',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          }
                        : null,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.disabled)) {
                            return const Color(0xFFFF9CA8);
                          }
                          return const Color(0xFFE3001B);
                        },
                      ),
                      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      elevation: MaterialStateProperty.all(0),
                    ),
                    child: _isLoading
                        ? const AppLoadingOnBrand(size: 22)
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

class ForgotPasswordOtpPage extends StatefulWidget {
  const ForgotPasswordOtpPage({super.key, required this.email});

  final String email;

  @override
  State<ForgotPasswordOtpPage> createState() => _ForgotPasswordOtpPageState();
}

class _ForgotPasswordOtpPageState extends State<ForgotPasswordOtpPage> {
  List<String> otp = ["", "", "", ""];
  bool _isVerifying = false;
  bool _isResending = false;

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
                  onPressed: (isFilled && !_isVerifying)
                      ? () async {
                          setState(() => _isVerifying = true);
                          try {
                            final otpCode = otp.join();
                            final result = await Auth().verifyForgotPasswordOtp(
                              email: widget.email,
                              otp: otpCode,
                            );
                            final resetToken = result['reset_token'] as String?;
                            if (!mounted) return;
                            if (resetToken == null || resetToken.isEmpty) {
                              setState(() => _isVerifying = false);
                              return;
                            }
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ResetPasswordPage(
                                  resetToken: resetToken,
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setState(() => _isVerifying = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is Exception
                                      ? e.toString().replaceFirst('Exception: ', '')
                                      : 'Error: $e',
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith<Color>((
                      states,
                    ) {
                      if (isFilled && !_isVerifying) {
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
                  child: _isVerifying
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
                    onTap: _isResending
                        ? null
                        : () async {
                            setState(() => _isResending = true);
                            try {
                              await Auth().resendForgotPasswordOtp(email: widget.email);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "A new code has been sent to your email.",
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e is Exception
                                        ? e.toString().replaceFirst('Exception: ', '')
                                        : 'Error: $e',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _isResending = false);
                            }
                          },
                    child: _isResending
                        ? const SizedBox(
                            height: 22,
                            child: AppLoadingIndicator(size: 20),
                          )
                        : const Text(
                            'Resend OTP',
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

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.resetToken});

  final String resetToken;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool get _isContinueEnabled {
    return newPasswordController.text.isNotEmpty &&
        confirmPasswordController.text.isNotEmpty;
  }

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool keepMeLoggedIn = false;
  bool _showPasswordEyee = false;
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

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: (_isContinueEnabled && !_isLoading)
                        ? () async {
                            final newPass = newPasswordController.text;
                            final confirmPass = confirmPasswordController.text;
                            if (newPass != confirmPass) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Passwords do not match."),
                                ),
                              );
                              return;
                            }
                            if (newPass.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Password must be at least 6 characters.",
                                  ),
                                ),
                              );
                              return;
                            }
                            setState(() => _isLoading = true);
                            try {
                              await Auth().resetPassword(
                                resetToken: widget.resetToken,
                                password: newPass,
                                passwordConfirmation: confirmPass,
                              );
                              if (!mounted) return;
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CongratsPage(),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => _isLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e is Exception
                                        ? e.toString().replaceFirst('Exception: ', '')
                                        : 'Error: $e',
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_isContinueEnabled && !_isLoading)
                          ? const Color(0xFFE3001B)
                          : const Color(0xFFFF9CA7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const AppLoadingOnBrand(size: 22)
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

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center, // centers the row
                  children: [
                    Checkbox(
                      value: keepMeLoggedIn,
                      onChanged: (value) {
                        setState(() {
                          keepMeLoggedIn = value!;
                        });
                      },
                      side: const BorderSide(
                        color: Color(0xFF717171), // border color
                        width: 1.5, // thin border
                      ),
                      fillColor: MaterialStateProperty.resolveWith<Color>((
                        Set<MaterialState> states,
                      ) {
                        if (states.contains(MaterialState.selected)) {
                          return const Color(0xFFE3001B); // red when checked
                        }
                        return Colors.white; // background when unchecked
                      }),
                      checkColor: Colors.white, // color of the check icon
                    ),
                    const SizedBox(
                      width: 0,
                    ), // spacing between checkbox and text
                    const Text(
                      "Keep me login",
                      style: TextStyle(
                        color: Color(0xFF575757),
                        fontSize: 14.85,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  runApp(
    const MaterialApp(
      home: ForgotPasswordPage(),
      debugShowCheckedModeBanner: false,
    ),
  );
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

class CongratsPage extends StatelessWidget {
  const CongratsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF005AE6),
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height, // 👈 keeps portrait layout intact
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ✅ SUCCESS IMAGE
                  Image.asset(
                    'lib/client/images/CL_page/create_success.jpg',
                    width: 376,
                    height: 376,
                  ),

                 

                  // ✅ TEXT
                  Column(
                    children: const [
                      Text(
                        'Your password has been',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'changed successfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 130),

                  // ✅ LOGIN BUTTON
                  SizedBox(
                    width: 170,
                    height: 57,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
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

                  const SizedBox(height: 30), // bottom spacing for scroll
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

