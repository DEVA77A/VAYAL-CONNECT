import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../utils/commerce_strings.dart';

class LocationGateScreen extends StatefulWidget {
  final Widget home;
  final LocationService? locationService;
  final ApiClient? api;
  const LocationGateScreen(
      {super.key, required this.home, this.locationService, this.api});
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
        await _api.request('/api/v1/users/me/location',
            method: 'PUT',
            body: {'latitude': result.latitude, 'longitude': result.longitude});
        if (mounted) {
          Navigator.of(context)
              .pushReplacement(MaterialPageRoute(builder: (_) => widget.home));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(S.t('Location required'))),
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_outlined, size: 64),
                const SizedBox(height: 20),
                Text(
                    S.t('Location supports farm discovery and distance estimates. Allow foreground location to continue. GPS does not replace a delivery address.'),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (_state != null && _state != LocationState.available)
                  Text(S.t(switch (_state!) {
                    LocationState.disabled =>
                      'Turn on location services, then retry.',
                    LocationState.permanentlyDenied =>
                      'Enable location permission in app settings.',
                    LocationState.denied =>
                      'Permission denied. Retry when ready.',
                    _ => 'Unable to obtain coordinates. Please retry.',
                  })),
                if (_error != null) Text(_error!),
                if (_busy)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                      onPressed: _allow, child: Text(S.t('Allow location'))),
                if (_state == LocationState.permanentlyDenied ||
                    _state == LocationState.disabled)
                  TextButton(
                      onPressed: () => LocationService.openSettings(
                          services: _state == LocationState.disabled),
                      child: Text(S.t('Open settings'))),
              ]))));
}
