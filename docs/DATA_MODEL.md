# DATA_MODEL.md — localStorage `kondate-loop-v1` (schema v1)

```typescript
interface AppState {
  inventory: InventoryItem[];
  recipes: Recipe[];
  shopping: ShoppingItem[];
  receipts: Receipt[];
  deals: Deal[];               // v1.8: チラシOCRで取り込んだ特売情報
  settings: Settings;
  current: string[] | null;   // 提案中の献立 recipe.id 配列
  plan: Plan | null;
  history: HistoryEntry[];    // v1.6: 献立カレンダー用の調理履歴
  ui: { locFilter: 'all'|'冷蔵'|'冷凍'|'常温'; favOnly: boolean };
}

// v1.8: チラシOCR(Gemini)で抽出した特売食材。チラシ画像自体は保存しない(抽出結果のみ)
interface Deal {
  id: string;
  name: string;
  price: number | null;
  unit: string | null;
  validUntil: string | null;   // 'YYYY-MM-DD'。過ぎたものは表示・スコア加点から除外(データは残る)
  addedAt: string;             // 'YYYY-MM-DD'
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
// v1.11: レシピOCR(Gemini)で本・Kindle・雑誌等の画像から抽出したレシピもseed:falseの通常レシピとしてstate.recipesに追加される(スキーマ変更なし)。家族同期対象・削除ボタンあり。抽出結果は確認モーダルでの編集を経てからのみ追加され、画像自体は保存しない

// v1.2: まとめ献立と仕込み(v1.6でdays構造を拡張)
interface Plan {
  createdAt: string;
  days: { offset: number; meals: Partial<Record<'朝'|'昼'|'夜', string[]>> }[];  // v1.6: 食事ごとのrecipe.id配列
  prepDone: Record<string, boolean>;
}
// 仕込みタスクは PREP 辞書(食材名→下処理)から動的生成。offset<=1のみ→冷蔵 / >=2を含む→冷凍案内。
// v1.6: 複数日にまたがる食材は「事前準備」の集約行(合計量+使い先内訳、offset>=2は冷凍案内)を生成する(buildPrepTasks()のt.summary)。
// v1.6: まとめ提案UIで「何日分(1〜7)」「朝/昼/夜(既定は夜のみ)」を選択できる。朝・昼は汁物+主菜1品の軽量構成で、時間の短いレシピを優先するスコアリング(scoreRecipeのlightフラグ)。

interface HistoryEntry {           // v1.6: 献立カレンダー用の調理履歴
  date: string;                    // 'YYYY-MM-DD'
  meal: '朝'|'昼'|'夜';             // markCooked()/feedbackDish()からの記録は既定で'夜'
  ids: string[];                   // recipe.id配列。削除済みレシピは表示側で「(削除済み)」扱い
}

interface ShoppingItem {
  id: string; name: string; qty: number; unit: string;
  menu: string;          // 対応する献立名(表示用)
  checked: boolean; memo: string;
}

interface Receipt {
  id: string;
  dataUrl: string;       // jpeg(最大幅900px, quality 0.72)
  addedAt: string;
  items?: { name: string; qty: number; unit: string; price: number|null; genre: string }[]; // v1.8: OCR確認モーダルで「在庫に追加」実行時に全抽出品目(チェック有無問わず)を保存。集計専用
  total?: number | null;  // v1.8: レシート合計金額(OCRの推定値。読み取れなければnull)
}
// items/totalは「🔍読み取り」→確認モーダル→「在庫に追加」を実行したレシートにのみ付与される。
// 未実行・旧形式のレシートはitemsを持たないため集計(📊)の対象外。
// 集計(📊)は端末内のレシートのみを対象にする(レシートはstripForSyncで同期対象外のため、家族の他端末のレシートは合算できない)。

interface Settings {
  shoppingDays: number[];   // 0=日..6=土
  shoppingLog: string[];    // v1.10で非推奨: 設定タブの「買い物記録」UIを削除したためもう書き込まれない。既存データ・エクスポート/インポート・migrateとの互換のためフィールド自体とdefaultStateの初期化は残す
  stores: { name: string; url: string; memo: string }[];
  normDict: Record<string,string>;  // v1.5: 食材名の正規化辞書(別名→正規名)。ユーザー登録分のみ。家族同期対象
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

## レシートOCR設定キー `kondate-loop-gemini` (v1.4で追加)

```typescript
// localStorage.getItem('kondate-loop-gemini') は文字列そのもの(Gemini APIキー)。JSON化しない。
```

- 値は Gemini APIキーの生文字列(空なら未設定)。設定タブの「レシートOCR(Gemini)」から保存/削除する。
- `kondate-loop-sync` と同様に端末ローカル専用: 家族同期(stripForSync)対象外、エクスポートJSON(state由来)にも含まれない(別キーのため自然に分離される)。
- OCR抽出結果は一時的な `ocrItems`(メモリ内のみ)を経由し、確認モーダルでチェックした品だけが `state.inventory` に追加される。抽出結果自体はlocalStorageに保存しない。

## チュートリアル既読フラグ `kondate-loop-tutorial-seen` (v1.5で追加)

- 値は `'1'`(文字列)固定。存在すれば既読、未設定なら初回起動とみなして使い方モーダルを自動表示する。
- 端末ローカル専用: `kondate-loop-v1` とは別キーのため、家族同期・エクスポートJSONの対象外。

## 食材名の正規化辞書 (v1.5で追加、v1.12で拡充)

- 組み込み辞書 `BUILTIN_NORM_DICT`(コード内定数、128組・63食材、v1.12でひらがな正規化方針に全面拡充)と、ユーザー登録分 `state.settings.normDict` の2層構成。UI表記は「食材辞書」(v1.12でUI文言のみ「食材名の辞書」から変更。関数名・localStorageキーは不変)。
- `normalizeName(s)`: trim → 組み込み辞書 → ユーザー辞書、の順に適用して正規名を返す。
- v1.12方針: **ひらがなを正規名(canonical)とする**(例: 玉ねぎ/タマネギ/玉葱 → 「たまねぎ」)。卵・豆腐など漢字表記が一般的な食材や、鶏もも肉など肉類は無理にひらがな化せず自然な表記を正規名にする。同音異義・多義語(さけ=酒/鮭、もも=桃/鶏もも 等)は誤マッチ防止のため収録しない。別食材(ミニトマト/トマト、ねぎ/玉ねぎ、しょうが/みょうが 等)は混同しない。
- `inStock()` は両辺(在庫名・材料名)を `normalizeName()` してから部分一致判定する。保存済みデータ自体は書き換えない(非破壊)。既存データが漢字で保存済みでも、両辺とも正規化されるためマッチングは壊れない。
- レシートOCR結果(`openOcrModal`)の食材名にも初期値として適用する(モーダル上で編集可能)。
- ユーザー登録分は `state.settings.normDict` に載るため、家族同期・エクスポートJSONの対象に含まれる。

## 在庫チップの手動補正 (v1.6で追加)
- 提案画面(単発・まとめ両方)の材料は `effectiveHas(name)` で表示する。`inStock()` の結果をグローバル変数 `stockOverride`(`Map`、正規化名→boolean)で上書きできる、提案セッション中のみの一時的な補正。
- `toggleStockChip(name)` でチップをタップすると◯⇄✗がトグルされる。`stockOverride` は `state` に含まれず保存されない(リロードで消える)。
- `missingIngs()`(買い物リスト生成の元)は `effectiveHas()` を経由するため、手動補正が「まとめ買いリストへ」「足りない食材を買い物リストへ」に反映される。`scoreRecipe()` の採点(実在庫のみ)には影響しない。

## 献立提案への要望反映・調理モード (v1.7で追加。AppStateスキーマ変更なし)
- 提案画面(単発・まとめ)の「要望」入力(音声/テキスト)とAIの提案理由は、在庫チップの手動補正(`stockOverride`, v1.6)と同様にグローバル変数(`suggestReason`/`planReason`)で保持するセッション内のみの一時値。`state`には含まれず、保存もされない(リロードで消える)。
- 調理モードの現在レシピ・工程番号は `cookState`(グローバル変数、非永続)で管理し、`state`やAppStateスキーマには一切影響しない。

## マイグレーションルール
- スキーマ変更時は `load()` 内で旧→新変換し、この表に追記する。

| version | 変更 | 日付 |
|---|---|---|
| v1 | 初版 | 2026-07-07 |
| v1.1 | 家族同期レイヤー追加(AppState自体は不変、`kondate-loop-sync` キー新設) | 2026-07-07 |
| v1.2 | Recipe.steps追加 / state.plan(まとめ献立+仕込み)追加 / 調理フィードバック | 2026-07-07 |
| v1.3 | freq(3値)→freqDays(間隔日数)へ移行。load()/applyRemote()のmigrate()で自動変換 | 2026-07-07 |
| v1.4 | レシートOCR(Gemini)追加。`kondate-loop-gemini`キー新設(AppState自体は不変) | 2026-07-07 |
| v1.5 | Settings.normDict追加(食材名の正規化辞書。migrate()で既存データに補完)。`kondate-loop-tutorial-seen`キー新設 | 2026-07-08 |
| v1.6 | plan.days[].ids → days[].meals.{朝,昼,夜}へ拡張(旧ids配列はmigrate()で`meals.夜`に変換)。state.history(献立カレンダー用)を新設、migrate()で`[]`補完。在庫チップの手動補正(非永続) | 2026-07-08 |
| v1.7 | 献立提案への要望入力(音声+テキスト)のGemini反映・調理モード追加。AppState自体は不変(要望・提案理由・調理モードの状態はすべて非永続のグローバル変数) | 2026-07-10 |
| v1.8 | state.deals(チラシOCRの特売情報)新設、migrate()で`[]`補完(家族同期対象)。Receipt.items/total追加(OCR確認モーダルで「在庫に追加」実行時のみ付与、レシート自体は引き続き非同期)。レシートOCRのスキーマにgenre(食材ジャンル)を追加 | 2026-07-10 |
| v1.10 | AppStateスキーマ変更なし。UI改修: チュートリアルを3枚スライド化+モバイルでの「はじめる」押下不可を修正、設定タブを下部ナビから廃止しヘッダー☰メニューへ集約(下部ナビ4タブ化)、設定タブの「買い物記録」UI削除(`settings.shoppingLog`フィールドは後方互換のため存置・非推奨)、調理モードの読み上げに材料の分量(大さじ/小さじ/g/個)を追加 | 2026-07-13 |
| v1.11 | AppStateスキーマ変更なし。レシピOCR(Gemini)を追加: 本・Kindle・雑誌・手書きの画像から複数レシピ(名前/カテゴリ/調理時間/材料/作り方)を抽出→確認・編集モーダルでチェックした分だけseed:falseのRecipeとしてstate.recipesに追加(画像自体は保存しない)。searchLinks()をGoogle検索経由からクラシル/DELISH KITCHENのサイト内検索への直リンクに変更 | 2026-07-14 |
| v1.12 | AppStateスキーマ変更なし。UI改修: 単発献立提案の結果画面に「🗑 クリア」ボタン追加(state.current=nullで入力画面に戻る)、買い物タブに一括操作バー追加(すべて選択/解除トグル・選択を在庫に追加・選択を削除)、BUILTIN_NORM_DICTをひらがな正規化方針で拡充(20組→128組・63食材)、UI文言「食材名の辞書」→「食材辞書」に変更(関数名・キー不変) | 2026-07-14 |

## 在庫マッチングの仕様
`inStock(ingName)`: 両辺を `normalizeName()` で正規化してから部分一致(`includes`)を双方向で判定する。
「鶏もも肉」の在庫は材料「鶏もも肉」にも「鶏もも」にもヒットする。
「たまねぎ」の在庫は組み込み辞書により「玉ねぎ」にも正規化されてヒットする(v1.5)。
