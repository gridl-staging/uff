-- Local dev seed file.
--
-- The local seed runner cannot persist custom app.* database settings, so this
-- file intentionally avoids ALTER DATABASE / ALTER ROLE statements.
-- notify_send_notification() falls back to the local API URL automatically,
-- but DB-triggered calls still need a non-empty app.webhook_secret setting if
-- you want end-to-end webhook authentication to succeed locally.
--
-- For hosted deployment, set these once after linking the project:
--   ALTER DATABASE postgres SET app.supabase_url = 'https://<ref>.supabase.co';
--   ALTER DATABASE postgres SET app.webhook_secret = '<your-webhook-secret>';

-- Club discovery seed data
insert into public.clubs (
  name,
  description,
  city,
  state_region,
  country,
  location_lat,
  location_lng,
  source,
  source_url,
  source_id,
  creator_id,
  claimed_by,
  member_count
) values
  ('Portland Frontrunners', null, 'Portland', 'OR', 'US', 45.5229, -122.6810, 'auto_discovered', null, 'rrca:portland-frontrunners', null, null, 0),
  ('Forest Park Striders', null, 'Portland', 'OR', 'US', 45.5626, -122.7289, 'auto_discovered', null, 'rrca:forest-park-striders', null, null, 0),
  ('Willamette River Run Club', null, 'Portland', 'OR', 'US', 45.5152, -122.6696, 'auto_discovered', null, 'rrca:willamette-river-run-club', null, null, 0),
  ('Rose City Runners', null, 'Portland', 'OR', 'US', 45.5264, -122.6582, 'auto_discovered', null, 'rrca:rose-city-runners', null, null, 0),
  ('Eastside Tempo Crew', null, 'Portland', 'OR', 'US', 45.5343, -122.6359, 'auto_discovered', null, 'rrca:eastside-tempo-crew', null, null, 0),
  ('Austin Marathon Project', null, 'Austin', 'TX', 'US', 30.2674, -97.7429, 'auto_discovered', null, 'rrca:austin-marathon-project', null, null, 0),
  ('Lady Bird Lake Runners', null, 'Austin', 'TX', 'US', 30.2599, -97.7478, 'auto_discovered', null, 'rrca:lady-bird-lake-runners', null, null, 0),
  ('South Congress Run Club', null, 'Austin', 'TX', 'US', 30.2504, -97.7496, 'auto_discovered', null, 'rrca:south-congress-run-club', null, null, 0),
  ('Barton Creek Trail Runners', null, 'Austin', 'TX', 'US', 30.2649, -97.7712, 'auto_discovered', null, 'rrca:barton-creek-trail-runners', null, null, 0),
  ('ATX Sunrise Striders', null, 'Austin', 'TX', 'US', 30.2748, -97.7330, 'auto_discovered', null, 'rrca:atx-sunrise-striders', null, null, 0),
  ('Central Park Track Club', null, 'New York', 'NY', 'US', 40.7812, -73.9665, 'auto_discovered', null, 'rrca:central-park-track-club', null, null, 0),
  ('Brooklyn Bridge Run Club', null, 'New York', 'NY', 'US', 40.7061, -73.9969, 'auto_discovered', null, 'rrca:brooklyn-bridge-run-club', null, null, 0),
  ('Riverside Tempo NYC', null, 'New York', 'NY', 'US', 40.8007, -73.9704, 'auto_discovered', null, 'rrca:riverside-tempo-nyc', null, null, 0),
  ('Queens Night Runners', null, 'New York', 'NY', 'US', 40.7421, -73.8465, 'auto_discovered', null, 'rrca:queens-night-runners', null, null, 0),
  ('Downtown Manhattan Striders', null, 'New York', 'NY', 'US', 40.7128, -74.0060, 'auto_discovered', null, 'rrca:downtown-manhattan-striders', null, null, 0),
  ('Chicago Lakefront Runners', null, 'Chicago', 'IL', 'US', 41.8827, -87.6233, 'auto_discovered', null, 'rrca:chicago-lakefront-runners', null, null, 0),
  ('West Loop Running Club', null, 'Chicago', 'IL', 'US', 41.8864, -87.6485, 'auto_discovered', null, 'rrca:west-loop-running-club', null, null, 0),
  ('Lincoln Park Striders', null, 'Chicago', 'IL', 'US', 41.9214, -87.6513, 'auto_discovered', null, 'rrca:lincoln-park-striders', null, null, 0),
  ('South Side Distance Crew', null, 'Chicago', 'IL', 'US', 41.7914, -87.6016, 'auto_discovered', null, 'rrca:south-side-distance-crew', null, null, 0),
  ('Wicker Park Run Collective', null, 'Chicago', 'IL', 'US', 41.9088, -87.6795, 'auto_discovered', null, 'rrca:wicker-park-run-collective', null, null, 0),
  ('Denver Run Collective', null, 'Denver', 'CO', 'US', 39.7392, -104.9903, 'auto_discovered', null, 'rrca:denver-run-collective', null, null, 0),
  ('Cherry Creek Striders', null, 'Denver', 'CO', 'US', 39.7197, -104.9488, 'auto_discovered', null, 'rrca:cherry-creek-striders', null, null, 0),
  ('City Park Track Club', null, 'Denver', 'CO', 'US', 39.7478, -104.9496, 'auto_discovered', null, 'rrca:city-park-track-club', null, null, 0),
  ('High Line Canal Runners', null, 'Denver', 'CO', 'US', 39.7050, -104.9008, 'auto_discovered', null, 'rrca:high-line-canal-runners', null, null, 0),
  ('Capitol Hill Tempo Denver', null, 'Denver', 'CO', 'US', 39.7347, -104.9775, 'auto_discovered', null, 'rrca:capitol-hill-tempo-denver', null, null, 0);
