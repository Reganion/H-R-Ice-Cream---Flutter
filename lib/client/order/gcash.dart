import 'package:flutter/material.dart';

/// Payment Method list screen: back arrow, title "Payment Method", "Methods" subheading, GCash row. back arrow, title "Payment Method", "Methods" subheading, GCash row.
class PaymentMethodPage extends StatelessWidget {
  const PaymentMethodPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20), // Move arrow a bit right
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color(0xFF1C1B1F),
              size: 23, // Minimize the size of the icon
            ),
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 20, // Ensure the IconButton itself is also small
          ),
        ),
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 30),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Payment Method",
              style: TextStyle(
                color: Color(0xFF1C1B1F),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Underlined "Methods" subheading
            const Text(
              "Methods",
              style: TextStyle(
                color: Color(0xFF1C1B1F),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                decorationColor: Color(0xFF1C1B1F),
              ),
            ),
            const SizedBox(height: 16),
            // GCash list entry
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const GcashDetailsPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    // GCash logo (circular)
                    ClipOval(
                      child: Image.asset(
                        "lib/client/order/images/gcash2.png",
                        height: 48,
                        width: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 48,
                          width: 48,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0055A4),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              "G",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "GCash",
                            style: TextStyle(
                              color: Color(0xFF1C1B1F),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "****5678",
                            style: TextStyle(
                              color: Color(0xFF1C1B1F),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF1C1B1F),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class GcashDetailsPage extends StatelessWidget {
  const GcashDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1C1B1F)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 30),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Details",
              style: TextStyle(
                color: Color(0xFF1C1B1F),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        centerTitle: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      const SizedBox(height: 36),
                      // GCash logo as circular - moved to top
                      ClipOval(
                        child: Image.asset(
                          "lib/client/order/images/gcash2.png",
                          height: 90,
                          width: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildGcashLogoPlaceholder(),
                        ),
                      ),
                      const SizedBox(height: 22),
                      // Account name
                      const Text(
                        "GCash",
                        style: TextStyle(
                          color: Color(0xFF1C1B1F),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Masked phone number
                      const Text(
                        "****5678",
                        style: TextStyle(
                          color: Color(0xFF1C1B1F),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 82),
                      // Unlink button, moved up below details
                      Align(
                        alignment: Alignment.center,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const GcashUnlinkSuccessPage(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE3001B),
                            side: const BorderSide(color: Color(0xFFE3001B), width: 1),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            minimumSize: const Size(0, 0),
                          ),
                          child: const Text(
                            "Unlink",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      // You can add more buttons below if needed (placeholders for "buttoms")
                      // Expanded to push everything up and not center them vertically
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGcashLogoPlaceholder() {
    return Container(
      height: 80,
      width: 80,
      decoration: const BoxDecoration(
        color: Color(0xFF0055A4),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          "G",
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Success screen shown after unlinking wallet: green checkmark, message, Continue button.
class GcashUnlinkSuccessPage extends StatelessWidget {
  const GcashUnlinkSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              // Green circle with white checkmark
              Container(
               
                decoration: const BoxDecoration(
                  color:  Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Color(0xFF4CAF50),
                  size: 100,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Wallet unlink successfully",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1C1B1F),
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Continue button - goes to Payment Method screen
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // close success
                    Navigator.of(context).pop(); // close details
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const PaymentNotLinkMethodPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00AE2A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Continue",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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
class PaymentNotLinkMethodPage extends StatelessWidget {
  const PaymentNotLinkMethodPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 20), // Move arrow a bit right
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color(0xFF1C1B1F),
              size: 23, // Minimize the size of the icon
            ),
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 20, // Ensure the IconButton itself is also small
          ),
        ),
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 30),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Payment Method",
              style: TextStyle(
                color: Color(0xFF1C1B1F),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Underlined "Methods" subheading
            const Text(
              "Methods",
              style: TextStyle(
                color: Color(0xFF1C1B1F),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                decorationColor: Color(0xFF1C1B1F),
              ),
            ),
            const SizedBox(height: 16),
            // GCash list entry
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const GcashDetailsPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    // GCash logo (circular)
                    ClipOval(
                      child: Image.asset(
                        "lib/client/order/images/gcash2.png",
                        height: 48,
                        width: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 48,
                          width: 48,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0055A4),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              "G",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "GCash",
                            style: TextStyle(
                              color: Color(0xFF1C1B1F),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Not link",
                            style: TextStyle(
                              color: Color(0xFF1C1B1F),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF1C1B1F),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}