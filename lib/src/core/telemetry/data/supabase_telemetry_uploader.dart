import 'package:supabase_flutter/supabase_flutter.dart' show FunctionResponse;
import 'package:uff/src/core/telemetry/service/telemetry_uploader.dart';

typedef TelemetryFunctionInvoker =
    Future<FunctionResponse> Function(
      String name, {
      Object? body,
    });

/// TODO: Document SupabaseTelemetryUploader.
class SupabaseTelemetryUploader implements TelemetryUploader {
  SupabaseTelemetryUploader({required TelemetryFunctionInvoker invoke})
    : _invoke = invoke;

  final TelemetryFunctionInvoker _invoke;

  @override
  Future<bool> upload(JsonMap row) async {
    try {
      final response = await _invoke('ingest-telemetry', body: row);
      return _isSuccessfulResponse(response);
    } on Object {
      return false;
    }
  }

  bool _isSuccessfulResponse(FunctionResponse response) {
    final responseData = response.data;
    if (response.status != 200 || responseData is! Map<Object?, Object?>) {
      return false;
    }

    return responseData['success'] == true;
  }
}
