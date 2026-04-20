import 'package:flutter/material.dart';

/// Full-width pill [ElevatedButton] with a centered loading indicator when [busy].
/// Keeps [backgroundColor] while loading (does not fall back to grey).
class DeliveryFilledPillButton extends StatelessWidget {
  const DeliveryFilledPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.busy,
    required this.enabled,
    this.backgroundColor = const Color(0xFFE3001B),
    this.foregroundColor = Colors.white,
    Color? disabledBackgroundColor,
    this.verticalPadding = 16,
    this.fontSize = 16,
  }) : disabledBackgroundColor =
            disabledBackgroundColor ?? const Color(0xFFE0E0E0);

  final String label;
  final VoidCallback? onPressed;
  /// True while an async action is in progress (shows spinner).
  final bool busy;
  /// False when the action is not allowed (standard disabled / grey style).
  final bool enabled;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final double verticalPadding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? handler;
    if (!enabled) {
      handler = null;
    } else if (busy) {
      handler = () {};
    } else {
      handler = onPressed;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: handler,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          elevation: 0,
        ),
        child: busy
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                  color: foregroundColor,
                ),
              ),
      ),
    );
  }
}

/// Outlined pill button with a small [CircularProgressIndicator] when [busy].
class DeliveryOutlinedPillButton extends StatelessWidget {
  const DeliveryOutlinedPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.busy,
    required this.enabled,
    this.color = const Color(0xFFE3001B),
    this.verticalPadding = 16,
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool enabled;
  final Color color;
  final double verticalPadding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? handler;
    if (!enabled) {
      handler = null;
    } else if (busy) {
      handler = () {};
    } else {
      handler = onPressed;
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: handler,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          foregroundColor: color,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: busy
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                  color: color,
                ),
              ),
      ),
    );
  }
}
