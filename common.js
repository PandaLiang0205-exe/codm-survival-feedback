// ================================================================
//  common.js — 兩頁共用的工具
// ----------------------------------------------------------------
//  這裡放的是「index.html 與 admin.html 都會用到」的東西:
//    - Supabase client 實體(sb)
//    - 中英字典(I18N) 與語言切換(setLang / getLang / t / applyI18n)
//    - HTML 逸出(esc) 防 XSS —— 所有從 DB 讀出的字串顯示前都要過
//    - 時間戳格式化(fmtDate) —— 專門給等寬字體那欄用
//    - 媒體型別判斷(mediaKind) —— 決定用 <img> 還是 <video>
//    - 統一的媒體渲染(renderMedia)
//
//  載入順序:supabase CDN → config.js → common.js → 頁面腳本
//  這個順序很重要,createClient 需要 SUPABASE_URL / KEY 都先在 window 上。
// ================================================================


// ─── [0] Fatal error UI ──────────────────────────────────────
// 兩支 CDN 都超時的話,把訊息塞進 #main 並附「重新載入」按鈕,
// 讓使用者知道發生什麼事而不是茫然對著 Loading 或黑螢幕。
function showFatalError(msgZh, msgEn) {
  const draw = () => {
    const main = document.getElementById('main');
    if (!main) return;
    main.innerHTML = `
      <div class="fatal">
        <div class="fatal-title">⚠ ${msgZh}</div>
        <div class="fatal-title-en">${msgEn}</div>
        <button onclick="location.reload()" class="btn" style="margin-top:20px">
          重新載入 / Reload
        </button>
      </div>
    `;
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', draw);
  } else {
    draw();
  }
}


// ─── [1] Supabase client 實體(延遲初始化)─────────────────
// SDK 現在由 <head> 的 bootstrap loader 非同步載入(見兩頁 head),
// 所以 common.js 執行時 window.supabase 可能還沒好。
// 用 let 宣告 sb,等 __sdkReady 決議後再 createClient。
//
// 這樣做的重點:
//   - 所有需要 sb 的呼叫都應該掛在 window.__sdkReady 上(見 index.html
//     與 admin.html 結尾的 render() 呼叫);到那時 sb 已經賦值完成。
//   - .then 依照註冊順序執行 → common.js 這支 .then 先跑(建 client),
//     頁面腳本的 .then 後跑(呼叫 render),順序不會錯。
let sb;
window.__sdkReady
  .then(() => {
    sb = window.supabase.createClient(
      window.SUPABASE_URL,
      window.SUPABASE_ANON_KEY
    );
  })
  .catch(() => {
    // 兩支 CDN 都掛才會走到這裡。顯示 fatal error 讓使用者可以按重新載入。
    showFatalError(
      '網路資源載入失敗,請檢查連線後重新載入。',
      'Failed to load required resources. Please check your connection and reload.'
    );
  });


