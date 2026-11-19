// Detection d'une nouvelle version publiee (web) : lit version.json sur le
// serveur et propose de recharger. Hors web : rien a faire (le store gere).
export 'app_update_io.dart' if (dart.library.js_interop) 'app_update_web.dart';
