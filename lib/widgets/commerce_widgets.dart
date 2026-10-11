import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../utils/commerce_strings.dart';
import 'vayal_app_bar.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  const MetricCard(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 155,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(S.t(label)),
                  ]))));
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
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ErrorPanel(_error!, () => _load()),
            if (!_busy && _items.isEmpty && _error == null)
              Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(S.t('No records yet.'))),
            for (final item in _items)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: widget.itemBuilder(context, item, () => _load())),
            if (_items.length < _total)
              OutlinedButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: Text(S.t('Load more'))),
          ])));
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
            const Icon(Icons.cloud_off, color: Colors.red),
            Text(S.message(error), textAlign: TextAlign.center),
            TextButton(onPressed: retry, child: Text(S.t('Retry'))),
          ])));
}

Widget detailLine(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text('${S.t(label)}: ${value ?? '—'}'));
