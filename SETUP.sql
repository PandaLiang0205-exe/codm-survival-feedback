-- ================================================================
--  CoDM 生存模式意見板 — Supabase 後端建置腳本
-- ----------------------------------------------------------------
--  執行方式：Supabase Dashboard → SQL Editor → 貼上執行
--
--  完整流程說明（先讀完再執行）：
--    1. 本檔會建立兩張表(bugs / suggestions)、啟用 RLS、設定政策、
--       建立投票用的 SECURITY DEFINER 函式、給 anon 執行權限。
--    2. Storage bucket "media" 需要「你自己在後台手動建立」。
--       建完 bucket 後，本檔最下方有可選的 storage policy SQL，
--       你可以選擇「後台 GUI 設定」或「直接跑 SQL」二擇一。
--    3. 管理員帳號用 Supabase Auth 建立(後台 → Authentication → Add user)。
--
--  為什麼要這樣設計：
--    - anon key 會出現在前端 JS 是正常的，所以第一道防線是 RLS。
--    - 訪客只能讀 approved=true → 保證主頁看不到未審核內容。
--    - 訪客 INSERT 被強制 approved=false → 送出即進審核佇列。
--    - 投票走 RPC(SECURITY DEFINER) → anon 不能直接改 upvotes 欄位，
--      只能透過受限的函式呼叫，避免 anon 亂改任意欄位。
-- ================================================================


-- ───────────────────────────────────────────────
-- [1] 建立 bugs 資料表
-- ───────────────────────────────────────────────
-- 這張表用來存 Bug 回報。approved 預設 false，代表送出後
-- 必須經管理員審核才會顯示在主頁；media_url 存 Storage 的公開 URL。
create table if not exists public.bugs (
  id           bigint generated always as identity primary key,
  title        text        not null,
  description  text        not null,
  media_url    text,
  created_at   timestamptz not null default now(),
  approved     boolean     not null default false
);


-- ───────────────────────────────────────────────
-- [2] 建立 suggestions 資料表
-- ───────────────────────────────────────────────
-- 建議表比 bugs 多兩個欄位：upvotes / downvotes。
-- 這兩個欄位「不允許」訪客直接 UPDATE，只能透過下面的
-- vote_suggestion() RPC 呼叫 +1，避免 anon 直接把票數寫成 9999。
create table if not exists public.suggestions (
  id           bigint generated always as identity primary key,
  title        text        not null,
  description  text        not null,
  media_url    text,
  created_at   timestamptz not null default now(),
  approved     boolean     not null default false,
  upvotes      integer     not null default 0,
  downvotes    integer     not null default 0
);


-- ───────────────────────────────────────────────
-- [3] 啟用 Row Level Security(RLS)
-- ───────────────────────────────────────────────
-- Supabase 預設不會擋 anon，一定要 enable RLS 後 policy 才有效。
-- 沒開 RLS 的話，anon key 可以無限制讀寫整張表。
alter table public.bugs        enable row level security;
alter table public.suggestions enable row level security;


-- ================================================================
--  [4] bugs 的 RLS 政策
-- ================================================================

-- ── 4-1. anon 讀取：只能看到已審核的列 ───────────────
-- 這條政策保證：訪客(未登入)呼叫 SELECT 時，未審核資料完全不存在於回應中。
-- 「送出後主頁看不到」這個驗收項目由這條實作。
drop policy if exists "bugs_anon_select_approved" on public.bugs;
create policy "bugs_anon_select_approved"
  on public.bugs
  for select
  to anon
  using (approved = true);

-- ── 4-2. authenticated(管理員)讀取：全部可讀 ────────
-- 管理員登入後才看得到待審核佇列，用於 admin.html。
drop policy if exists "bugs_auth_select_all" on public.bugs;
create policy "bugs_auth_select_all"
  on public.bugs
  for select
  to authenticated
  using (true);

-- ── 4-3. anon 新增：強制 approved=false ─────────────
-- with check 是 INSERT 時的欄位驗證。就算 anon 在 payload 硬塞
-- approved=true，這條會直接拒絕。搭配欄位 default false，
-- 前端不用管 approved 也能成功送出。
drop policy if exists "bugs_anon_insert" on public.bugs;
create policy "bugs_anon_insert"
  on public.bugs
  for insert
  to anon
  with check (approved = false);

-- ── 4-4. authenticated 更新:核准用 ─────────────────
-- 管理員把 approved 從 false 改成 true，該筆才會在主頁出現。
drop policy if exists "bugs_auth_update" on public.bugs;
create policy "bugs_auth_update"
  on public.bugs
  for update
  to authenticated
  using (true)
  with check (true);

