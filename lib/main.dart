import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VayalConnectApp());
}

class VayalConnectApp extends StatelessWidget {
  const VayalConnectApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionManager(),
      builder: (context, _) {
        return MaterialApp(
          title: 'VayalConnect • வயல் Connect',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}
