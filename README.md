# CoDM Survival Feedback Board

Call of Duty Mobile「生存模式」意見板 — 純靜態 + Supabase 後端，部署在 GitHub Pages。

- **前端**：HTML + 原生 JS + Supabase JS SDK（CDN 引入），無框架、無建置工具
- **後端**：Supabase（PostgreSQL + RLS + Storage + Auth）
- **雙語**：中英文切換（存 localStorage）
- **設計**：CoD 戰術 HUD 風（近黑背景、signal-amber 強調、bug 紅標籤）

---

## 檔案結構

```
codm-feedback/
├─ SETUP.sql        Supabase 一鍵建置腳本（表、RLS、RPC）
├─ config.js        SUPABASE_URL 與 anon key（唯一需要填的檔案）
├─ common.js        兩頁共用 JS（i18n、sb client、helpers）
├─ style.css        全部樣式
├─ index.html       主頁（列表 / 詳情 / 提交表單）
├─ admin.html       管理員頁（登入 / 待審核佇列）
└─ README.md        本檔
```

---

## 部署流程總覽

1. Supabase 後台跑 `SETUP.sql`
2. Supabase 後台建立 Storage bucket `media`
3. Supabase 後台建立管理員帳號
4. 填 `config.js`
5. 推到 GitHub → 開 GitHub Pages
6. 依「驗收清單」逐項測試

---

## 一、Supabase 後端建置

### 1-1. 執行 SETUP.sql

到 Supabase Dashboard → **SQL Editor** → New Query → 貼上整個 `SETUP.sql` 內容 → 點 **Run**。

跑完會建立：
- `bugs` 資料表
- `suggestions` 資料表
- 兩張表的 RLS 政策（`anon` 只讀 approved、可 INSERT 待審；`authenticated` 全權）
- RPC 函式 `vote_suggestion(sid, dir)`（`anon` 可執行，安全地 +1 票數）
- 兩條 Storage policy（給 media bucket，可選）

### 1-2. 建立 Storage bucket「media」

**這一步必須在後台 GUI 手動做**（SQL 建 bucket 有些限制）：

1. Supabase Dashboard → **Storage** → **New bucket**
2. Name：`media`
3. **Public bucket**：✅ 打勾（訪客要看到圖片影片必須公開）
4. **File size limit**：`25 MB`
5. **Allowed MIME types**：`image/*, video/*`
6. Save

如果 `SETUP.sql` 底部那兩條 storage policy 你不想跑，也可以在 bucket 建好後：
- Storage → 點 media bucket → **Policies** → New policy
  - 一條：`INSERT` for `anon`（with check：`bucket_id = 'media'`）
  - 一條：`SELECT` for `public`（using：`bucket_id = 'media'`）

Public bucket 通常會自帶 public read policy，若已有就跳過第二條。

### 1-3. 建立管理員帳號

Supabase Dashboard → **Authentication** → **Users** → **Add user** → **Create new user**
- Email：你要用的管理員 email
- Password：設個強密碼
- **Auto Confirm User**：✅ 打勾（不然要收信驗證）
- Create user

之後就是這組 email + password 登入 `admin.html`。

如果要多位管理員，重複這步驟。所有 authenticated 用戶都享有相同權限（RLS 沒分角色）。

---

## 二、前端設定

### 2-1. 填 `config.js`

Supabase Dashboard → **Project Settings** → **API**

- `Project URL` → 貼到 `SUPABASE_URL`
- `Project API Keys` → `anon` `public` → 貼到 `SUPABASE_ANON_KEY`

```js
window.SUPABASE_URL = 'https://xxxxxxxx.supabase.co';
window.SUPABASE_ANON_KEY = 'eyJ...你的 anon key';
```

> **anon key 出現在前端是安全的**。它就是設計來給瀏覽器用的公開金鑰，防線靠 RLS。**千萬不要**把 `service_role` key 放進前端 —— 那支是萬能鑰匙。

### 2-2. 本機測試（選用）

因為引用了 CDN 與跨源，直接雙擊 `index.html` 有些瀏覽器會擋。用最簡單的 http server：

```powershell
# 在專案資料夾內
python -m http.server 8080
# 開 http://localhost:8080
```

---

## 三、部署到 GitHub Pages

