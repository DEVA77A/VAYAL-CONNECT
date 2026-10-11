import 'package:flutter/material.dart';
import '../services/session_manager.dart';

/// Rebuild each open route when the shared, persisted locale changes.
mixin LanguageRebuild<T extends StatefulWidget> on State<T> {
  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    SessionManager().addListener(_localeChanged);
  }

  @override
  void dispose() {
    SessionManager().removeListener(_localeChanged);
    super.dispose();
  }
}
