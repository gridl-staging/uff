<!-- [scrai:start] -->
## features

| File | Summary |
| --- | --- |

| Directory | Summary |
| --- | --- |
| activity_tracking | — |
| analytics | The analytics module provides performance tracking and visualization for the UFF app, featuring PMC charts, training load metrics, and race prediction cards as interactive presentation components. |
| auth | The auth directory provides authentication functionality through a Supabase-backed data layer with repository abstractions for OAuth configuration and user operations, combined with a presentation layer that includes login and signup screens plus reusable social authentication components. |
| clubs | The clubs module provides geolocation-based club discovery and management, consisting of a Riverpod-powered application layer that queries clubs by proximity and handles membership/run mutations with cache invalidation, a Supabase data layer for backend access, and presentation screens for listing, viewing, creating, and managing clubs and their runs. |
| gear | The gear feature allows users to manage their equipment with a Supabase-backed data layer handling CRUD operations and presentation screens for viewing and editing gear items. |
| import | The import feature enables users to import fitness activities from FIT, GPX, or Strava ZIP files through an interactive Flutter UI. |
| legal | — |
| maps | — |
| notifications | — |
| onboarding | The onboarding directory manages the initial user onboarding flow, with a presentation layer containing the onboarding_screen.dart component that renders the onboarding UI and handles the user's first-time setup experience. |
| photos | The photos module provides complete activity photo management across three layers: data persistence with device selection and Supabase backend storage, domain entities for activity photos and upload-pending states, and presentation components for gallery browsing, full-screen viewing, and upload/delete operations. |
| profile | — |
| settings | The settings directory contains Flutter UI components for the settings feature, with a main settings screen composed of modular sections and a dedicated HR zone setup screen. |
| social | The social directory contains presentation layer UI screens for managing user interactions including activity comments, user profiles, follow requests, and relationship discovery. |
<!-- [scrai:end] -->
