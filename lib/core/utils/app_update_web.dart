import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Version publiee sur le serveur (« 1.3.0+5 »), lue dans version.json sans
/// passer par le cache du navigateur. null si illisible (hors ligne...).
Future<String?> fetchPublishedVersion() async {
  try {
    final url = 'version.json?t=${DateTime.now().millisecondsSinceEpoch}';
    final res = await web.window
        .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
        .toDart;
    if (!res.ok) return null;
    final text = (await res.text().toDart).toDart;
    final data = jsonDecode(text) as Map<String, dynamic>;
    final v = data['version'] as String?;
    final b = data['build_number'] as String?;
    if (v == null) return null;
    return b == null || b.isEmpty ? v : '$v+$b';
  } catch (_) {
    return null;
  }
}

/// Recharge la page pour charger la nouvelle version.
void reloadApp() => web.window.location.reload();
