# API_DESIGN.md — Phase 2以降のバックエンド設計(未実装)

現在はバックエンドなし。家族共有・OCRを入れる時に以下で実装する。
推奨: Supabase (Auth + Postgres + Storage) または Hono + SQLite。

## リソース設計(REST)

| Method | Path | 説明 |
|---|---|---|
| GET/POST | /api/inventory | 在庫一覧 / 追加 |
| PATCH/DELETE | /api/inventory/:id | 更新 / 削除 |
| GET/POST | /api/recipes | レシピ |
| GET/POST/PATCH | /api/shopping(/:id) | 買い物リスト |
| POST | /api/receipts | multipart画像 → Storage保存 |
| POST | /api/receipts/:id/ocr | OCRジョブ起動(下記) |
| GET | /api/suggest?date=... | 献立提案(ロジックはサーバー移植) |

## OCRパイプライン(Edge Functionプロキシで実装済み、2026-07-15)
実装は当初案(Claude API vision + サーバーStorage)ではなく、Gemini API + Supabase Edge Functionプロキシで完了。
1. 画像はクライアントでcanvas圧縮 → dataURL(Storage未使用、画像自体は保存しない。レシートのみ端末localStorageに保持)
2. OCR: クライアントの`callGemini(contents, generationConfig)`(index.html) → `POST {SYNC_URL}/functions/v1/gemini` → Edge Function(`supabase/functions/gemini/index.ts`)がsecret `GEMINI_API_KEY` を付与してGemini APIへ中継。レスポンスはステータス込みで透過
   出力JSON(レシート): `{items:[{name, qty, unit, price, expiryGuess, location, genre}], total}`(チラシ・レシピOCRは別スキーマ。DATA_MODEL.md参照)
3. フロントで確認・補正UI → 確定分のみ在庫/state.deals/state.recipesにINSERT
※ 「自動反映」ではなく「確認付き反映」を必ず挟む(誤読対策)方針は当初案どおり維持

## 認証・共有(Phase 3)
- Supabase Auth(メールリンク) + household_id で世帯単位共有
- 全テーブルに household_id、RLSで分離

## 公開レシピプール「みんなの定番」(Supabase, 実装済み v1.20)
実体は `supabase/recipes_pool.sql`(`public.recipes`テーブル+RLS+2つのRPC)。家族同期(household_pull/push)とは別テーブル・別RPC。すべて`syncHeaders()`の公開(publishable)キーで叩く(秘密キーは使わない)。

| 操作 | 呼び方 | 説明 |
|---|---|---|
| 一覧取得 | `GET {SYNC_URL}/rest/v1/recipes?status=eq.active&order=use_count.desc&limit=60&select=...` (headers=`syncHeaders()`) | `status='active'`のみ匿名SELECT可(RLS)。人気順(use_count降順)。失敗はthrow |
| 貢献 | `POST {SYNC_URL}/rest/v1/rpc/recipe_contribute` body `{"p":{name,cat,cuisine,time_min,ings:[{name,qty,unit}],steps:[...],source,contributor}}` | SECURITY DEFINER RPC。`name_key`(正規化キー)で重複統合し、既存なら`use_count+1`。新規ならuuidを返す。`cat`は主菜/副菜/汁物以外は主菜に、`cuisine`は和/洋/中/その他以外はその他に丸める(RPC内部で検証・CHECK制約は無し) |
| 通報 | `POST {SYNC_URL}/rest/v1/rpc/recipe_flag` body `{"p_id":"<uuid>"}` | `flags`をインクリメントし、3件到達で`status='hidden'`に自動遷移(以後一覧・提案から除外) |

- テーブルへの直接write/delete/更新は不可(anon/authenticatedからrevoke済み、RPCのみgrant)。
- クライアント側ラッパ: `poolFetchTop(limit)`/`poolContribute(recipe,source)`/`poolFlag(id)`(index.html)。`poolContribute`はベストエフォートでUIをブロックしない。
- 貢献元は`saveRecipe()`の手動新規作成のみ(`state.settings.shareMyRecipes`がtrueの場合)。レシピOCR(本・雑誌からの取り込み)は著作権配慮のため一切呼ばない。

## 特売情報(Phase 3)
1. 手動登録(現状) → 2. トクバイ等のチラシURL埋め込み →
3. スクレイピング/API(法務・規約確認必須) → 4. 提案スコアに特売ボーナス加点
