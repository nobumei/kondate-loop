-- kondate-loop 公開レシピDB(全ユーザー共通プール)。Supabase SQL Editor に貼って Run。
-- 直接アクセスは全面禁止(RLS)。読み取りは status='active' のみ匿名可。書き込みは検証付きRPC経由のみ。
-- ※ CHECK制約は付けない(貼り付け事故を避けるため)。値の検証はRPC側で行う。

create table if not exists public.recipes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  name_key    text not null unique,
  cat         text not null default '主菜',
  cuisine     text not null default 'その他',
  time_min    int  not null default 20,
  ings        jsonb not null default '[]'::jsonb,
  steps       jsonb not null default '[]'::jsonb,
  source      text not null default 'ai',
  contributor text,
  use_count   int  not null default 1,
  flags       int  not null default 0,
  status      text not null default 'active',
  created_at  timestamptz not null default now()
);
create index if not exists recipes_active_pop on public.recipes (status, use_count desc);

-- 正規化キー(重複統合用): 小文字化 + 空白除去
create or replace function public.norm_key(p_name text)
returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(p_name, '')), '\s|　', '', 'g');
$$;

alter table public.recipes enable row level security;
revoke all on public.recipes from anon, authenticated;
drop policy if exists recipes_read_active on public.recipes;
create policy recipes_read_active on public.recipes for select to anon using (status = 'active');
grant select on public.recipes to anon;

-- 貢献RPC: 検証 + 重複統合(name_keyで一意、既存なら use_count+1)
create or replace function public.recipe_contribute(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; nk text; nm text; c text; cu text;
begin
  nm := coalesce(p->>'name', '');
  nk := public.norm_key(nm);
  if char_length(nm) = 0 or char_length(nk) = 0 then raise exception 'invalid_name'; end if;
  if jsonb_typeof(p->'ings') <> 'array' or jsonb_typeof(p->'steps') <> 'array' then
    raise exception 'invalid_body'; end if;
  c  := case when p->>'cat' in ('主菜','副菜','汁物') then p->>'cat' else '主菜' end;
  cu := case when p->>'cuisine' in ('和','洋','中','その他') then p->>'cuisine' else 'その他' end;
  insert into public.recipes(name, name_key, cat, cuisine, time_min, ings, steps, source, contributor, status)
  values (left(nm,80), nk, c, cu,
          least(greatest(coalesce((p->>'time_min')::int, 20), 1), 999),
          p->'ings', p->'steps',
          case when p->>'source' = 'user' then 'user' else 'ai' end,
          nullif(left(coalesce(p->>'contributor',''), 40), ''), 'active')
  on conflict (name_key) do update set use_count = public.recipes.use_count + 1
  returning id into nid;
  return nid;
end; $$;

-- 通報RPC: フラグ加算、3件で自動非表示
create or replace function public.recipe_flag(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.recipes
     set flags = flags + 1,
         status = case when flags + 1 >= 3 then 'hidden' else status end
   where id = p_id and status = 'active';
end; $$;

revoke all on function public.recipe_contribute(jsonb) from public;
revoke all on function public.recipe_flag(uuid)        from public;
grant execute on function public.recipe_contribute(jsonb) to anon;
grant execute on function public.recipe_flag(uuid)        to anon;
