import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';
import '../services/session_manager.dart';
import '../screens/auth_gateway_screen.dart';

/// Modern, professional confirmation dialog for logging out of VayalConnect.
class LogoutConfirmationDialog extends StatelessWidget {
  final Future<void> Function()? onConfirm;

  const LogoutConfirmationDialog({super.key, this.onConfirm});

  static Future<bool?> show(
    BuildContext context, {
    Future<void> Function()? onConfirm,
    bool closeDrawer = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => LogoutConfirmationDialog(
        onConfirm: () async {
          Navigator.pop(ctx, true);
          if (closeDrawer) {
            Navigator.of(context).pop(); // Close drawer
          }
          if (onConfirm != null) {
            await onConfirm();
          } else {
            await SessionManager().logout();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthGatewayScreen()),
                (route) => false,
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.cardBorder, width: 1),
      ),
      elevation: 6,
      backgroundColor: AppTheme.surfaceCream,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logout Icon Badge
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.logout_rounded,
                    color: AppTheme.errorRed,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                S.t('Confirm Logout'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDarkGreen,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),

              // Description
              Text(
                S.t('Are you sure you want to log out of your account?'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 26),

              // Action Buttons Row
              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryDarkGreen,
                          backgroundColor: Colors.white,
                          side: const BorderSide(
                            color: AppTheme.cardBorder,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          S.t('Cancel'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Logout Button
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: onConfirm,
                        child: Text(
                          S.t('Logout'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
}
