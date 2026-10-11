import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'vayal_logo.dart';
import '../models/auth_models.dart';
import '../utils/commerce_strings.dart';

/// Reusable Top App Bar matching Stitch Design System
///
/// Features:
/// - Brand logo & bilingual title ('வயல் Connect')
/// - Active role badge (விவசாயி / வாங்குபவர் / நிர்வாகி)
/// - Language switcher pill (தமிழ் / English)
/// - Notification trigger
class VayalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final String? subtitle;
  final bool showBack;
  final bool showRoleBadge;
  final List<Widget>? actions;

  const VayalAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.showBack = false,
    this.showRoleBadge = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    String roleName;
    Color roleBadgeColor;
    switch (session.activeRole) {
      case AppRole.farmer:
        roleName = session.isTamil ? 'விவசாயி' : 'Farmer';
        roleBadgeColor = AppTheme.accentGold;
        break;
      case AppRole.buyer:
        roleName = session.isTamil ? 'வாங்குபவர்' : 'Buyer';
        roleBadgeColor = Colors.lightBlueAccent;
        break;
      case AppRole.admin:
        roleName = session.isTamil ? 'நிர்வாகி' : 'Admin';
        roleBadgeColor = Colors.amberAccent;
        break;
    }

    return AppBar(
      backgroundColor: AppTheme.primaryGreen,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const VayalLogo(width: 36, height: 36),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                title ?? (session.isTamil ? 'வயல் Connect' : 'VayalConnect'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
              if (showRoleBadge) ...[
                const SizedBox(width: 8),
                Flexible(
                    child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: roleBadgeColor.withOpacity(0.6), width: 1),
                  ),
                  child: Text(
                    roleName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: roleBadgeColor,
                    ),
                  ),
                )),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Language Toggle Pill
        TextButton(
          onPressed: session.savingLanguage
              ? null
              : () async {
                  try {
                    await session.toggleLanguagePersisted();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(S.t(
                              'Unable to save language preference. Please retry.'))));
                    }
                  }
                },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  session.isTamil ? 'தமிழ்' : 'Eng',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (actions != null) ...actions!,
        const SizedBox(width: 8),
      ],
    );
  }
}
