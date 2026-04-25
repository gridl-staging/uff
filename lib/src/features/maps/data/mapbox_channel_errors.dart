import 'package:flutter/services.dart';

/// Whether a Mapbox platform-channel failure is safe to ignore in widget tests
/// and early platform-view lifecycles where the native channel is not attached.
bool isRecoverableMapboxChannelError(Object error) {
  if (error is MissingPluginException) {
    final message = error.message ?? '';
    return message.contains('annotation#create_manager') &&
        message.contains('plugins.flutter.io');
  }

  if (error is! PlatformException || error.code != 'channel-error') {
    return false;
  }

  final message = error.message ?? '';
  return message.contains('Unable to establish connection on channel') &&
      message.contains('mapbox_maps_flutter');
}
