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

- `DayFlow/Services/` — `CalendarService`, `ReminderService` (`@Observable`, EventKit), `ScheduleStore`
- `DayFlow/Services/Obsidian/` — Obsidian連携（VoiceDrop方式を移植）: `KeychainStore`, `GitHubClient`, `GitHubSync`, `VaultWriter`, `ScheduleMarkdown`
- `DayFlow/Models/` — `CalendarEvent`, `ReminderItem`, `TimeCategory`, `TimeBlock`, `DaySchedule`
- `DayFlow/Views/` — `ReviewHomeView`, `TimeScheduleView`, `InsightsView`, `MainTabView`, `SettingsView`（旧Dashboard/Month/Yearは互換用に残存）
- `DayFlow/Views/Components/` — `NewItemSheet`, `DayDetailSheet`, `EventRow`, `ReminderRow`, `SectionHeader`, `TimeWheelView`, `CategoryEditorSheet`
- `DayFlowWidget/` — Widget extension (TodayWidget, StatsWidget, shared `WidgetDataProvider`)

### 時間割（Time-schedule）feature

- **タブ**: MainTabView は「今日・記録・分析」の3タブ。時間割エディタは「記録」に配置。
- **現在のプロダクト軸**: 「昨日の実績を短時間で振り返り、今日の予定を組み直す」。タブは「今日・記録・分析」の3本。今日タブから昨日実績／今日予定へ直接遷移し、分析はイベント件数ではなく時間ポートフォリオを表示する。
- **予定の自動生成**: 今日タブから時刻付きカレンダーイベントを仕事カテゴリとして時間割へ取り込める。既存の予定は上書きしない。
- **予定→実績**: 同日の予定がある場合、実績編集画面から複製して差分だけ修正できる。
- **円グラフUI** (`TimeWheelView`): 24hの放射リング。00:00が上・時計回り（6:00右/12:00下/18:00左）。指ドラッグでカテゴリを塗る。内部は5分×288スロットの `[String?]` を編集し、`TimeGrid` で `[TimeBlock]` と相互変換。塗りは「直前スロット→現在スロットの短い方の弧」を埋めるので速いドラッグでも連続する。
- **カテゴリ** (`TimeCategory`): プリセット9種（睡眠/仕事/学習/食事/移動/運動/家事/娯楽/自由）＋カスタム追加可（`CategoryEditorSheet`）。idは安定slug、blocksとvault markdownはidで参照するので改名しても壊れない。
- **予定/実績**: `ScheduleKind`。同じエディタで日付ステッパ＋セグメントで切替。「前日の実績を記録」も同じ画面で。
- **保存**: `ScheduleStore` が Documents配下の `schedules.json` / `custom_categories.json` にJSON永続化（アプリ自身の source of truth）。ドラッグ終了ごとに `commit()`。
- **Obsidian出力**: `commit()` から `VaultWriter.writeDay` で1日1ファイル `TimeLog/YYYY/MM/YYYY-MM-DD.md` を全体再生成。予定・実績のカテゴリ別テーブル＋割合＋`[[YYYY-MM-DD]]` backlink＋往復用の隠しJSON（`<!-- dayflow:… -->`）。

### Obsidian連携（VoiceDrop方式の移植）

- **ローカルVault**: security-scopedブックマークで選んだフォルダに直接書き込み（`VaultWriter`）。
- **GitHubミラー** (`GitHubSync`): iPhone単体で正典VaultのGitリポジトリへ Contents API 直コミット。オフラインoutbox（path単位で最新renderに置換）＋2秒デバウンスflush（ドラッグ連打を1コミットに集約）。有効化・owner/repo/branch・PATは `SettingsView`（時間割タブ右上の歯車）で設定。トークンはKeychain（`com.chisatoo.dayflow.secrets`）。
- 全て任意。未設定でも時間割エディタは完全動作（`writeDay` は `isConfigured` でガード）。

### SwiftUI落とし穴メモ

- Form内の `Toggle` は、computer-use等の「一瞬のクリック（down+upが同時）」だとスクロール認識に食われて反応しない。**down と up を別コールにして間隔を空ける**と正しくタップ扱いになる（バインディングのバグではない）。ネストした `@Observable` へのバインドは `body` 冒頭で `@Bindable var x = writer.github` として `$x.…` で問題なく動く。

## TestFlight / App Store

- `ExportOptions.plist` is at project root (not /tmp)
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload
- App icon must be RGB, no alpha (1024x1024)
- Icon generated via Python/Pillow (Swift/CoreGraphics crashes with `hasAlpha: false`)
