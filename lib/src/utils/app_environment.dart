const defaultAppEnvironmentName = 'dev';

const _environmentAssetByName = <String, String>{
  'dev': '.env.dev',
  'staging': '.env.staging',
  'prod': '.env.prod',
};

final supportedAppEnvironmentNames = List<String>.unmodifiable(
  _environmentAssetByName.keys,
);

final runtimeEnvironmentAssetNames = List<String>.unmodifiable(
  _environmentAssetByName.values,
);

const runtimeEnvironmentSetupGuidance =
    'Set APP_ENV to dev, staging, or prod and add non-empty values to '
    'the matching .env.dev, .env.staging, or .env.prod file.';

String readConfiguredAppEnvironment() {
  return const String.fromEnvironment(
    'APP_ENV',
    defaultValue: defaultAppEnvironmentName,
  );
}

String resolveRuntimeEnvironmentAsset() {
  return resolveEnvironmentAssetForName(readConfiguredAppEnvironment());
}

String resolveEnvironmentAssetForName(String environmentName) {
  final normalizedEnvironmentName = environmentName.trim();
  final resolvedAsset = _environmentAssetByName[normalizedEnvironmentName];
  if (resolvedAsset != null) {
    return resolvedAsset;
  }

  throw StateError(
    'Unsupported APP_ENV value "$environmentName". '
    'Supported APP_ENV values: ${supportedAppEnvironmentNames.join(', ')}.',
  );
}

String requireEnvironmentValue({
  required Map<String, String> environment,
  required String key,
}) {
  final value = environment[key]?.trim() ?? '';
  if (value.isEmpty) {
    throw StateError('Missing required $key. $runtimeEnvironmentSetupGuidance');
  }
  return value;
}
