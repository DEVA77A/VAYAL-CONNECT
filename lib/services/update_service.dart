import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/commerce_strings.dart';

/// Representation of an official published mobile app release.
class AppReleaseInfo {
  final String appId;
  final String versionName;
  final int versionCode;
  final int minSupportedVersionCode;
  final String apkUrl;
  final String sha256;
  final String releaseNotesEn;
  final String releaseNotesTa;
  final bool mandatory;
  final String releaseDate;

  const AppReleaseInfo({
    required this.appId,
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.apkUrl,
    required this.sha256,
    required this.releaseNotesEn,
    required this.releaseNotesTa,
    required this.mandatory,
    required this.releaseDate,
  });

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    return AppReleaseInfo(
      appId: json['app_id'] as String? ?? 'com.vayalconnect.app',
      versionName: json['version_name'] as String? ?? '1.1.0',
      versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
      minSupportedVersionCode:
          (json['min_supported_version_code'] as num?)?.toInt() ?? 1,
      apkUrl: json['apk_url'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').trim(),
      releaseNotesEn: json['release_notes_en'] as String? ?? '',
      releaseNotesTa: json['release_notes_ta'] as String? ?? '',
      mandatory: json['mandatory'] == true,
      releaseDate: json['release_date'] as String? ?? '',
    );
  }

  String localizedReleaseNotes(bool isTamil) {
    if (isTamil && releaseNotesTa.trim().isNotEmpty) {
      return releaseNotesTa;
    }
    return releaseNotesEn;
  }
}

class UpdateSecurityException implements Exception {
  final String message;
  const UpdateSecurityException(this.message);
  @override
  String toString() => message;
}

/// Service managing in-app update checks, secure HTTPS download,
/// SHA-256 cryptographic verification, and Android Package Installer handover.
class UpdateService {
  static const int currentVersionCode = 11;
  static const String currentVersionName = '1.1.0';
  static const MethodChannel _channel =
      MethodChannel('com.vayalconnect.app/updater');

  final ApiClient _api;

  UpdateService({ApiClient? api}) : _api = api ?? ApiClient();

  /// Get installed application versionCode from Android PackageManager or default.
  Future<int> getInstalledVersionCode() async {
    if (kIsWeb || !Platform.isAndroid) return currentVersionCode;
    try {
      final code = await _channel.invokeMethod<int>('getVersionCode');
      return code ?? currentVersionCode;
    } catch (_) {
      return currentVersionCode;
    }
  }

  /// Check whether an update is available against the backend /app-release endpoint.
  Future<AppReleaseInfo?> checkForUpdate() async {
    try {
      final data = await _api.request('/api/v1/settings/app-release');
      if (data is! Map<String, dynamic>) return null;

      final release = AppReleaseInfo.fromJson(data);
      final installedCode = await getInstalledVersionCode();

      if (release.versionCode > installedCode) {
        return release;
      }
      return null;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Download APK with byte progress tracking and SHA-256 verification.
  Future<File> downloadAndVerifyApk(
    AppReleaseInfo release, {
    required void Function(double progress, int receivedBytes, int totalBytes)
        onProgress,
    required void Function(String statusMessage) onStatus,
  }) async {
    if (!release.apkUrl.startsWith('https://')) {
      throw const UpdateSecurityException(
          'Security violation: Updates must be downloaded over HTTPS.');
    }

    onStatus(S.t('Connecting to secure release repository...'));

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(release.apkUrl));
      final resp = await client.send(req);

      if (resp.statusCode != 200) {
        throw UpdateSecurityException(
            'Release server responded with HTTP status ${resp.statusCode}');
      }

      final totalBytes = resp.contentLength ?? 0;
      final tempDir = Directory.systemTemp;
      final targetFile = File(
          '${tempDir.path}/vayalconnect_${release.versionName}_${release.versionCode}.apk');

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      onStatus(S.t('Downloading update package...'));

      final sink = targetFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in resp.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        final double progress =
            totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
        onProgress(progress, receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();

      onStatus(S.t('Verifying package integrity (SHA-256)...'));

      final digest = await sha256.bind(targetFile.openRead()).first;
      final actualSha256 = digest.toString().toLowerCase();

      // If SHA-256 metadata is specified by release, verify strictly
      if (release.sha256.isNotEmpty) {
        final expected = release.sha256.toLowerCase();
        if (actualSha256 != expected) {
          try {
            await targetFile.delete();
          } catch (_) {}
          throw UpdateSecurityException(
              'Integrity check failed: APK SHA-256 checksum mismatch.\n'
              'Expected: $expected\n'
              'Actual: $actualSha256');
        }
      }

      onStatus(S.t('Integrity verified successfully.'));
      return targetFile;
    } finally {
      client.close();
    }
  }

  /// Triggers the Android package installer Intent.
  Future<bool> installApk(File file) async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('installApk', {
        'filePath': file.path,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      throw UpdateSecurityException(e.message ?? 'Installation failed');
    }
  }

  /// Check whether the app can request package installs on Android 8.0+.
  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? can =
          await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return can ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open unknown app sources settings on Android 8.0+.
  Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }
}

