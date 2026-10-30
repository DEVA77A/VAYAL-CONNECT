import '../theme/app_theme.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../utils/commerce_strings.dart';
import 'vayal_app_bar.dart';
import 'brand_widgets.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final bool compact;

  const MetricCard(
    this.label,
    this.value, {
    super.key,
    this.onTap,
    this.icon,
    this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClickable = onTap != null;
    final primaryColor = color ?? AppTheme.primaryGreen;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isGridCell =
            constraints.hasBoundedWidth && constraints.maxWidth < 300;

        Widget content;
        if (icon != null || isClickable) {
          content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: isGridCell ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (icon != null)
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, size: 18, color: primaryColor),
                      )
                    else
                      const SizedBox(height: 18),
                    if (isClickable)
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: AppTheme.textSecondary.withOpacity(0.5),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                if (isGridCell)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        S.t(label),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    S.t(label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          );
        } else {
          content = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppTheme.deepGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.t(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          );
        }

        final card = Card(
          color: AppTheme.surfaceCream,
          elevation: isClickable ? 1.5 : 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.cardBorder, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: isClickable
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: content,
                )
              : content,
        );

        if (isGridCell) return card;

        final width = MediaQuery.sizeOf(context).width < 380 ||
                MediaQuery.textScalerOf(context).scale(14) > 20
            ? MediaQuery.sizeOf(context).width - 32
            : (MediaQuery.sizeOf(context).width < 600
                ? (MediaQuery.sizeOf(context).width - 48) / 2
                : 220.0);
        return SizedBox(width: width, child: card);
      },
    );
  }
}

class RecordPage extends StatefulWidget {
  final String title;
  final String path;
  final bool embedded;
  final ApiClient? api;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback)
      itemBuilder;
  const RecordPage(
      {super.key,
      required this.title,
      required this.path,
      this.embedded = false,
      this.api,
      required this.itemBuilder});
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage>
    with LanguageRebuild<RecordPage> {
  late final _api = widget.api ?? ApiClient();
  final _items = <Map<String, dynamic>>[];
  int _page = 1;
  int _total = 0;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final data = await _api.request(
          '${widget.path}${widget.path.contains('?') ? '&' : '?'}page=$page&limit=30');
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(
            (data['items'] as List).map((e) => Map<String, dynamic>.from(e)));
        _page = page;
        _total = data['total'] as int? ?? _items.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: widget.embedded
          ? null
          : VayalAppBar(title: S.t(widget.title), showBack: true),
      body: PageBody(
          child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null) ErrorPanel(_error!, () => _load()),
                    if (!_busy && _items.isEmpty && _error == null)
                      const EmptyPanel('No records yet.'),
                    for (final item in _items)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child:
                              widget.itemBuilder(context, item, () => _load())),
                    if (_items.length < _total)
                      OutlinedButton(
                          onPressed: _busy ? null : () => _load(more: true),
                          child: Text(S.t('Load more'))),
                  ]))));
}

class ErrorPanel extends StatelessWidget {
  final String error;
  final VoidCallback retry;
  const ErrorPanel(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Icon(Icons.cloud_off_outlined,
                color: AppTheme.errorRed, size: 32),
            const SizedBox(height: 12),
            Text(S.message(error), textAlign: TextAlign.center),
            TextButton(onPressed: retry, child: Text(S.t('Retry'))),
          ])));
}

Widget detailLine(String label, dynamic value) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
        color: AppTheme.backgroundWarm, borderRadius: BorderRadius.circular(8)),
    child: Text.rich(TextSpan(children: [
      TextSpan(
          text: '${S.t(label)}: ',
          style: const TextStyle(color: AppTheme.textSecondary)),
      TextSpan(
          text: '${value ?? '—'}',
          style: const TextStyle(
              color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
    ])));
