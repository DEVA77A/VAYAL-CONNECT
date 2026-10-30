import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';

/// Keeps forms comfortable on tablets and clear of Android system navigation.
class PageBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const PageBody({super.key, required this.child, this.maxWidth = 760});

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
              width: maxWidth, height: double.infinity, child: child)));
}

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const SectionCard(
      {super.key,
      required this.title,
      required this.icon,
      required this.children});

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 20, color: AppTheme.earthBrown),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(S.t(title),
                      style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 16),
            ...children,
          ])));
}

/// Wraps long Tamil labels/amounts instead of squeezing either column.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const InfoRow(this.label, this.value, {super.key, this.emphasize = false});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final labelWidget = Text(S.t(label),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color:
                    emphasize ? AppTheme.deepGreen : AppTheme.textSecondary));
        final valueWidget = Text(value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: emphasize ? AppTheme.deepGreen : AppTheme.textPrimary,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600));
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(14) > 21) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelWidget,
                const SizedBox(height: 4),
                valueWidget,
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: labelWidget),
          const SizedBox(width: 16),
          Expanded(child: valueWidget),
        ]);
      }));
}

class EmptyPanel extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyPanel(this.message, {super.key, this.icon = Icons.eco_outlined});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            DecoratedBox(
                decoration: const BoxDecoration(
                    color: AppTheme.softGreen, shape: BoxShape.circle),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(icon, size: 32, color: AppTheme.primaryGreen))),
            const SizedBox(height: 16),
            Text(S.t(message),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
          ])));
}

class SheetTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onClose;
  const SheetTitle(
      {super.key,
      required this.title,
      required this.icon,
      required this.onClose});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: AppTheme.primaryGreen),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close)),
      ]);
}

class CropSummary extends StatelessWidget {
  final String name;
  final String? imageUrl;
  const CropSummary({super.key, required this.name, this.imageUrl});
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final photo = ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
                width: 72,
                height: 72,
                child: CropImage(imageUrl, semanticLabel: name)));
        final title = Text(name, style: Theme.of(context).textTheme.titleLarge);
        if (MediaQuery.textScalerOf(context).scale(14) > 21 ||
            bounds.maxWidth < 260) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [photo, const SizedBox(height: 12), title]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          photo,
          const SizedBox(width: 16),
          Expanded(child: title)
        ]);
      });
}

class ResponsivePair extends StatelessWidget {
  final Widget first;
  final Widget second;
  const ResponsivePair({super.key, required this.first, required this.second});
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        if (bounds.maxWidth >= 340 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second]);
      });
}

/// Presentation only: callers own content, permissions and actions.
class BrandHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  const BrandHeading(
      {super.key,
      required this.title,
      this.subtitle,
      this.icon = Icons.eco_outlined});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.lightGreenDashboard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.cardBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppTheme.darkBrown.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                            color: AppTheme.darkGreenText,
                            fontWeight: FontWeight.bold)),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.5)),
                ],
              ])),
          if (MediaQuery.textScalerOf(context).scale(14) <= 21) ...[
            const SizedBox(width: 12),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppTheme.surfaceCream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder, width: 1)),
                child: Icon(icon, color: AppTheme.darkGreenText, size: 24)),
          ],
        ]),
      );
}

class FormSection extends StatelessWidget {
  final String label;
  final IconData icon;
  const FormSection(this.label, {super.key, this.icon = Icons.eco_outlined});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 16),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppTheme.surfaceCream,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppTheme.earthBrown, size: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(S.t(label),
                  style: Theme.of(context).textTheme.titleMedium)),
        ]),
      );
}

/// Accepts actual product media only. Relative URLs resolve to the existing API.
/// Never send the session bearer token to an external image host.
Uri? resolveCropImage(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty || raw.startsWith('//')) return null;
  final parsed = Uri.tryParse(raw);
  final base = Uri.tryParse(ApiConfig.baseUrl);
  if (parsed == null || base == null) return null;
  final uri = raw.startsWith('/') ? base.resolveUri(parsed) : parsed;
  if (!uri.hasAuthority ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

class CropImage extends StatelessWidget {
  final String? url;
  final String? semanticLabel;
  final BoxFit fit;
  const CropImage(this.url,
      {super.key, this.semanticLabel, this.fit = BoxFit.cover});
  @override
  Widget build(BuildContext context) {
    final uri = resolveCropImage(url);
    final fallback = Semantics(
        label: S.t('Crop photograph unavailable'),
        child: ExcludeSemantics(
            child: ColoredBox(
                color: AppTheme.softGreen,
                child: LayoutBuilder(
                    builder: (context, bounds) => Center(
                        child: Icon(
                            Icons.eco_outlined,
                            size: bounds.biggest.shortestSide.clamp(28, 56),
                            color: AppTheme.primaryGreen))))));
    if (uri == null) return fallback;
    final base = Uri.tryParse(ApiConfig.baseUrl);
    final token = SessionManager().accessToken;
    final authorized = base != null &&
        base.hasAuthority &&
        ['http', 'https'].contains(base.scheme) &&
        uri.origin == base.origin &&
        uri.path.startsWith('/api/v1/media/') &&
        token != null &&
        token.isNotEmpty;
    return LayoutBuilder(builder: (context, bounds) {
      // Width buckets let list/details reuse Flutter's in-memory image cache.
      final pixels = (bounds.maxWidth.isFinite ? bounds.maxWidth : 400) *
          MediaQuery.devicePixelRatioOf(context);
      final decodeWidth = const [128, 256, 512, 768, 1024, 1600]
          .firstWhere((size) => size >= pixels, orElse: () => 1600);
      return Image.network(uri.toString(),
          key: ValueKey(uri.toString()),
          width: double.infinity,
          height: double.infinity,
          fit: fit,
          cacheWidth: decodeWidth,
          filterQuality: FilterQuality.medium,
          semanticLabel: semanticLabel,
          headers: authorized ? {'Authorization': 'Bearer $token'} : const {},
          errorBuilder: (_, __, ___) => fallback,
          frameBuilder: (context, child, frame, synchronous) {
            if (synchronous) return child;
            return Stack(fit: StackFit.expand, children: [
              if (frame == null)
                const ColoredBox(
                  color: AppTheme.backgroundWarm,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                )
              else
                const ColoredBox(color: AppTheme.backgroundWarm),
              AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: child),
            ]);
          });
    });
  }
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (color, background, icon) = switch (status) {
      'CAPTURED' || 'COMPLETED' || 'APPROVED' || 'PAID' || 'ACTIVE' => (
          AppTheme.deepGreen,
          AppTheme.softGreen,
          Icons.check_circle_outline
        ),
      'FAILED' || 'CANCELLED' || 'REJECTED' => (
          AppTheme.errorRed,
          const Color(0xFFFFEBEE),
          Icons.error_outline
        ),
      _ => (AppTheme.darkBrown, AppTheme.surfaceCream, Icons.schedule_outlined),
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Text.rich(
            TextSpan(children: [
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(icon, size: 14, color: color))),
              TextSpan(text: S.status(status)),
            ]),
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12)));
  }
}
