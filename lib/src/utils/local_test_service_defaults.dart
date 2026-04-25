/// Shared non-secret defaults for local test infrastructure.
///
/// These values match the committed local Supabase configuration that the repo
/// already uses in shell/JS smoke scripts. The Mapbox token is only a
/// placeholder for test bootstrapping.
abstract final class LocalTestServiceDefaults {
  static const supabaseUrl = 'http://127.0.0.1:54321';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.'
      'CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
  static const mapboxAccessToken = 'pk.test-token';
}
