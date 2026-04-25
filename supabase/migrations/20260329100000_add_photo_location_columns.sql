-- Add GPS coordinates to activity_photos for geotagged photo display.
-- Nullable: null means no GPS (e.g., gallery import). 0.0 is valid (equator).
ALTER TABLE public.activity_photos ADD COLUMN latitude double precision;
ALTER TABLE public.activity_photos ADD COLUMN longitude double precision;
