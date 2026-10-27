import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'vayal_logo.dart';
import '../models/auth_models.dart';
import '../utils/commerce_strings.dart';

/// Reusable Top App Bar
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
  final bool? showMenu;
  final bool showRoleBadge;
  final List<Widget>? actions;

  const VayalAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.showBack = false,
    this.showMenu,
    this.showRoleBadge = true,
    this.actions,
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 88 : 104);

  @override
  Widget build(BuildContext context) {
    final session = SessionManager();

    String roleName;
    switch (session.activeRole) {
      case AppRole.farmer:
        roleName = session.isTamil ? 'விவசாயி' : 'Farmer';
        break;
      case AppRole.buyer:
        roleName = session.isTamil ? 'வாங்குபவர்' : 'Buyer';
        break;
      case AppRole.admin:
        roleName = session.isTamil ? 'நிர்வாகி' : 'Admin';
        break;
    }

    final bool displayMenu = !showBack && (showMenu ?? true);

    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: displayMenu || showBack ? 8 : 16,
      backgroundColor: AppTheme.primaryGreen,
      elevation: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 48,
      iconTheme: const IconThemeData(color: Colors.white),
      leading: showBack
          ? IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : displayMenu
              ? Builder(
                  builder: (ctx) => IconButton(
                    tooltip: S.t('Menu'),
                    icon: const Icon(Icons.menu_rounded, size: 24, color: Colors.white),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                )
              : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!showBack &&
                  MediaQuery.textScalerOf(context).scale(14) < 21) ...[
                const VayalLogo(width: 36, height: 36),
                const SizedBox(width: 8),
              ],
              Expanded(
                  child: Tooltip(
                      message: title ?? 'VayalConnect',
                      child: Text(
                        title ??
                            (session.isTamil ? 'வயல் Connect' : 'VayalConnect'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                        maxLines:
                            MediaQuery.textScalerOf(context).scale(14) > 21
                                ? 1
                                : 2,
                        overflow: TextOverflow.ellipsis,
                      ))),
            ],
          ),
          if (showRoleBadge || subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              [if (showRoleBadge) roleName, if (subtitle != null) subtitle!]
                  .join(' · '),
              maxLines:
                  MediaQuery.textScalerOf(context).scale(14) > 21 ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.softGreen,
                fontWeight: FontWeight.w600,
                height: 1.3,
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
