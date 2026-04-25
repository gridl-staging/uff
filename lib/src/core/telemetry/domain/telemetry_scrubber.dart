typedef JsonMap = Map<String, Object?>;

// TODO(uff): Document TelemetryScrubber.
/// TODO: Document TelemetryScrubber.
class TelemetryScrubber {
  TelemetryScrubber({
    this.maxExceptionMessageLength = 1024,
    this.maxStackTraceLength = 8192,
  });

  final int maxExceptionMessageLength;
  final int maxStackTraceLength;

  static const Set<String> _forbiddenKeySubstrings = <String>{
    'token',
    'authorization',
    'password',
    'secret',
    'cookie',
  };
  static final RegExp _bearerCredentialPattern = RegExp(
    r'\bbearer\s+[A-Za-z0-9\-._~+/]+=*',
    caseSensitive: false,
  );
  static final RegExp _inlineCredentialPattern = RegExp(
    "\\b([A-Za-z0-9_.-]*(?:token|authorization|password|secret|cookie|api[_-]?key|session(?:[_-]?id)?|jwt)[A-Za-z0-9_.-]*)\\b(\\s*[:=]\\s*)(\"[^\"]*\"|'[^']*'|(?:Bearer\\s+)?[^,;\\s]+)",
    caseSensitive: false,
  );
  static const String _redactedValue = '[REDACTED]';

  JsonMap scrubContext(JsonMap context) {
    return _scrubScalarMap(context);
  }

  JsonMap scrubBreadcrumbMetadata(JsonMap metadata) {
    return _scrubScalarMap(metadata);
  }

  JsonMap _scrubScalarMap(JsonMap source) {
    final scrubbed = <String, Object?>{};

    for (final entry in source.entries) {
      final key = entry.key;
      if (_isForbiddenKey(key)) {
        continue;
      }

      final scalarValue = _validateScalarValue(key: key, value: entry.value);
      scrubbed[key] = _applyTruncationPolicy(key: key, value: scalarValue);
    }

    return Map<String, Object?>.unmodifiable(scrubbed);
  }

  bool _isForbiddenKey(String key) {
    final normalizedKey = key.toLowerCase();
    return _forbiddenKeySubstrings.any(normalizedKey.contains);
  }

  Object? _validateScalarValue({required String key, required Object? value}) {
    if (value == null || value is bool || value is String) {
      return value;
    }

    if (value is num && value.isFinite) {
      return value;
    }

    throw ArgumentError.value(
      value,
      key,
      'Telemetry values must be null, bool, String, or finite num.',
    );
  }

  Object? _applyTruncationPolicy({
    required String key,
    required Object? value,
  }) {
    if (value is! String) {
      return value;
    }

    final scrubbedValue = _redactSensitiveStringFragments(value);

    final maxLength = switch (key) {
      'exceptionMessage' => maxExceptionMessageLength,
      'stackTrace' => maxStackTraceLength,
      _ => null,
    };

    if (maxLength == null || scrubbedValue.length <= maxLength) {
      return scrubbedValue;
    }

    return scrubbedValue.substring(0, maxLength);
  }

  String _redactSensitiveStringFragments(String value) {
    final inlineScrubbed = value.replaceAllMapped(_inlineCredentialPattern, (
      Match match,
    ) {
      final key = match.group(1)!;
      final separator = match.group(2)!;
      return '$key$separator$_redactedValue';
    });
    return inlineScrubbed.replaceAllMapped(
      _bearerCredentialPattern,
      (_) => 'Bearer $_redactedValue',
    );
  }
}
