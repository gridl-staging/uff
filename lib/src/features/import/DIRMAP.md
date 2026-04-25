<!-- [scrai:start] -->
## import

| File | Summary |
| --- | --- |

| Directory | Summary |
| --- | --- |
| application | The ImportPipeline orchestrates parsing of FIT/GPX fitness activity files, normalizing the data, persisting to the local database, and queuing for backend sync. |
| data | StravaZipImporter decodes Strava ZIP exports and imports activity files (FIT, GPX, FIT.GZ) through a pipeline, returning success/failure counts with detailed error tracking and progress callbacks. |
| domain | — |
| presentation | ImportScreen is a Flutter widget that lets users import fitness activities from FIT, GPX, or ZIP files, with file selection, parsing, persistence, and detailed UI feedback for both single-file and batch imports. |
<!-- [scrai:end] -->
