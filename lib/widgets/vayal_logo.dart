import 'package:flutter/material.dart';

/// Original approved brand artwork; never replaced by a generated logo.
class VayalLogo extends StatelessWidget {
  final double width;
  final double height;
  const VayalLogo({super.key, this.width = 160, this.height = 160});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.asset('assets/branding/vayalconnect-logo.jpeg',
      width: width, height: height, fit: BoxFit.contain,
      semanticLabel: 'VayalConnect logo'),
  );
}
