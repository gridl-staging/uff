-- Stage 5 security hardening for profiles private fields.
--
-- Keep direct cross-user profile reads limited to public identity fields while
-- exposing full self-profile reads through an auth-scoped SECURITY DEFINER RPC.

revoke select on table public.profiles from authenticated;
grant select (id, display_name, avatar_url, created_at, updated_at)
  on table public.profiles
  to authenticated;

create or replace function public.get_my_profile()
returns setof public.profiles
language sql
security definer
set search_path = public
stable
as $$
  select *
  from public.profiles
  where id = auth.uid();
$$;

grant execute on function public.get_my_profile()
  to authenticated, service_role;
revoke execute on function public.get_my_profile()
  from anon, public;
