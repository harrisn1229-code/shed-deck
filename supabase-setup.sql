-- Note Cards sync: run this once in your Supabase project's SQL Editor.
--
-- Each set of linked devices shares one sync code. The table can't be read or
-- written directly; the app only calls note_cards_sync(), which needs the code.
-- It merges the ratings it is sent with the ones already stored (the newest
-- rating for each card wins) and returns the merged set.

create table if not exists public.note_cards_sync (
  code       text primary key check (code ~ '^[A-Za-z0-9]{20,64}$'),
  progress   jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.note_cards_sync enable row level security;
revoke all on table public.note_cards_sync from anon, authenticated;

create or replace function public.note_cards_sync(p_code text, p_progress jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  merged jsonb;
begin
  if p_code is null or p_code !~ '^[A-Za-z0-9]{20,64}$' then
    raise exception 'invalid sync code';
  end if;
  if p_progress is null or jsonb_typeof(p_progress) <> 'object' then
    p_progress := '{}'::jsonb;
  end if;
  if pg_column_size(p_progress) > 300000 then
    raise exception 'too many ratings in one request';
  end if;

  insert into note_cards_sync (code) values (p_code) on conflict (code) do nothing;
  perform 1 from note_cards_sync where code = p_code for update;

  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into merged
  from (
    select distinct on (k) k, v
    from (
      select e.key as k, e.value as v from note_cards_sync s, jsonb_each(s.progress) e where s.code = p_code
      union all
      select e.key, e.value from jsonb_each(p_progress) e
    ) both_sides
    where jsonb_typeof(v) = 'object'
    order by k, case when jsonb_typeof(v -> 't') = 'number' then (v ->> 't')::numeric else 0 end desc
  ) newest;

  if pg_column_size(merged) > 300000 then
    raise exception 'sync data too large';
  end if;

  update note_cards_sync set progress = merged, updated_at = now() where code = p_code;
  return merged;
end;
$$;

revoke all on function public.note_cards_sync(text, jsonb) from public;
grant execute on function public.note_cards_sync(text, jsonb) to anon, authenticated;
