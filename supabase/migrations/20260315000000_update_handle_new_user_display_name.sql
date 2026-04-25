-- Propagate display_name from auth metadata into profiles on user creation.
-- The client passes data: {'display_name': value} during signUp(), which
-- Supabase stores in auth.users.raw_user_meta_data. This trigger reads it
-- so the profile row is complete without a separate client-side update.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name');

  return new;
end;
$$;
