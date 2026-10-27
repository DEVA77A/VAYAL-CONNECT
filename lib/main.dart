import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SessionManager().restoreLanguage();
  await SessionManager().restoreSession();
  runApp(const VayalConnectApp());
}

class VayalConnectApp extends StatelessWidget {
  const VayalConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionManager(),
      builder: (context, _) {
        return MaterialApp(
          title: 'VayalConnect • வயல் Connect',
          debugShowCheckedModeBanner: false,
          locale: Locale(SessionManager().isTamil ? 'ta' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ta')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.lightTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}
