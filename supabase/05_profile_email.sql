-- ============================================================
-- BikeReclaim — profiles.email 추가 (ADM-10 신고자 표시용)
-- 적용: Supabase 대시보드 > SQL Editor 에 전체 붙여넣고 Run
-- ============================================================
-- 왜 필요한가:
--   이메일 원본은 auth.users에 있는데, 앱은 anon key라서 남의 auth
--   레코드를 읽을 수 없다. 그래서 profiles로 복사해두고 RLS로 보호한다.
--
-- 개인정보 관점:
--   profiles_select 정책이 이미 "본인 또는 관리자"만 허용하므로
--   일반 사용자는 남의 이메일을 절대 조회할 수 없다.
--   (02_rls.sql: using (id = auth.uid() or public.is_admin()))
--   관리자의 열람 목적은 '신고 처리' — 수집 목적 범위 내 이용.
-- ============================================================

-- 1) 컬럼 추가
alter table public.profiles
  add column if not exists email text not null default '';

-- 2) 기존 가입자 백필 (auth.users에서 복사)
update public.profiles p
   set email = u.email
  from auth.users u
 where u.id = p.id
   and coalesce(p.email, '') = '';

-- 3) 신규 가입 시 자동 저장 — 기존 트리거 함수 교체
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', ''),
    coalesce(new.email, '')
  );
  return new;
end;
$$;

-- 4) 이메일 변경 시 동기화 (선택이지만 있으면 안전)
create or replace function public.sync_profile_email()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update public.profiles
     set email = coalesce(new.email, '')
   where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.sync_profile_email();

-- 5) 확인용
-- select id, display_name, email, role from public.profiles;
