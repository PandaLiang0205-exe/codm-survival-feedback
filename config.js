// ================================================================
//  config.js — Supabase 前端連線資訊
// ----------------------------------------------------------------
//  這是「唯一」需要你填的檔案，index.html / admin.html 都會讀這裡。
//
//  ⚠️ 關於 anon key 出現在前端是不是安全的？
//    → 是的，這是設計上就允許的。anon key 就是給瀏覽器用的公開金鑰，
//      Supabase 的防線是 SETUP.sql 裡的 RLS 政策，不是靠藏 key。
//      永遠不要把 service_role key(後台看得到的另一支) 放進前端 —
//      那支是真的萬能鑰匙，一旦外洩整個資料庫任人擺布。
//
//  兩個值去哪裡拿：
//    Supabase Dashboard → Project Settings → API
//      - Project URL              → 貼到 SUPABASE_URL
//      - Project API Keys → anon  → 貼到 SUPABASE_ANON_KEY
// ================================================================

// 專案網址(結尾不要斜線)
window.SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';

// 公開的 anon key(一長串 JWT，開頭通常是 eyJ...)
window.SUPABASE_ANON_KEY = 'YOUR-ANON-KEY';
