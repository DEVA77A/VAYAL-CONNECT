import 'package:flutter/material.dart';

/// Locale-aware presentation only; the persisted order timestamp is unchanged.
String displayDate(BuildContext context, dynamic value) {
  if (value == null || value.toString().trim().isEmpty) return '—';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return value.toString();
  final local = date.toLocal();
  final labels = MaterialLocalizations.of(context);
  final day = labels.formatMediumDate(local);
  if (!value.toString().contains('T')) return day;
  return '$day · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}
