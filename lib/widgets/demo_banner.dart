import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import '../screens/auth_gateway_screen.dart';

/// Explicit visual banner shown whenever the application is in Demo Preview Mode.
/// Guarantees that neither developers nor users mistake offline fixtures for live backend data.
class DemoModeBanner extends StatelessWidget {
  const DemoModeBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();
    if (!session.isDemoMode) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: const Color(0xFFFFF3E0),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFE65100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.isTamil
                  ? 'டெமோ பயன்முறை • பார்வைக்காக மாதிரி தரவு காட்டப்படுகிறது'
                  : 'DEMO PREVIEW • Displaying sample data for visual inspection',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE65100),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              session.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGatewayScreen()),
                (route) => false,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Exit',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
