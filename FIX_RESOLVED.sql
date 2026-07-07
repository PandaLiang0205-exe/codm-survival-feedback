-- ================================================================
--  補丁:bugs 表新增 resolved 欄位
-- ----------------------------------------------------------------
--  用途:
--    - 管理員可將某筆 BUG 標記為「已解決」
--    - 主頁 BUG 分頁預設只顯示未解決,可切換到「已解決」檢視
--
--  為什麼是 boolean 而不是 status enum:
--    - 目前只有 open / resolved 兩態,boolean 最省
--    - 未來若加 in_progress / wontfix,再換成 enum 也容易
--
--  RLS 影響:
--    - 不用改 policy:
--      * anon SELECT 靠 approved=true(resolved 都能讀 → 前端自己切)
--      * authenticated UPDATE 已允許改任意欄位(bugs_auth_update)
-- ================================================================

alter table public.bugs
  add column if not exists resolved boolean not null default false;


-- ── 驗證 ─────────────────────────────────────
-- 應該看到 resolved 欄位存在、型別 boolean、預設 false
select column_name, data_type, column_default, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'bugs'
  and column_name  = 'resolved';
