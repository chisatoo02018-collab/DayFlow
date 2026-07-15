# DayFlow

iOS productivity app — calendar events + reminders dashboard with widgets.

## Project Setup

- **Framework:** SwiftUI, iOS 17+, `@Observable` macro
- **Project management:** xcodegen (`project.yml`)
- **Bundle ID:** `com.chisatoo.dayflow`
- **Team ID:** `WY55TM2MU8`
- **Device:** iPhone only (`TARGETED_DEVICE_FAMILY: "1"`)

## Build Commands

Every `xcodebuild` / `xcrun` command **must** be prefixed with:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Available simulator: `iPhone 17 Pro` (not iPhone 16)

When adding or removing Swift files, run `xcodegen generate` before building.

## Architecture

- `DayFlow/Services/` — `CalendarService`, `ReminderService` (`@Observable`, EventKit), `ScheduleStore`, `HealthService`（HealthKit読み取り: 歩数/心拍/睡眠/消費kcal/運動。睡眠・運動の区間取得も）, `HealthBackgroundSync`（HKObserverQuery+バックグラウンド配信でアプリ非起動時もdaily note更新）
- `DayFlow/Services/Obsidian/` — Obsidian連携（VoiceDrop方式を移植）: `KeychainStore`, `GitHubClient`, `GitHubSync`, `VaultWriter`, `ScheduleMarkdown`
- `DayFlow/Models/` — `CalendarEvent`, `ReminderItem`, `TimeCategory`, `TimeBlock`, `DaySchedule`
- `DayFlow/Views/` — `ReviewHomeView`（今日タブ）, `TimeScheduleView`（記録タブ）, `InsightsView`（分析タブ）, `MainTabView`, `SettingsView`, `HealthSection`（Apple Watchヘルス表示、ReviewHomeViewに埋め込み）（旧Month/Yearは互換用に残存。旧DashboardViewは非参照の死蔵だったため2026-07-13に削除）
- `DayFlow/Views/Components/` — `NewItemSheet`, `DayDetailSheet`, `EventRow`, `ReminderRow`, `SectionHeader`, `TimeWheelView`, `CategoryEditorSheet`
- `DayFlowWidget/` — Widget extension (TodayWidget, StatsWidget, shared `WidgetDataProvider`)

### 時間割（Time-schedule）feature

