import 'package:flutter/material.dart';

/// H&R Ice Cream — shared loading visuals (color + sizing) to avoid drift across screens.
abstract final class AppLoadingColors {
  static const Color brand = Color(0xFFE3001B);
}

/// Brand-colored circular progress. Prefer this over raw [CircularProgressIndicator].
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 24,
    this.strokeWidth = 2,
    this.color = AppLoadingColors.brand,
  });

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Centered loading for full pages / list areas (order history, cart, etc.).
class AppLoadingCenter extends StatelessWidget {
  const AppLoadingCenter({super.key, this.size = 24, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppLoadingIndicator(size: size, strokeWidth: strokeWidth),
    );
  }
}

/// White spinner for red primary buttons (Place Order, Continue on brand, etc.).
class AppLoadingOnBrand extends StatelessWidget {
  const AppLoadingOnBrand({super.key, this.size = 24, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return AppLoadingIndicator(
      size: size,
      strokeWidth: strokeWidth,
      color: Colors.white,
    );
  }
}