// ─── [2] 中英雙語字典 ───────────────────────────────────────
// 每個 key 對應 {en, zh} 兩種寫法。頁面上任何顯示文字都經過 t()。
// 為什麼不用 i18n 套件?因為只有兩種語言、幾十個 key,自幹最省。
const I18N = {
  // 頁首
  brand_home:      { en: '【生存模式回饋系統】',          zh: '【生存模式回饋系統】' },
  brand_admin:     { en: '【生存模式回饋系統】管理後台',   zh: '【生存模式回饋系統】管理後台' },
  nav_home:        { en: 'Home',                          zh: '主頁' },
  nav_admin:       { en: 'Admin',                         zh: '管理' },
  lang_toggle:     { en: '中文',                          zh: 'EN' },
  logout:          { en: 'Logout',                        zh: '登出' },

  // Tab / 按鈕
  tab_bugs:        { en: 'Bug Reports',                   zh: 'BUG 回報' },
  tab_suggestions: { en: 'Game Suggestions',              zh: '遊戲建議' },
  new_bug:         { en: '+ Report Bug',                  zh: '+ 新增回報' },
  new_suggestion:  { en: '+ Add Suggestion',              zh: '+ 新增建議' },
  back:            { en: '← Back',                        zh: '← 返回' },

  // 搜尋 / 排序
  search_placeholder: { en: 'Search keywords...',         zh: '搜尋關鍵字...' },
  sort_label:         { en: 'Sort:',                      zh: '排序:' },
  sort_newest:        { en: 'Newest first',               zh: '最新優先' },
  sort_oldest:        { en: 'Oldest first',               zh: '最舊優先' },
  sort_top:           { en: 'Most supported',             zh: '支持度最高' },
  no_match:           { en: 'No results match.',          zh: '找不到符合的項目。' },

  // 站點統計
  stats_bugs:         { en: 'BUGS',                       zh: 'BUG' },
  stats_suggestions:  { en: 'SUGG',                       zh: '建議' },
  stats_views:        { en: 'VIEWS',                      zh: '瀏覽' },

  // BUG 狀態
  filter_open:        { en: 'Unresolved',                 zh: '未解決' },
  filter_resolved:    { en: 'Resolved',                   zh: '已解決' },
  tag_resolved:       { en: 'RESOLVED',                   zh: '已解決' },
  mark_resolved:      { en: 'Mark Resolved',              zh: '標記為已解決' },
  mark_open:          { en: 'Reopen',                     zh: '取消解決' },

  // 表單
  form_new_bug:        { en: 'New Bug Report',            zh: '新增 Bug 回報' },
  form_new_suggestion: { en: 'New Suggestion',            zh: '新增建議' },
  f_title:             { en: 'Title',                     zh: '標題' },
  f_desc:              { en: 'Description',               zh: '說明' },
  f_media:             { en: 'Media (image/video, max 25MB, optional)', zh: '媒體(圖片或影片,上限 25MB,選填)' },
  submit:              { en: 'Submit',                    zh: '送出' },
  submitted:           { en: '✓ Submitted. Awaiting moderator review.', zh: '✓ 已送出,等待管理員審核。' },
  err_size:            { en: 'File exceeds 25 MB.',       zh: '檔案超過 25 MB。' },
  err_type:            { en: 'Only image / video allowed.', zh: '只允許圖片或影片。' },
  uploading:           { en: 'Uploading...',              zh: '上傳中...' },
  submitting:          { en: 'Submitting...',             zh: '送出中...' },

  // 列表 / 詳情
  loading:         { en: 'Loading...',                    zh: '載入中...' },
  empty:           { en: 'No items yet.',                 zh: '目前沒有項目。' },
  tag_bug:         { en: 'BUG',                           zh: 'BUG' },
  upvote:          { en: 'Support',                       zh: '支持' },
  downvote:        { en: 'Reject',                        zh: '不支持' },

  // Admin
  login:           { en: 'Admin Login',                   zh: '管理員登入' },
  f_email:         { en: 'Email',                         zh: '電子郵件' },
  f_password:      { en: 'Password',                      zh: '密碼' },
  do_login:        { en: 'Sign In',                       zh: '登入' },
  pending_queue:   { en: 'Pending Queue',                 zh: '待審核佇列' },
  approved_list:   { en: 'Approved Items',                zh: '已核准項目' },
  no_pending:      { en: '✓ No pending items.',           zh: '✓ 目前沒有待審核項目。' },
  no_approved:     { en: '✓ No approved items.',          zh: '✓ 目前沒有已核准項目。' },
  approve:         { en: 'Approve',                       zh: '核准' },
  reject:          { en: 'Reject',                        zh: '拒絕' },
  edit:            { en: 'Edit',                          zh: '編輯' },
  del:             { en: 'Delete',                        zh: '刪除' },
  save:            { en: 'Save',                          zh: '儲存' },
  cancel:          { en: 'Cancel',                        zh: '取消' },
  confirm_delete:  { en: 'Delete this item permanently?', zh: '確定要永久刪除這筆嗎?' },
  saved:           { en: '✓ Saved.',                      zh: '✓ 已儲存。' },
  admin_tab_pending:  { en: 'Pending',                    zh: '待審核' },
  admin_tab_approved: { en: 'Approved',                   zh: '已核准' },

  // 錯誤
  err_prefix:      { en: 'Error: ',                       zh: '錯誤:' }
};


