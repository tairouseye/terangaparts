import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_info.dart';
import '../theme/app_theme.dart';
import '../utils/app_update.dart';

/// « Une nouvelle version est disponible » (inspire de GesSchool).
///
/// Le navigateur peut garder l'ancienne version de l'app ouverte longtemps :
/// personne ne sait qu'il y a du neuf. On compare la version embarquee
/// au build (AppInfo.appVersion) a celle publiee sur le serveur
/// (version.json) au demarrage, toutes les 5 minutes et au retour sur
/// l'onglet ; si elles different, un bandeau propose de recharger.
class UpdateWatcher extends StatefulWidget {
  final Widget child;
  const UpdateWatcher({super.key, required this.child});

  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher>
    with WidgetsBindingObserver {
  static const _interval = Duration(minutes: 5);
  String? _current; // « 1.3.0+5 »
  String? _available; // version publiee differente
  bool _dismissed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    _current = AppInfo.appVersion.isEmpty ? null : AppInfo.appVersion;
    if (_current == null) return; // build sans version embarquee (dev)
    await _check();
    _timer = Timer.periodic(_interval, (_) => _check());
  }

  Future<void> _check() async {
    final published = await fetchPublishedVersion();
    if (!mounted || published == null || _current == null) return;
    if (published != _current && published != _available) {
      setState(() {
        _available = published;
        _dismissed = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = _available != null && !_dismissed;
    return Stack(
      children: [
        widget.child,
        if (show)
          Positioned(
            left: 12,
            right: 12,
            bottom: 64,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    elevation: 6,
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      child: Row(children: [
                        const Icon(Icons.system_update, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nouvelle version disponible '
                            '(v${_available!.split('+').first}).',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: reloadApp,
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.or),
                          child: const Text('Mettre à jour'),
                        ),
                        IconButton(
                          tooltip: 'Plus tard',
                          onPressed: () => setState(() => _dismissed = true),
                          icon: const Icon(Icons.close,
                              color: Colors.white70, size: 20),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
