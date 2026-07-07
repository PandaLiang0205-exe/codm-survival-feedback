-- ================================================================
--  補丁:新增站點統計(瀏覽次數)
-- ----------------------------------------------------------------
--  為什麼要用 DB：
--    - BUG / 建議「數量」前端直接 count(...) 就好,不需要 DB 存
--    - 但「瀏覽次數」必須所有訪客共用,一定得存在後端
--    - 用一張單列表(id=1)存全站 visits 累加值,結構最簡單
--
--  安全:
--    - anon 只能 SELECT(讀 visits) 與呼叫 RPC(讓後端 +1)
--    - 不允許 anon 直接 UPDATE visits(不然可以設 999999)
--    - RPC 走 SECURITY DEFINER 才能寫入
-- ================================================================


-- ── [1] 建表 ─────────────────────────────────
-- 單列表 pattern:id=1 永遠只有這一列。
-- 用 int primary key 而不是 identity,因為我們就是「這一列 = 全站 stats」。
create table if not exists public.site_stats (
  id     int    primary key,
  visits bigint not null default 0
);

-- 初始化那一列(存在就跳過)
insert into public.site_stats (id, visits)
  values (1, 0)
  on conflict (id) do nothing;


-- ── [2] RLS ──────────────────────────────────
alter table public.site_stats enable row level security;

-- 讀:公開,任何人都能看到目前瀏覽次數
drop policy if exists "stats_public_select" on public.site_stats;
create policy "stats_public_select"
  on public.site_stats
  for select
  to anon, authenticated
  using (true);

-- 注意:「沒有」寫 anon 的 UPDATE 政策 → anon 不能直接改 visits。
-- 唯一寫入方式是透過下方的 increment_visits() RPC。


-- ── [3] +1 RPC ───────────────────────────────
-- 呼叫一次 visits += 1;回傳更新後的值以便前端立刻顯示。
-- SECURITY DEFINER → 以 owner 身分執行,繞過 anon 的 RLS 邊界。
create or replace function public.increment_visits()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_visits bigint;
begin
  update public.site_stats
     set visits = visits + 1
   where id = 1
   returning visits into new_visits;
  return new_visits;
end;
$$;

-- 授權 anon 與 authenticated 呼叫
grant execute on function public.increment_visits() to anon;
grant execute on function public.increment_visits() to authenticated;


-- ── [4] 驗證 ─────────────────────────────────
-- 執行後應看到 site_stats 一列 + increment_visits(DEFINER)
select id, visits from public.site_stats;

select
  routine_name,
  security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'increment_visits';
