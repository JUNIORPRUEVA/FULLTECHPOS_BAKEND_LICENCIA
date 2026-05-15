enum AppEnvironment { local, staging, production }

class AppConfig {
  AppConfig._();

  static const String environmentName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'local',
  );
  static const String apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String _cloudBaseUrl =
      'https://fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host';
  static const String _localBaseUrl = _cloudBaseUrl;
  static const String _stagingBaseUrl = _cloudBaseUrl;
  static const String _productionBaseUrl = _cloudBaseUrl;

  static AppEnvironment get environment {
    switch (environmentName.toLowerCase().trim()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.local;
    }
  }

  static String get baseUrl {
    final override = apiBaseUrlOverride.trim();
    if (override.isNotEmpty) {
      return override.replaceFirst(RegExp(r'/$'), '');
    }

    switch (environment) {
      case AppEnvironment.local:
        return _localBaseUrl;
      case AppEnvironment.staging:
        return _stagingBaseUrl;
      case AppEnvironment.production:
        return _productionBaseUrl;
    }
  }

  static bool get isDebug => environment != AppEnvironment.production;

  static const Duration requestTimeout = Duration(seconds: 30);
  static const String sessionKey = 'sessionId';
}
