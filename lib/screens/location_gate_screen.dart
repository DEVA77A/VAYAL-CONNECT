import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../utils/commerce_strings.dart';
import '../utils/language_rebuild.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/vayal_app_bar.dart';

class LocationGateScreen extends StatefulWidget {
  final Widget home;
  final LocationService? locationService;
  final ApiClient? api;

  const LocationGateScreen({
    super.key,
    required this.home,
    this.locationService,
    this.api,
  });

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends State<LocationGateScreen>
    with LanguageRebuild<LocationGateScreen> {
  late final _api = widget.api ?? ApiClient();
  bool _busy = false;
  LocationState? _state;
  String? _error;

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _allow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await (widget.locationService ?? LocationService()).request();
      if (!mounted) return;
      setState(() => _state = result.state);
      if (result.state == LocationState.available &&
          result.latitude != null &&
          result.longitude != null) {
        await _api.request(
          '/api/v1/users/me/location',
          method: 'PUT',
          body: {'latitude': result.latitude, 'longitude': result.longitude},
        );
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => widget.home),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundWarm,
      appBar: VayalAppBar(
        title: S.t('Location required'),
        showRoleBadge: false,
      ),
      body: PageBody(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Hero Location Illustration Badge
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      color: AppTheme.softGreen.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppTheme.softGreen,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryGreen.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Heading Typography
                  Text(
                    S.t('Location required'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDarkGreen,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitle
                  Text(
                    S.t('Enable location for a better experience'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Light-Green Information Feature Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCream,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.cardBorder, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.t('Location supports farm discovery and distance estimates. Allow foreground location to continue. GPS does not replace a delivery address.'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppTheme.dividerColor, height: 1),
                        const SizedBox(height: 16),
                        _buildFeatureRow(
                          icon: Icons.storefront_outlined,
                          title: S.t('Nearby Farm Discovery'),
                          subtitle:
                              S.t('Find nearby farms and fresh local harvests'),
                        ),
                        const SizedBox(height: 14),
                        _buildFeatureRow(
                          icon: Icons.route_outlined,
                          title: S.t('Accurate Distance'),
                          subtitle:
                              S.t('Get precise distance & delivery estimates'),
                        ),
                        const SizedBox(height: 14),
                        _buildFeatureRow(
                          icon: Icons.query_stats_outlined,
                          title: S.t('Transparent Pricing'),
                          subtitle: S.t(
                              'View government mandi prices for your district'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Privacy / GPS note
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.t('GPS is only used while using the app and does not replace your delivery address.'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Permission State Error / Warning Banner
                  if (_state != null && _state != LocationState.available) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.warningOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.warningOrange.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppTheme.warningOrange,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              S.t(switch (_state!) {
                                LocationState.disabled =>
                                  'Turn on location services, then retry.',
                                LocationState.permanentlyDenied =>
                                  'Enable location permission in app settings.',
                                LocationState.denied =>
                                  'Permission denied. Retry when ready.',
                                _ =>
                                  'Unable to obtain coordinates. Please retry.',
                              }),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.errorRed.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.errorRed,
                        ),
                      ),
                    ),
                  ],

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                      ),
                      onPressed: _busy ? null : _allow,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded, size: 20),
                      label: Text(
                        S.t('Allow location'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Open settings button when permanently denied or disabled
                  if (_state == LocationState.permanentlyDenied ||
                      _state == LocationState.disabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryDarkGreen,
                          side: const BorderSide(
                              color: AppTheme.cardBorder, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMedium),
                          ),
                        ),
                        onPressed: () => LocationService.openSettings(
                          services: _state == LocationState.disabled,
                        ),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: Text(
                          S.t('Open settings'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.softGreen.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppTheme.primaryDarkGreen),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
