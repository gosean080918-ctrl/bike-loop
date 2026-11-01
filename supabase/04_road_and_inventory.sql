-- ============================================================
-- 04: store road routes and extend inventory management
-- ID number format: {district}_{collectionDateYYYYMMDD}_{3-digit sequence}
--   e.g. Seogwipo-si_20260721_001
--   district = second token of the report address; falls back to 'Jeju'
-- Run this whole file in the SQL editor. Safe to re-run.
-- ============================================================

-- Store the road polyline (from Kakao Mobility) on the collection job
alter table public.collection_jobs
  add column if not exists route_polyline jsonb;

-- Inventory: ID number and storage location
alter table public.bikes
  add column if not exists code text unique;

alter table public.bikes
  add column if not exists storage_location text not null default '';

-- Drop the old default and sequence in case an earlier version of 04 was applied
alter table public.bikes alter column code drop default;
drop sequence if exists public.bike_code_seq;

-- Trigger that generates the ID number: {district}_{YYYYMMDD}_{NNN}
create or replace function public.gen_bike_code()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_addr text;
  v_region text;
  v_date text;
  v_prefix text;
  v_seq int;
begin
  if new.code is not null then
    return new;
  end if;

  select address into v_addr
    from public.reports where id = new.report_id;

  -- Take the second token of the address (the city or county)
  v_region := nullif(split_part(coalesce(v_addr, ''), ' ', 2), '');
  if v_region is null then
    v_region := '제주';
  end if;

  v_date := to_char(coalesce(new.collected_at, now()), 'YYYYMMDD');
  v_prefix := v_region || '_' || v_date || '_';

  select count(*) + 1 into v_seq
    from public.bikes where code like v_prefix || '%';

  new.code := v_prefix || lpad(v_seq::text, 3, '0');
  return new;
end;
$$;

drop trigger if exists bikes_gen_code on public.bikes;
create trigger bikes_gen_code
  before insert on public.bikes
  for each row execute function public.gen_bike_code();

-- Backfill the new format onto existing rows (no code, or the old BK- format)
do $$
declare
  r record;
  v_addr text;
  v_region text;
  v_date text;
  v_prefix text;
  v_seq int;
begin
  for r in
    select b.id, b.report_id, b.collected_at
      from public.bikes b
      where b.code is null or b.code like 'BK-%'
      order by b.collected_at
  loop
    select address into v_addr
      from public.reports where id = r.report_id;
    v_region := nullif(split_part(coalesce(v_addr, ''), ' ', 2), '');
    if v_region is null then v_region := '제주'; end if;
    v_date := to_char(coalesce(r.collected_at, now()), 'YYYYMMDD');
    v_prefix := v_region || '_' || v_date || '_';
    select count(*) + 1 into v_seq
      from public.bikes where code like v_prefix || '%';
    update public.bikes
      set code = v_prefix || lpad(v_seq::text, 3, '0')
      where id = r.id;
  end loop;
end;
$$;