// ─── [3] 語言存取 ───────────────────────────────────────────
// 為什麼把語言存 localStorage:換頁不會掉、重整不會回預設。
// 預設 'en' — 主題是英文遊戲,英文為預設較自然。

// 讀目前語言(找不到就給 'en')
function getLang() {
  return localStorage.getItem('lang') || 'en';
}

// 設定語言並「當場重繪」— 由頁面自己覆寫 window.rerender 決定怎麼重繪。
// 語言切換鈕會呼叫這支,不再由每個頁面各自寫一次。
function setLang(l) {
  localStorage.setItem('lang', l);
  // 換完馬上重繪頁面。每頁在啟動時把 render() 掛到 window.rerender。
  if (typeof window.rerender === 'function') window.rerender();
}

// 取字典字串;沒對到就把 key 原樣吐出來(比空字串更容易發現漏翻)
function t(key) {
  const entry = I18N[key];
  if (!entry) return key;
  return entry[getLang()] || entry.en || key;
}


// ─── [4] 掃描頁面套用 i18n 屬性 ─────────────────────────────
// 在 HTML 靜態元素上寫 data-i18n="key" 就會自動被換成翻譯。
// data-i18n-placeholder="key" 則會塞到 input.placeholder。
// 頁面裡由 JS 生的內容通常直接用 t(),不靠這個掃描。
function applyI18n() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    el.textContent = t(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  // 順便更新 <html lang> 讓瀏覽器 / 螢幕閱讀器知道語言
  document.documentElement.lang = getLang() === 'zh' ? 'zh-Hant' : 'en';
}


// ─── [5] 綁定共用元件:語言切換鈕 / 登入時的 logout 鈕 ──────
// 兩頁的 header 都有 #lang-toggle,寫在共用檔省掉重複。
// 頁面載入完再綁定,避免 DOM 還沒生出來就找不到元素。
document.addEventListener('DOMContentLoaded', () => {
  const langBtn = document.getElementById('lang-toggle');
  if (langBtn) {
    langBtn.addEventListener('click', () => {
      // 兩種語言互切
      setLang(getLang() === 'en' ? 'zh' : 'en');
    });
  }
});


// ─── [6] 時間戳格式化 ─────────────────────────────────────
// 為什麼自幹而不用 toLocaleString?
//   - 想要固定格式 YYYY-MM-DD HH:mm,配等寬字體才對齊。
//   - toLocaleString 各瀏覽器輸出不一,對齊排版很難看。
function fmtDate(iso) {
  const d = new Date(iso);
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
         `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}


// ─── [7] HTML 逸出 ────────────────────────────────────────
// 所有從資料庫拿出來的字串,顯示到頁面前一律過這個函式。
// 不然使用者輸入 <script>alert(1)</script> 進 title,顯示時就會執行 —— 這是 XSS。
// 這裡把五個關鍵字元轉成 HTML entity,瀏覽器看到就會當文字顯示。
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[c]));
}


// ─── [8] 判斷媒體是圖片還是影片 ───────────────────────────
// 用副檔名(而非 MIME)判斷,因為公開 URL 拿不到 MIME header。
// 常見影片格式全部列出;沒對到就當圖片處理(圖片格式太多不逐一列)。
function mediaKind(url) {
  // .split('?')[0] 去掉 querystring,再取最後一段的副檔名
  const clean = url.split('?')[0].split('#')[0];
  const ext = clean.split('.').pop().toLowerCase();
  return ['mp4', 'webm', 'mov', 'm4v', 'ogg', 'ogv'].includes(ext) ? 'video' : 'image';
}


// ─── [9] 統一媒體渲染 ─────────────────────────────────────
// 詳情頁跟管理頁都要顯示媒體,共用一份。
// controls 屬性讓影片有播放列;圖片 loading="lazy" 減少頻寬。
function renderMedia(url) {
  if (mediaKind(url) === 'video') {
    return `<video controls preload="metadata" class="media" src="${esc(url)}"></video>`;
  }
  return `<img class="media" loading="lazy" src="${esc(url)}" alt="">`;
}
