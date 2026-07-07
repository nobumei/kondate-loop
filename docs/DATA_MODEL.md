# DATA_MODEL.md — localStorage `kondate-loop-v1` (schema v1)

```typescript
interface AppState {
  inventory: InventoryItem[];
  recipes: Recipe[];
  shopping: ShoppingItem[];
  receipts: Receipt[];
  settings: Settings;
  current: string[] | null;   // 提案中の献立 recipe.id 配列
  ui: { locFilter: 'all'|'冷蔵'|'冷凍'|'常温'; favOnly: boolean };
}

interface InventoryItem {
  id: string;            // uid()
  name: string;
  qty: number;
  unit: string;          // 個/g/袋/本...
  location: '冷蔵'|'冷凍'|'常温';
  expiry: string | null; // 'YYYY-MM-DD'
  addedAt: string;       // 'YYYY-MM-DD'
  memo: string;
}

interface Recipe {
  id: string;            // seed0..seed17 は初期データ
  name: string;
  cat: '主菜'|'副菜'|'汁物';
  time: number;          // 分
  ings: { name: string; qty: number|null; unit: string }[];
  favorite: boolean;
  freqDays: number;      // 食べたい間隔(日): 3/7/14/30/90/180/365 (v1.3)
  rating: 0|1|2|3|4|5;   // 家族の評価
  memo: string;
  steps: string[];       // 作り方(v1.2で追加。タップで表示)
  lastCooked: string | null; // 'YYYY-MM-DD'
  seed: boolean;         // trueなら削除ボタン非表示
}

// v1.2: まとめ献立と仕込み
// state.plan: { createdAt: string, days: {offset:number, ids:string[]}[], prepDone: Record<string,boolean> } | null
// 仕込みタスクは PREP 辞書(食材名→下処理)から動的生成。offset<=1のみ→冷蔵 / >=2を含む→冷凍案内。

interface ShoppingItem {
  id: string; name: string; qty: number; unit: string;
  menu: string;          // 対応する献立名(表示用)
  checked: boolean; memo: string;
}

interface Receipt {
  id: string;
  dataUrl: string;       // jpeg(最大幅900px, quality 0.72)
  addedAt: string;
}

interface Settings {
  shoppingDays: number[];   // 0=日..6=土
  shoppingLog: string[];    // 買い物した日付の配列
  stores: { name: string; url: string; memo: string }[];
}
```

## 同期設定キー `kondate-loop-sync` (v1.1で追加)

```typescript
interface SyncConfig {
  enabled: boolean;
  householdId: string;      // 家族共有の「あいことば」。8文字以上、UUID生成推奨
  lastSyncedAt: string | null; // 最後に取り込んだ/送信した updated_at (ISO)
}
```

- Supabase の Project URL と publishable key は index.html に定数として埋め込み(公開前提のキー)。
- 同期対象は AppState から `receipts` と `ui` を除いたもの(stripForSync)。
- 競合は whole-blob の last-write-wins。push前に pull-before-push で新しいremoteを取り込む。
- エクスポートJSONには SyncConfig を含めない(別キーのため自然に分離される)。

## マイグレーションルール
- スキーマ変更時は `load()` 内で旧→新変換し、この表に追記する。

| version | 変更 | 日付 |
|---|---|---|
| v1 | 初版 | 2026-07-07 |
| v1.1 | 家族同期レイヤー追加(AppState自体は不変、`kondate-loop-sync` キー新設) | 2026-07-07 |
| v1.2 | Recipe.steps追加 / state.plan(まとめ献立+仕込み)追加 / 調理フィードバック | 2026-07-07 |
| v1.3 | freq(3値)→freqDays(間隔日数)へ移行。load()/applyRemote()のmigrate()で自動変換 | 2026-07-07 |

## 在庫マッチングの仕様
`inStock(ingName)`: 部分一致(`includes`)を双方向で判定。
「鶏もも肉」の在庫は材料「鶏もも肉」にも「鶏もも」にもヒットする。
誤ヒット例が増えたら正規化辞書の導入を検討(TODO参照)。
