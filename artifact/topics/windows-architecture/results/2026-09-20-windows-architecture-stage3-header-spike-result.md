# 段階 3 事前スパイク: 公開ヘッダーの骨組み

- 日付: 2026-09-20
- 目的: 設計書 `designs/2026-09-20-windows-architecture-cpp-api-design.md` の 7.1（`WindowHandle`）と 7.2（`Result<T, E>`）が、記述どおりに書いて実際にコンパイルできるかを確かめる
- 位置づけ: 段階 3 の T-04 と U-D の前倒し。**実装ファイルは作らない**（作るのは T-02 の後）
- 環境: Visual Studio 2022 Community（`D:\Program Files\Microsoft Visual Studio\2022\Community`）、MSVC 14.44.35207、x64

## 1. 実施内容

一時ディレクトリに次の 4 ファイルを作り、`cl` でコンパイルした。

| ファイル | 内容 |
|---|---|
| `NativeToolkitTypes.h` | 設計書 7.1 の `struct HWND__;`（大域）と `WindowHandle`、`WriteOptions` |
| `NativeToolkitError.h` | 設計書 7.2 の `Failure<Code>`、`Unexpected<E>`、`Result<T, E>`、`Result<void, E>` |
| `check.cpp` | `<windows.h>` を include せずに両ヘッダーを単独 include し、`static_assert` で要件を確かめる |
| `check_windows_first.cpp` | `<windows.h>` を先に include し、`HWND` と `WindowHandle` の相互運用を確かめる |

コマンド:

```
cl /nologo /utf-8 /std:c++20 /EHsc /W4 /permissive- check.cpp
cl /nologo /utf-8 /std:c++20 /EHsc /W4 /permissive- check_windows_first.cpp
```

## 2. 結果

**両方ともコンパイルに成功した。** `static_assert` はすべて成立。

| 確かめたこと | 結果 |
|---|---|
| `<windows.h>` 抜きで両ヘッダーを単独 include できる | 成功 |
| `<windows.h>` を先に include した場合、`WindowHandle` と `HWND` が**同一の型**で相互に代入できる | 成功（`std::is_same_v` が true） |
| 機能ごとの別名（`Clipboard::Result` と `Dialog::Result`）が別の型になる | 成立 |
| `Result<MoveOnly>` がコピー不可・ムーブ可 | 成立 |
| `Result<int>` がコピー可能かつ自明に破棄可能 | 成立 |
| `T == E`（`Result<Failure<E>, Failure<E>>`）が曖昧にならない | 成立 |
| `Result<void, E>` の成功・失敗の構築と `error()` | 成立 |

## 3. 分かったこと（設計書へ反映済み）

| # | 内容 | 反映先 |
|---|---|---|
| 1 | **最初のコンパイルは `warning C4819` で失敗した。** UTF-8 の非 ASCII を含むファイルを MSVC が CP932 として読み、コメントが後続のコードを飲み込んだ。`/utf-8` を付けると通る。つまり**公開ヘッダーに非 ASCII を入れると利用者に `/utf-8` を強いる** | 7.1 に「公開ヘッダーは ASCII だけで書く」を追加 |
| 2 | `std::variant<T, E>` を**添字で**保持する形にすると、`T == E` でも曖昧にならず、コピー可否と自明な破棄も自動で伝播する。ただし `valueless_by_exception` を持ちうるため、設計書 7.2 の「値を持たない不正状態を公開しない」を厳密に満たすには、自前の union にするか `valueless` を `Failure` に写す必要がある | 7.2 に実装方式の選択として追記。決めるのは T-04 |

## 4. 成果物の扱い

検証用の 4 ファイルは**リポジトリに入れない**。段階 3 の T-02（プロジェクトの分割）より前に実装ファイルを置くと段階の順序が崩れるため、`include/NativeToolkit/` に置くのは T-04 で行う。検証済みの内容は設計書 7.1 と 7.2 のコードに反映してある。
