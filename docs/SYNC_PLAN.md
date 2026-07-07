# SYNC_PLAN.md — 家族共有(Supabase同期)実装指示書

> 置き場所: `docs/SYNC_PLAN.md`
> 実行者: Claude Code。着手前に AGENTS.md / CLAUDE.md / docs/DATA_MODEL.md を読むこと。
> 完了したら docs/TODO.md の「家族共有」に [x] を付け、DATA_MODEL.md にスキーマ変更を追記する。

## 目的
家族の複数端末(スマホ/PC)で在庫・献立・買い物リストを同期する。
認証は導入しない。共有の「あいことば(household ID)」方式で最小実装する。

## 事前準備(人間の作業・Claude Codeは待つ)
1. https://supabase.com で無料プロジェクト作成
2. SQL Editor で以下を実行:

```sql
create table households (
  id text primary key,
  data jsonb not null,
  updated_at timestamptz not null default now()
);
alter table households enable row level security;
create policy "anon rw" on households for all
  to anon using (true) with check (true);
```

3. Settings > API から `Project URL` と `anon key` を控える

## セキュリティ上のトレードオフ(明記すること)
- anon keyは公開リポジトリに含まれる。household IDを知る者は誰でも読み書き可能。
- 対策: household IDは推測困難な文字列にする(UI側で `crypto.randomUUID()` による生成ボタンを用意)。
- 扱うのは献立・在庫データのみで機微情報ではないため、家族用途では許容と判断。
- 本格運用に進む場合は Supabase Auth + RLS(household_id紐付け)へ移行(API_DESIGN.md Phase 3)。

## 実装仕様

### 1. 設定タブに「家族で同期」セクションを追加
- 入力欄: Supabase URL / anon key / あいことば(household ID)
- ボタン: 「あいことばを生成」「同期を開始」「同期を解除」
- 同期状態インジケータ: 🟢同期中 / 🟡送信待ち / 🔴エラー / ⚪未設定
- これらの接続情報は state とは別の localStorage キー `kondate-loop-sync` に保存
  (エクスポートJSONに接続情報を含めないため)

### 2. 同期エンジン(index.html内、/* ==== 同期 ==== */ セクション)
- 通信は fetch + Supabase REST (`/rest/v1/households`)。SDKは導入しない(ゼロ依存維持)。
- **pull**: 起動時 / `visibilitychange`(復帰時) / 同期開始時
  - `GET ?id=eq.{hid}&select=data,updated_at`
  - remote.updated_at > local最終同期時刻 なら remote.data を採用して renderAll()
- **push**: save() の後段にフック。2秒デバウンス
  - `PATCH ?id=eq.{hid}` で `{data: state, updated_at: now()}`
  - 行が無ければ `POST`(初回)
- **競合方針**: whole-blob の last-write-wins。push前に必ずpullして新しいremoteを取り込んでから送る。
  同時編集で片方の直近変更が消える可能性がある旨を README に明記。
- **除外**: `state.receipts` と `state.ui` は同期対象から外す(画像はjsonb肥大の原因。送信前にstripする)。
- オフライン時: pushをキューせず、次のsave/復帰時に再試行。エラーは🔴+toastで通知。

### 3. スキーマ影響
- AppState 本体は不変(v1のまま)。同期はレイヤーとして被せる。
- DATA_MODEL.md に `kondate-loop-sync` キーの構造を追記:
  `{ url: string, anonKey: string, householdId: string, lastSyncedAt: string }`

### 4. テスト追加(TEST_PLAN.mdに追記)
1. 端末A: あいことば生成→同期開始→在庫追加 → 端末B: 同じあいことば入力→在庫が現れる
2. 端末Bで買い物チェック → 端末Aをバックグラウンド→復帰 → 反映されている
3. 機内モードで在庫追加 → 🔴表示 → 復帰後にsave操作で送信される
4. 同期解除 → ローカルデータは残る/通信が発生しない
5. エクスポートJSONに url/anonKey/householdId が含まれていないこと

## 実装順序(1コミットずつ)
1. 設定UI + `kondate-loop-sync` の保存
2. pull(読み取りのみ)で表示確認
3. push(デバウンス+pull-before-push)
4. インジケータ・エラー処理
5. ドキュメント3点更新(DATA_MODEL / TEST_PLAN / README)
