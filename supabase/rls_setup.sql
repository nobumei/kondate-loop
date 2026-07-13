-- kondate-loop 家族同期テーブルのセキュリティ設定(RLS + RPC)
-- 実行環境: Supabase ダッシュボード → SQL Editor に貼り付けて Run
-- 目的: publishable(anon)キーからの「全行読み取り・他人行の改ざん/削除・任意INSERT」を遮断し、
--       あいことば(id)を知っている人だけが自分の1行だけを読み書きできるようにする。
--
-- 注意: このSQLを実行すると、旧バージョンのindex.html(テーブルに直接アクセスしていた版)からの
--       同期は動かなくなります。RPC対応版のindex.htmlとセットで使ってください。

-- 1) テーブルへの直接アクセスを全遮断
alter table public.households enable row level security;
revoke all on public.households from anon, authenticated;

-- 2) あいことば(id)の1行だけを読むRPC
create or replace function public.household_pull(p_id text)
returns table(data jsonb, updated_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select h.data, h.updated_at from public.households h where h.id = p_id;
$$;

-- 3) あいことば(id)の1行だけを作成/更新するRPC(サーバ側で updated_at を確定)
create or replace function public.household_push(p_id text, p_data jsonb)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare ts timestamptz := now();
begin
  insert into public.households(id, data, updated_at)
  values (p_id, p_data, ts)
  on conflict (id) do update set data = excluded.data, updated_at = ts;
  return ts;
end;
$$;

-- 4) 匿名からはこの2つのRPCだけ実行可(テーブルには触れない)
revoke all on function public.household_pull(text)        from public;
revoke all on function public.household_push(text, jsonb) from public;
grant execute on function public.household_pull(text)        to anon;
grant execute on function public.household_push(text, jsonb) to anon;

-- 補足: これでも「あいことばを知る人はその世帯を読み書きできる」設計は維持されます
-- (家族で共有する前提のため)。あいことばは推測されにくい長い文字列にしてください。
-- さらに強くしたい場合は household_push に秘密トークン引数を追加し、一致時のみ書き込む方式に拡張できます。
