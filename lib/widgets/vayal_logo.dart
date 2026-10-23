import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Approved artwork presented in an elegant circular frame with a subtle brand border.
class VayalLogo extends StatelessWidget {
  final double width;
  final double height;
  final bool showBorder;

  const VayalLogo({
    super.key,
    this.width = 110,
    this.height = 110,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: showBorder
              ? Border.all(
                  color: AppTheme.primaryLightGreen.withOpacity(0.4),
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipOval(
          child: Padding(
            padding: EdgeInsets.all(width * 0.04),
            child: Image.asset(
              'assets/branding/vayalconnect-logo.jpeg',
              fit: BoxFit.contain,
              semanticLabel: 'VayalConnect logo',
            ),
          ),
        ),
      );
}