- **タブ**: MainTabView は「今日・記録・分析」の3タブ。時間割エディタは「記録」に配置。
- **現在のプロダクト軸**: 「昨日の実績を短時間で振り返り、今日の予定を組み直し、明日を仕込む」。タブは「今日・記録・分析」の3本。今日タブは**昨日・今日・明日の3日カード**(`DayCard`)で、各カードから対応する日の編集(昨日=実績/今日・明日=予定)へ直接遷移する。明日カード/DateNavigatorの明日ボタンはカレンダー取り込み→予定編集への高速導線。分析はイベント件数ではなく時間ポートフォリオを表示する。
- **予定→実績の複製**: `ScheduleStore.copySchedule`を`DuplicatePlanCard`(記録タブ・実績かつ予定あり・実績空の時だけ表示)で配線。「予定をコピーして差分だけ直す」ワークフロー。
- **予定の自動生成**: 今日タブから時刻付きカレンダーイベントを仕事カテゴリとして時間割へ取り込める。既存の予定は上書きしない。
- **予定→実績**: 同日の予定がある場合、実績編集画面から複製して差分だけ修正できる。
- **閲覧/編集モード**: 初期状態は閲覧モードで、リングへのタップやドラッグでは変更されない。「編集する」を明示的に押したときだけ塗り替え可能。
- **精密編集**: 編集モードで塗った区間をタップすると開始・終了につまみを表示。リング上のドラッグまたは編集カードの±ボタンで5分単位に調整でき、区間削除にも対応。縦スクロールとの誤認を避けるため、塗りは円周方向のドラッグだけを受け付ける。
- **データ出所**: `TimeBlock.source`（manual/calendar/healthKit/imported）と`isUserModified`を後方互換つきで保持。将来の自動記録と手動修正のUI分岐に利用する。
- **主カテゴリ+タグ（重複活動）**: `TimeBlock.tags: [String]`で1区間に副次カテゴリを複数付与できる（例: 移動(主)＋運動(タグ)）。リングは主カテゴリで着色、タグは内側の細い輪で描画。編集は区間選択時の「兼ねている活動」チップ。`TimeGrid`は主スロット`[String?]`とタグスロット`[Set<String>]`を並行編集し、blocks(from:tagSlots:)で主orタグ集合の境界ごとに分割。**設計思想**: 客観的センサー事実(重なる)を主観的会計リング(重なり不可の分割)に上書きで混ぜない。センサーはタグとして乗せるか空き時間だけ埋める。
- **HealthKit→実績リング**: 設定「睡眠を実績リングの正とする」「運動を実績リングに反映」で、実績を開くたび`.task`で自動反映。睡眠(`sleepIntervals`)は主カテゴリ睡眠を置換(手動の他カテゴリは上書きしない・空き時間のみ)、運動(`exerciseIntervals`=appleExerciseTime間隔)は空きは主カテゴリ運動・重なりは運動タグ。メニューから手動取込も可。
- **バックグラウンド同期**: `HealthBackgroundSync`がHKObserverQuery+enableBackgroundDelivery(.hourly)を登録。Watch sync時にiOSがアプリをバックグラウンド起動しdaily noteの`## ヘルス`を更新+GitHub push。リングの睡眠/運動反映はアプリ前面時のみ。healthkit.background-delivery entitlement必要。
- **日付選択**: 昨日・今日を主要ショートカットとして常時表示。任意日はカレンダーボタンのグラフィカルDatePickerから選ぶ。
- **予定パターン**: 現在の予定リングを「仕事の日」「習い事の日」などの名前で永続保存し、別の日へ呼び出せる。`schedule_templates.json`に保存。
- **スクロール共存**: リングの操作ヒット領域はドーナツ形の円周だけ。中央と外側の上下スワイプは親ScrollViewへ渡す。
- **時刻表示**: リング内側に0〜23時を1時間ごと、同一サイズで表示する。
- **円グラフUI** (`TimeWheelView`): 24hの放射リング。00:00が上・時計回り（6:00右/12:00下/18:00左）。指ドラッグでカテゴリを塗る。内部は5分×288スロットの `[String?]` を編集し、`TimeGrid` で `[TimeBlock]` と相互変換。塗りは「直前スロット→現在スロットの短い方の弧」を埋めるので速いドラッグでも連続する。
- **カテゴリ** (`TimeCategory`): プリセット9種（睡眠/仕事/学習/食事/移動/運動/家事/娯楽/自由）＋カスタム追加可（`CategoryEditorSheet`）。idは安定slug、blocksとvault markdownはidで参照するので改名しても壊れない。
- **予定/実績**: `ScheduleKind`。同じエディタで日付ステッパ＋セグメントで切替。「前日の実績を記録」も同じ画面で。
- **保存**: `ScheduleStore` が Documents配下の `schedules.json` / `custom_categories.json` にJSON永続化（アプリ自身の source of truth）。ドラッグ終了ごとに `commit()`。
- **Obsidian出力**: `commit()` から `VaultWriter.writeDay` で詳細ファイル `TimeLog/YYYY/MM/YYYY-MM-DD.md` を全体再生成。同時に `Daily/YYYY/MM/YYYY-MM-DD.md` のマーカー付き `## DayFlow` セクションだけを冪等更新し、Voice Logなど既存本文を保持する。右上メニューから選択中の日を手動再同期できる。

### Obsidian連携（VoiceDrop方式の移植）

- **ローカルVault**: security-scopedブックマークで選んだフォルダに直接書き込み（`VaultWriter`）。
- **GitHubミラー** (`GitHubSync`): 専用`TimeLog`ファイルはContents APIで更新し、共有DailyのDayFlow/ヘルス管理ブロックは`system/ingest/dayflow/pending/`へ一意JSONとして送る。Mac miniの単一マージャーだけがDailyへ反映する。オフラインoutbox＋2秒デバウンスflush。トークンはKeychain（`com.chisatoo.dayflow.secrets`）。
- 全て任意。未設定でも時間割エディタは完全動作（`writeDay` は `isConfigured` でガード）。

### SwiftUI落とし穴メモ

- Form内の `Toggle` は、computer-use等の「一瞬のクリック（down+upが同時）」だとスクロール認識に食われて反応しない。**down と up を別コールにして間隔を空ける**と正しくタップ扱いになる（バインディングのバグではない）。ネストした `@Observable` へのバインドは `body` 冒頭で `@Bindable var x = writer.github` として `$x.…` で問題なく動く。

## TestFlight / App Store

### DayFlowの実装完了ルール（2026-07-14）

- ユーザーからDayFlowの機能追加・修正・改善を依頼された場合、明示的に「配布しない」「ローカルだけ」と指定されない限り、実装だけで終了しない。
- 完了条件は、①シミュレータbuild、②実機archive、③`CURRENT_PROJECT_VERSION`を一意に更新、④TestFlightへアップロードして`Upload succeeded` / `EXPORT SUCCEEDED`を確認、⑤DayFlow `main`へcommit・push、のすべて。
- ユーザーへ「実装済み」と報告する時点では、その変更を含むTestFlight Build番号とmain commitを併記する。
- TestFlightアップロード後に追加変更した場合、その変更を含む新しいBuildを再度アップロードする。リポジトリ最新断面とTestFlight最新断面をずらしたまま完了扱いにしない。

- `ExportOptions.plist` is at project root (not /tmp)
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload
- App icon must be RGB, no alpha (1024x1024)
- Icon generated via Python/Pillow (Swift/CoreGraphics crashes with `hasAlpha: false`)