-- ── 4-5. authenticated 刪除:拒絕用 ─────────────────
-- 管理員的「拒絕」動作 = DELETE，直接把該筆從資料庫移除。
drop policy if exists "bugs_auth_delete" on public.bugs;
create policy "bugs_auth_delete"
  on public.bugs
  for delete
  to authenticated
  using (true);


-- ================================================================
--  [5] suggestions 的 RLS 政策(結構跟 bugs 同,只有 insert 多防護)
-- ================================================================

drop policy if exists "suggestions_anon_select_approved" on public.suggestions;
create policy "suggestions_anon_select_approved"
  on public.suggestions
  for select
  to anon
  using (approved = true);

drop policy if exists "suggestions_auth_select_all" on public.suggestions;
create policy "suggestions_auth_select_all"
  on public.suggestions
  for select
  to authenticated
  using (true);

-- 注意這裡的 with check：不只擋 approved=true，還擋非零的初始票數。
-- 為什麼要擋？因為 anon 若能任意寫 upvotes=999 進來，投票就形同虛設。
drop policy if exists "suggestions_anon_insert" on public.suggestions;
create policy "suggestions_anon_insert"
  on public.suggestions
  for insert
  to anon
  with check (approved = false and upvotes = 0 and downvotes = 0);

drop policy if exists "suggestions_auth_update" on public.suggestions;
create policy "suggestions_auth_update"
  on public.suggestions
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "suggestions_auth_delete" on public.suggestions;
create policy "suggestions_auth_delete"
  on public.suggestions
  for delete
  to authenticated
  using (true);


-- ================================================================
--  [6] 投票 RPC — SECURITY DEFINER
-- ----------------------------------------------------------------
--  為什麼要用 RPC？
--    RLS 的 UPDATE 政策只能控制「哪些列可以改」，沒辦法控制
--    「哪些欄位可以改」。如果我們給 anon UPDATE，他就可以把
--    title/description 一起改掉。所以用 SECURITY DEFINER 函式
--    當閘門：只允許把 upvotes 或 downvotes +1，其他都碰不到。
--
--  SECURITY DEFINER 的意思：
--    函式執行時以「函式擁有者(通常是 postgres)」的身分執行，
--    會繞過呼叫者(anon)的 RLS。所以能寫入 upvotes 欄位。
--    這也是為什麼一定要在函式內部做嚴格檢查(dir 值、approved=true)。
--
--  安全考量：
--    - set search_path = public 避免被人建立同名假 schema 攻擊。
--    - WHERE approved = true → 未審核的建議連 RPC 都動不到。
-- ================================================================
create or replace function public.vote_suggestion(sid bigint, dir text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 檢查 dir 參數：只接受 'up' / 'down'，其他一律拒絕。
  -- 這是白名單設計 — 就算未來有人嘗試 SQL injection 也走不通。
  if dir not in ('up', 'down') then
    raise exception 'invalid dir: %', dir;
  end if;

  -- 依方向 +1。approved = true 是關鍵 — 未審核的建議不計票。
  if dir = 'up' then
    update public.suggestions
       set upvotes = upvotes + 1
     where id = sid and approved = true;
  else
    update public.suggestions
       set downvotes = downvotes + 1
     where id = sid and approved = true;
  end if;
end;
$$;

-- 授權：只有給 anon 執行權，管理員也可以用同一支。
-- 沒有這行 anon 呼叫 rpc 會被拒絕。
grant execute on function public.vote_suggestion(bigint, text) to anon;
grant execute on function public.vote_suggestion(bigint, text) to authenticated;


-- ================================================================
--  [7] Storage bucket policies (可選 — 若你偏好用 GUI 設定就跳過)
-- ----------------------------------------------------------------
--  Bucket 本身「一定要在後台建立」，這裡只是設定 policy。
--  後台步驟：
--    Storage → New bucket → 名稱 media / Public bucket 打勾
--    File size limit: 25 MB
--    Allowed MIME types: image/*, video/*
--
--  Bucket 建好後，把下面兩條政策執行，anon 才能上傳；
--  或者你也可以在 Storage → Policies GUI 手動加。
-- ================================================================

-- 允許 anon 上傳到 media bucket(其他 bucket 不受影響)
drop policy if exists "media_anon_insert" on storage.objects;
create policy "media_anon_insert"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'media');

-- 讓所有人(含 anon)能透過 public URL 讀 media bucket
-- Public bucket 通常已有預設的 public read，若你的專案沒有再加。
drop policy if exists "media_public_select" on storage.objects;
create policy "media_public_select"
  on storage.objects
  for select
  to public
  using (bucket_id = 'media');


-- ================================================================
--  結束
--  下一步(README 有詳述)：
--    A. 後台建立 storage bucket "media"(見 [7] 上方註解)
--    B. 後台建立管理員帳號:Authentication → Users → Add user
--    C. 前端 config.js 填入 SUPABASE_URL / anon key
--    D. 推上 GitHub Pages
-- ================================================================
