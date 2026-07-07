-- ================================================================
--  補丁：新增 unvote_suggestion RPC 支援「收回投票 / 切換方向」
-- ----------------------------------------------------------------
--  為什麼需要這支：
--    現有 vote_suggestion 只做 +1；使用者要收回或換方向時，
--    前端需要能對 upvotes / downvotes 做 -1。
--    但 anon 不能直接 UPDATE(RLS 只允許 authenticated update)，
--    也不能給欄位級權限，所以走跟 vote_suggestion 一樣的
--    SECURITY DEFINER RPC 模式。
--
--  安全保護：
--    - 白名單 dir(只接受 'up' / 'down')
--    - WHERE approved = true：未審核的建議不能被減分
--    - greatest(x - 1, 0)：不允許票數變成負數(防止手動竄改
--      localStorage 拼命呼叫 unvote 把票數打到負)
-- ================================================================

create or replace function public.unvote_suggestion(sid bigint, dir text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if dir not in ('up', 'down') then
    raise exception 'invalid dir: %', dir;
  end if;

  if dir = 'up' then
    update public.suggestions
       set upvotes = greatest(upvotes - 1, 0)
     where id = sid and approved = true;
  else
    update public.suggestions
       set downvotes = greatest(downvotes - 1, 0)
     where id = sid and approved = true;
  end if;
end;
$$;


-- 授權：anon 與 authenticated 都可執行(跟 vote_suggestion 對稱)
grant execute on function public.unvote_suggestion(bigint, text) to anon;
grant execute on function public.unvote_suggestion(bigint, text) to authenticated;


-- 驗證：跑完應該看得到 unvote_suggestion 是 DEFINER
select
  routine_name,
  security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('vote_suggestion', 'unvote_suggestion');
