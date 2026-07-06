-- ================================================================
--  修復 v2：改用 SECURITY DEFINER RPC 處理 anon 送出
-- ----------------------------------------------------------------
--  為什麼要這樣改：
--    supabase-js@2 的 .insert() 預設送 Prefer: return=representation，
--    這會讓 PostgREST 對剛 INSERT 的 row 做 RETURNING(等同 SELECT)。
--    但 anon 的 SELECT policy 是 `using (approved = true)`，
--    剛送出的 approved=false 資料看不到 → 報 42501。
--
--  RPC 用 SECURITY DEFINER 執行 → 以擁有者身分寫入，繞過 anon 的
--  RLS 邊界。這也是專案已有的 pattern(vote_suggestion 就是這樣)。
--
--  安全考量：
--    - 白名單長度檢查(避免 anon 灌爆資料庫)
--    - 硬編碼 approved=false / upvotes=0 / downvotes=0(anon 無法夾帶)
--    - set search_path = public 防搜尋路徑劫持
-- ================================================================

-- ── submit_bug ───────────────────────────────
create or replace function public.submit_bug(
  t_title text,
  t_description text,
  t_media_url text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id bigint;
begin
  -- 前端也會擋，這裡是最後一道防線
  if length(coalesce(trim(t_title), '')) = 0 then
    raise exception 'title required';
  end if;
  if length(coalesce(trim(t_description), '')) = 0 then
    raise exception 'description required';
  end if;
  if length(t_title) > 200 then
    raise exception 'title too long';
  end if;
  if length(t_description) > 4000 then
    raise exception 'description too long';
  end if;

  insert into public.bugs (title, description, media_url, approved)
    values (trim(t_title), trim(t_description), t_media_url, false)
    returning id into new_id;

  return new_id;
end;
$$;


-- ── submit_suggestion ────────────────────────
create or replace function public.submit_suggestion(
  t_title text,
  t_description text,
  t_media_url text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id bigint;
begin
  if length(coalesce(trim(t_title), '')) = 0 then
    raise exception 'title required';
  end if;
  if length(coalesce(trim(t_description), '')) = 0 then
    raise exception 'description required';
  end if;
  if length(t_title) > 200 then
    raise exception 'title too long';
  end if;
  if length(t_description) > 4000 then
    raise exception 'description too long';
  end if;

  insert into public.suggestions (title, description, media_url, approved, upvotes, downvotes)
    values (trim(t_title), trim(t_description), t_media_url, false, 0, 0)
    returning id into new_id;

  return new_id;
end;
$$;


-- ── 授權 anon + authenticated 呼叫 ────────────
grant execute on function public.submit_bug(text, text, text) to anon;
grant execute on function public.submit_bug(text, text, text) to authenticated;
grant execute on function public.submit_suggestion(text, text, text) to anon;
grant execute on function public.submit_suggestion(text, text, text) to authenticated;


-- ── 驗證 ─────────────────────────────────────
select
  routine_name,
  security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('submit_bug', 'submit_suggestion', 'vote_suggestion');
