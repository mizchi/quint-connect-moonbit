# Quint Connect pattern in MoonBit

MoonBit package名は `mizchi/quint_connect`。Quint の model-based testing trace をMoonBit実装へ
replayする、実動するruntime adapterである。
公式 `quint-connect` の Rust attribute macro を移植したものではないが、Connect の中核である
「Quint が生成した action を実装へ適用し、各 step の observable state を比較する」workflow は
MoonBit で再現できた。

## 再現

repository root で次を実行する。

```sh
nix develop -c just check
```

MoonBit toolchainはhostの `~/.moon/bin` を使う。devShellはQuint 0.32、just、rgなどintegration
controlに必要なtoolを提供する。すでに `moon` と `quint` がPATHにある場合は `just check` だけでもよい。

このtaskはformatter、typecheck、unit testに加えて、次のpositive / negative controlを実行する。

- adapter、generator、seed、path projection、multi-trace replay の unit test 11件
- `quint run --mbt` が生成する8 traces / 34 statesの正常 replay
- 同じ生成traceに対し、意図的に壊した `cancelCart` が `Cancelled` / `Refunded` の差分で失敗すること
- `quint test` のnamed testを、nested stateとcustom sum-type actionから1 trace / 2 states replayすること
- named testでも壊したdriverが失敗すること

CLIを直接使う場合は次のようになる。

```sh
moon run cmd/connect run fixtures/OrderCheckout.qnt \
  --main OrderCheckout --max-samples 8 --max-steps 8 --seed 0x1234

moon run cmd/connect test fixtures/OrderCheckoutNamed.qnt \
  --main OrderCheckoutNamed --test cancelTest \
  --state-path model --nondet-path actionTaken --seed 0x1234
```

CLI seed、`QUINT_SEED`、自動生成seedの順に優先する。`QUINT_VERBOSE=1` でtraceごとの
action列を表示し、`--keep-traces` で一時ITFを残せる。backendのdefaultは
`typescript` で、`--backend rust` も指定できる。

## 構成

```text
connect run/test
  -> RunConfig / TestConfig
  -> MoonBit async process runner
  -> quint run --mbt / quint test
  -> temporary ITF files
  -> configurable state/action projection
  -> fresh MoonBit driver per trace
  -> action apply -> state project -> expected state compare
```

| 層 | ファイル | 責務 |
|---|---|---|
| contract | `adapter.mbt` | ITF、trace設定、replay結果、失敗境界の型 |
| generator | `generator.mbt` | `run` / `test` 引数、backend、seedの検証 |
| process | `runner/runner.mbt` | Quint起動、一時directory、複数ITFの収集とdecode |
| replay kernel | `adapter.mbt` | action適用、state projection、stepごとの一致判定 |
| domain adapter | `order_driver.mbt` | `OrderCheckout` action/stateとMoonBit実装の対応 |
| CLI | `cmd/connect/main.mbt` | 明示的な `run` / `test` API、診断、再現seed |

libraryとして参照するときのimport pathは `mizchi/quint_connect`、runner packageは
`mizchi/quint_connect/runner` である。

各traceは新しいdriverから開始する。失敗は `TraceDecode`、`DriverRejected`、
`StateDiverged`、suite内の `TraceFailed`、Quint process errorに分け、model、mapping、
implementationのどの境界で失敗したかを残す。

## 公式 Connect との対応

| 公式側の概念・機能 | MoonBit版 | 備考 |
|---|---|---|
| `Driver::step` | 対応 | callbackでactionとnondeterministic picksを実装へ適用 |
| `State::from_driver` | 対応 | projection callbackでobservable stateだけを比較 |
| `#[quint_run]` | 対応 | `connect run` / `RunConfig` という明示API |
| `#[quint_test]` | 対応 | `connect test` / `TestConfig` とcustom action path |
| `switch!` / pick decode | 部分対応 | action matchと `required_nondet` / `optional_nondet` |
| Quint processからtrace生成 | 対応 | native async process runnerを使用 |
| 複数trace replay | 対応 | traceごとにfresh driverを生成して集計 |
| nested state / nondet path | 対応 | `--state-path` / `--nondet-path` |
| `QUINT_SEED` | 対応 | CLI seedを最優先し、失敗時に再現方法を表示 |
| `QUINT_VERBOSE` | 部分対応 | action列を表示。公式と同じ詳細loggerではない |
| stateless driver | 対応 | `replay_stateless`を提供 |
| typed ITF decode | 部分対応 | boundaryは`Json`で、domain adapterが明示decode |
| Rust attribute macro / derive | 非対応 | MoonBitではCLIと通常関数を明示的に呼ぶ |

## 分かった制約

- 実装済みのdomain adapterは `OrderCheckout` のみである。replay kernel自体はgenericだが、
  action mappingとstate projectionは対象実装ごとに書く必要がある。
- MoonBit core JSONのnumberは`Double`を経由する。`2^53`を超える整数を正確に比較する用途では、
  ITF boundaryに別decoderまたは文字列表現が必要になる。
- Quintのset、map、tuple、variantはraw JSONとして保持できるが、RustのSerde相当の自動変換はない。
- action適用は同期callbackである。実network、clock、並行I/Oを含むdriverの評価は未実施である。
- compile-time attribute macro、trace shrinking、網羅性の証明はscope外である。有限個の生成traceに
  対するconformance testであり、formal verificationそのものではない。
- process runnerはMoonBit native async、replay kernelのunit testはJS targetで確認している。
- Quint 0.32のRust backendでは、multi-trace出力の初期actionが一部 `init` ではなく `step` と
  表示されるケースを観測した。再現性のあるcontractを優先し、このCLIはTypeScript backendを
  defaultにしている。

## 評価

| 項目 | 結果 |
|---|---|
| source | Quint公式model-based testing documentationと公式`quint-connect`実装 |
| observation | generated 8 traces / 34 states、named test 1 trace / 2 statesが一致 |
| negative control | 両経路で `cancelCart` の `Cancelled` / `Refunded` driftを検出 |
| decision | runtime adapter patternはMoonBitでも採用可能。macro/derive互換は目標にしない |
| trust boundary | Quint spec、action mapping、state projection、ITF decoder |
| lock | fixed seed `0x1234` とpositive / negative controlをCI taskに固定 |

Connect の価値はadapterの薄さではなく、specと実装の対応関係を明示的なcontractとしてCIで
継続検査できることにある。一方でprojectionを間違えると誤った安心につながるため、正常系だけでなく
意図的なstate driftを必ず同じfixtureで検出する。
