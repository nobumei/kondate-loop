# CLAUDE.md — Claude Code用の永続ルール

AGENTS.md を先に読むこと。以下はClaude Code固有の補足。

## セッション開始時
1. `docs/TODO.md` を読み、着手タスクを1つ宣言する
2. `docs/DATA_MODEL.md` でスキーマを確認する

## セッション終了時
1. `docs/TODO.md` を更新(完了チェック・新規発見タスク追記)
2. 大きな設計判断をしたら `docs/ARCHITECTURE.md` の「設計判断ログ」に1行追記

## 禁止事項
- localStorageキー名 `kondate-loop-v1` の変更(マイグレーション無しでの変更)
- index.html の単一ファイル構成の分割(Phase 2判断まで)
- ユーザー確認なしの全データ削除系コードの追加

## テスト
ブラウザで index.html を開き、docs/TEST_PLAN.md のスモークテスト(5分)を実行。