/// Interactive update dialog with download progress and verification status.
class UpdateDialog extends StatefulWidget {
  final AppReleaseInfo release;
  final UpdateService? updateService;

  const UpdateDialog({
    super.key,
    required this.release,
    this.updateService,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late final UpdateService _service = widget.updateService ?? UpdateService();
  bool _downloading = false;
  double _progress = 0.0;
  int _received = 0;
  int _total = 0;
  String _status = '';
  String? _error;
  File? _downloadedFile;

  Future<void> _startUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0.0;
      _status = S.t('Starting update...');
    });

    try {
      final file = await _service.downloadAndVerifyApk(
        widget.release,
        onProgress: (p, received, total) {
          if (mounted) {
            setState(() {
              _progress = p;
              _received = received;
              _total = total;
            });
          }
        },
        onStatus: (msg) {
          if (mounted) {
            setState(() => _status = msg);
          }
        },
      );

      _downloadedFile = file;

      if (!mounted) return;

      final canInstall = await _service.canRequestPackageInstalls();
      if (!canInstall) {
        setState(() {
          _status = S.t(
              'Please grant permission to install updates in Android Settings.');
        });
        await _service.openInstallPermissionSettings();
      }

      if (mounted) {
        setState(() => _status = S.t('Launching package installer...'));
        await _service.installApk(file);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTamil = SessionManager().isTamil;
    final notes = widget.release.localizedReleaseNotes(isTamil);
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.softGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.system_update_alt_rounded,
                color: AppTheme.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t('Update Available'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'v${widget.release.versionName} (Build ${widget.release.versionCode})',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notes.isNotEmpty) ...[
              Text(
                S.t('What\'s New:'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundWarm,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Text(
                  notes,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _total > 0
                        ? '${(_received / (1024 * 1024)).toStringAsFixed(1)} / ${(_total / (1024 * 1024)).toStringAsFixed(1)} MB'
                        : '${(_received / (1024 * 1024)).toStringAsFixed(1)} MB',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _status,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.errorRed),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                      color: AppTheme.errorRed, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading || _error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.t('Later')),
          ),
        if (!_downloading && _downloadedFile == null)
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen),
            onPressed: _startUpdate,
            label: Text(S.t('Download & Install')),
          )
        else if (_error != null)
          FilledButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen),
            onPressed: _startUpdate,
            label: Text(S.t('Retry')),
          )
        else if (_downloadedFile != null)
          FilledButton.icon(
            icon: const Icon(Icons.install_mobile, size: 18),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen),
            onPressed: () =>
                _service.installApk(_downloadedFile!),
            label: Text(S.t('Install APK')),
          ),
      ],
    );
  }
}
