/// Configuration de l'accès au backend SabiData.
class ApiConfig {
  /// URL de base de l'API.
  ///
  /// Priorité :
  /// 1. `--dart-define=API_BASE_URL=https://…` (prod / CI)
  /// 2. défaut LAN ci-dessous (dev local)
  ///
  /// Exemples :
  /// ```bash
  /// flutter run --dart-define=API_BASE_URL=https://sabidata-backend.up.railway.app
  /// flutter run   # utilise le défaut LAN
  /// ```
  /// Émulateur Android : `http://10.0.2.2:3000`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.11.124:3000',
  );
}