### 3-1. 建立 GitHub 倉庫並推送

```powershell
cd C:\Users\alber\Desktop\codm-feedback
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/codm-feedback.git
git push -u origin main
```

### 3-2. 開啟 GitHub Pages

1. GitHub 倉庫 → **Settings** → **Pages**
2. **Source**：`Deploy from a branch`
3. **Branch**：`main` / `/ (root)`
4. Save
5. 等 1–2 分鐘，頁面會顯示網址：`https://YOUR_USERNAME.github.io/codm-feedback/`

### 3-3. Supabase 端無需額外設定

Supabase 預設允許所有來源，GitHub Pages 網址不用列白名單。

---

## 四、驗收清單（依序測試）

| # | 項目 | 怎麼驗 |
|---|------|-------|
| 1 | 訪客只讀得到 approved=true | 無痕視窗開主頁，主頁不會出現任何 approved=false 的資料 |
| 2 | 訪客送出即待審核 | 送出後畫面顯示「已送出，等待管理員審核」；回主頁不會出現該筆 |
| 3 | 訪客不能 UPDATE / DELETE | DevTools Console 執行 `await sb.from('bugs').delete().eq('id',1)` → 回傳 error 或空受影響列 |
| 4 | 未登入的 admin 只看得到登入表單 | 無痕開 `admin.html` → 只有 login form |
| 5 | 登入後核准 → 主頁出現 | 登入 admin → 點某筆 Approve → 開主頁 → 該筆出現 |
| 6 | 拒絕 → DB 刪除 | 點 Reject → Supabase Table Editor 查該筆已不存在 |
| 7 | 投票 +1 且只能對 approved | 建議卡點 ▲ → 票數 +1；對未審核 id 呼叫 RPC → 票數不變 |
| 8 | 投一次後鈕鎖定、重整仍鎖 | 投票 → 兩鈕 disabled → F5 仍 disabled |
| 9 | 上傳 >25MB 或非 image/video 被擋 | 選 30MB 的 zip → 前端立刻報錯，不上傳 |
| 10 | 語言切換 | 點語言鈕 → 全頁翻譯 → 換頁 → 語言保留 |

---

## 五、常見問題

**Q：送出時看到「new row violates row-level security policy」**
A：多半是 SETUP.sql 沒跑完，或 `anon insert` policy 沒建立。回 SQL Editor 重跑一次。

**Q：上傳檔案報「new row violates row-level security policy」對 storage.objects**
A：Storage bucket policy 沒設。回到「1-2. 建立 Storage bucket」最後那段，補上 `anon INSERT` policy。

**Q：admin 登入後看不到待審核**
A：確認你是用 `authenticated` role（用建立好的 email/密碼登入）。可到 Console：
```js
(await sb.auth.getSession()).data.session
```
應該要回一個 session 物件，不是 null。

**Q：投票鈕點了但票數不動**
A：確認 SETUP.sql 底部的 `grant execute on function vote_suggestion(...) to anon` 有跑。Supabase Dashboard → Database → Functions 可以看到那支函式。

**Q：想清空「投過票」的本地紀錄重測**
A：DevTools Console：
```js
Object.keys(localStorage).filter(k => k.startsWith('voted_')).forEach(k => localStorage.removeItem(k))
```

---

## 六、資料表 schema（快速參照）

```
bugs
  id           bigint       主鍵
  title        text         必填
  description  text         必填
  media_url    text         可空（Storage public URL）
  created_at   timestamptz  預設 now()
  approved     boolean      預設 false

suggestions
  id           bigint       主鍵
  title        text         必填
  description  text         必填
  media_url    text         可空
  created_at   timestamptz  預設 now()
  approved     boolean      預設 false
  upvotes      integer      預設 0
  downvotes    integer      預設 0
```

---

## 七、RLS 政策速查

| Role          | bugs / suggestions              | 動作 |
|---------------|--------------------------------|------|
| anon          | SELECT WHERE approved = true    | 只讀已審核 |
| anon          | INSERT WHERE approved = false   | 只能送待審 |
| authenticated | SELECT ALL                       | 讀全部（含待審） |
| authenticated | UPDATE / DELETE                  | 核准 / 拒絕 |
| anon          | vote_suggestion RPC              | +1 票（僅 approved 列） |
