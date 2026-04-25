<!-- [scrai:start] -->
## functions

| File | Summary |
| --- | --- |

| Directory | Summary |
| --- | --- |
| delete-my-account | This Edge Function handles self-service account deletion by verifying the user's JWT, removing all storage objects (avatars and activity photos) from Supabase storage buckets, and deleting the auth.users row to cascade-delete all related profile, activity, and track data. |
| discover-clubs | — |
| ingest-telemetry | Supabase Edge Function that ingests telemetry events from authenticated clients, validates Bearer tokens against JWT, maps camelCase payloads to the telemetry_events table, and handles idempotent upserts by event_id. |
| send-notification | A Supabase Edge Function that routes database webhooks (from kudos, comments, and follow-accept events) to recipients and sends push notifications via Firebase Cloud Messaging, with automatic cleanup of stale tokens on delivery failures. |
<!-- [scrai:end] -->
