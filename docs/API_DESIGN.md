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

## OCRパイプライン(Phase 2)
1. 画像アップロード → Storage
2. OCR: Claude API (vision) にレシート画像 + 抽出プロンプト
   出力JSON: `{items:[{name, qty, unit, price, expiryGuess}]}`
3. フロントで確認・補正UI → 確定分のみ在庫にINSERT
※ 「自動反映」ではなく「確認付き反映」を必ず挟む(誤読対策)

## 認証・共有(Phase 3)
- Supabase Auth(メールリンク) + household_id で世帯単位共有
- 全テーブルに household_id、RLSで分離

## 特売情報(Phase 3)
1. 手動登録(現状) → 2. トクバイ等のチラシURL埋め込み →
3. スクレイピング/API(法務・規約確認必須) → 4. 提案スコアに特売ボーナス加点
