# quint-connect-moonbit

`quint-connect-moonbit` は、[Quintのモデルベーステスト](https://quint.sh/docs/model-based-testing)を
MoonBitの実装に接続する実験的なruntime adapterです。MoonBitのpackage名は `mizchi/quint_connect` です。

[English version](README.md)

このリポジトリは、実行可能なQuint specificationとMoonBit実装を次の流れで接続します。

1. Quintが、モデルで許可されたexecution traceを1つ以上生成する。
2. adapterがInformal Trace Format（ITF）のtraceを読み込む。
3. domain driverが各Quint actionをMoonBit実装の操作へ対応づける。
4. 各actionの実行後に、観測可能な実装snapshotとQuintが期待するstateを比較する。

これにより、生成されたscenarioにおける **specificationと実装のずれ** を検出できます。ただし、可能なすべての
executionについてMoonBit実装が正しいと証明するものではありません。

このプロジェクトは公式の[Quint Connect](https://github.com/quint-co/quint-connect) Rust libraryと同じruntime
patternを採用していますが、公式portではありません。Rustのattribute macroやSerde deriveの代わりに、明示的な
MoonBit functionと実行packageを使用します。

## このリポジトリの目的

モデルが正しくても、production codeがstate transitionを誤って実装することがあります。通常のexample-based testで
扱えるのは、多くの場合、手書きした少数のscenarioです。モデルベーステストでは、1つのモデルから多数の正しいaction
sequenceと期待stateをQuintに生成させられます。

重要な接続部分は、意図的に明示しています。

- **Action mapping:** 各Quint actionは、実装のどの操作に対応するか。
- **Input mapping:** Quintのnondeterministic choiceを、どのように実装の引数へdecodeするか。
- **State projection:** 実装のどのfieldを観測し、モデルと比較するか。

これらのmappingはapplication固有であり、他のAPI contractと同様にreviewする必要があります。このpackageは、その接続を
囲むITF parsing、replay loop、trace generation、diagnostics、再利用可能な型を提供します。

## 動作の仕組み

```text
Quint specification
  -> quint run --mbt または quint test
  -> 一時ITF JSON trace
  -> parse_itf_with_config
  -> traceごとに新しいMoonBit driver
  -> apply(action, nondet_picks)
  -> project(driver)
  -> 期待されるQuint stateと比較
```

`quint run --mbt` では、default parserが使用する2つのfieldをQuintが記録します。

- `mbt::actionTaken`: そのstepで選択されたaction
- `mbt::nondetPicks`: 関連する `nondet` expressionが選択した値

adapterは、観測対象のstateとaction dataを任意のnested pathへ保存する、名前つき `quint test` traceにも対応します。
OrderCheckout exampleがこのcontractを示します。

## クイックスタート

必要なもの:

- `~/.moon/bin` にinstallされたMoonBit toolchain
- flakesを有効にしたNix、またはローカルにinstallしたQuint 0.32、`just`、`rg`

repository rootから完全なvalidation suiteを実行します。

```sh
nix develop -c just check
```

必要なtoolがすべて `PATH` にある場合:

```sh
just check
```

このcommandは、format check、MoonBit type check、14件のunit test、Quint type check、全exampleのintegration controlを
実行します。このリポジトリで使用する固定seedでは、integration suiteは次を検査します。

| Example | Positive control | Negative control |
|---|---|---|
| OrderCheckout simulation | 8 traces / 34 states | cancelが誤ったterminal stateを生成する |
| OrderCheckout named test | 1 trace / 2 states | custom path経由で同じcancelのずれを検出する |
| BankAccount | 8 traces / 72 states | withdrawが選択額の2倍を引き落とす |
| CommandSink | 8 traces / 72 actions | 実装に `reset` mappingがない |

これらの件数は決定的なregression fixtureであり、coverageやproofを主張するものではありません。

## リポジトリ構成

| Path | 責務 |
|---|---|
| [`adapter.mbt`](adapter.mbt) | ITF型、parsing、path projection、replay、error boundary |
| [`generator.mbt`](generator.mbt) | 検証済みの `quint run` / `quint test` command構築とseed優先順位 |
| [`runner/`](runner/) | native async Quint process実行と一時ITF収集 |
| [`examples/`](examples/) | Quint spec、MoonBit driver、実行package、negative-control sample |
| [`scripts/check.sh`](scripts/check.sh) | 全exampleのend-to-end regression control |
| [`justfile`](justfile) | 再現可能なformat、type check、unit test、integration task |

再利用可能なpackageは `mizchi/quint_connect` です。process実行はnative専用の
`mizchi/quint_connect/runner` packageへ分離しています。そのためreplay kernelはportableなまま維持され、JS targetで
unit testできます。

## Core API

### Trace parsing

- `parse_itf(text)` は、標準的な `quint run --mbt --out-itf` 出力をparseします。
- `parse_itf_with_config(text, config)` は、さらにnested stateとcustom action dataをprojectします。
- `TraceConfig.state_path` は、domain adapterがdecodeするmodel stateを選択します。
- `TraceConfig.nondet_path` は、action tagと引数を含むcustom Quint variantを選択します。
- `required_nondet` と `optional_nondet` は、Quintの `Some` / `None` をnormalizeした後、名前つきchoiceをdecodeします。

parserはdomain stateを意図的に `Json` のまま保持します。各domain adapterは、比較するfieldを明示的にdecodeする必要が
あります。reviewされていない自動変換を、信頼できるcontractの一部として扱わないためです。

### Stateful replay

`replay` は1つのtraceを処理します。`replay_suite` は複数のtraceを処理し、traceごとに新しいdriverを構築します。
どちらも同じ3つのcallbackを使用します。

```moonbit
apply    : (Driver, String, Json) -> Result[Driver, String]
project  : (Driver) -> Snapshot
expected : (Json) -> Result[Snapshot, String]
```

trace内の各stateについて、`apply` が選択されたactionを実行し、`project` が実装snapshotを抽出し、`expected` が対応する
Quint snapshotをdecodeします。2つのsnapshotは `Eq` と `Debug` を実装し、各stepで一致する必要があります。

### Stateless replay

`replay_stateless` は、実装stateを比較せずにすべてのactionを実行します。action mappingだけを観測できるcommand
dispatcher、API client、その他のadapterに有用です。rejectされたactionや未知のactionは報告しますが、state driftは
検出できません。意味のあるsnapshotを取得できる場合はstateful replayを優先してください。

### Trace generation

- `RunConfig` は、`quint run --mbt` によるrandomized simulationを記述します。
- `TestConfig` は、`quint test --match` で選択する名前つきscenarioを記述します。
- `runner.generate_run` と `runner.generate_test` はQuintを起動し、生成された全ITF fileを収集してparseします。
- CLI seedの優先順位は、command-line seed、`QUINT_SEED`、自動生成seedの順に明示されています。

example executableはdefaultでTypeScript simulator backendを使用します。OrderCheckout CLIは `--backend rust` も
受けつけますが、このリポジトリで検査する再現可能なbaselineはTypeScript backendです。

## Failure model

失敗をboundaryごとに分離しているため、red testからどのcontractが壊れたか判断できます。

| Error | 意味 |
|---|---|
| `TraceDecode` | ITF構造、設定path、metadata、またはexpected-state decodingが不正 |
| `DriverRejected` | MoonBit driverがQuint actionを実行できない、または引数をdecodeできない |
| `StateDiverged` | actionは実行されたが、projectしたMoonBit stateとQuint stateが異なる |
| `TraceFailed` | 複数traceのうち1つが失敗した。trace indexは保持される |
| process error | Quintが失敗した、traceを生成しなかった、またはITF fileを読めなかった |

integration suiteには、`DriverRejected` と `StateDiverged` の両方を起こす意図的な失敗が含まれます。positive testだけでは、
mappingと比較処理が実際に機能していることを示せません。

## Examples

機能ごとの概要は[examples guide](examples/)を参照してください。

| Example | 学べること |
|---|---|
| [OrderCheckout](examples/order_checkout/) | lifecycle transition、setとvariant、nondeterministic item選択、generated trace、named trace、nested projection |
| [BankAccount](examples/bank_account/) | nondeterministic choiceによるinteger引数、Quint `#bigint` decoding、小さなstate projection |
| [CommandSink](examples/command_sink/) | stateless action replay、不完全なcommand mappingの検出 |

各exampleには次が含まれます。

- 実行可能なQuint model（`*.qnt`）
- actionを対応づけ、expected stateをdecodeするMoonBit driver
- `cmd/` 以下の実行可能なnative executable
- MoonBit contract test
- integration scriptが使用する意図的に壊したmode

## 公式Quint Connectとの関係

| 公式Rust版の概念 | このMoonBit package | 状態 |
|---|---|---|
| `Driver::step` | `apply` callback | 対応 |
| `State::from_driver` | `project` callback | 対応 |
| generated simulation trace | `RunConfig` + `runner.generate_run` | 対応 |
| named scenario trace | `TestConfig` + custom trace path | 対応 |
| 複数trace | traceごとに新しいdriverを作る `replay_suite` | 対応 |
| nondeterministic value helper | `required_nondet` / `optional_nondet` | 手動で対応 |
| unit-state driver | `replay_stateless` | 対応 |
| `QUINT_SEED` | 明示的なseed解決と再現用出力 | 対応 |
| Rust `switch!` macro | 通常のMoonBit pattern matching | 手動で同等機能を実現 |
| Rust attribute macro | 明示的なconfigとexecutable code | 未実装 |
| Serde deriveによるtyped ITF変換 | domain固有のJSON decoding | 未実装 |
| trace shrinking | — | 未実装 |

## 保証と制約

suiteが成功したときに言えること:

- 生成されたすべてのtraceをdriverが受けつけた。
- 選択されたすべてのactionとnondeterministic inputを正しくmappingできた。
- state projectionに含めたすべてのfieldが、検査した各stepで一致した。

**言えないこと:**

- 実装がformal verificationされた。
- 可能なすべてのexecutionを探索した。
- projectionから除外したfieldが正しい。
- 実際のnetwork、clock、concurrency、failure injection、外部I/Oのsemanticsを検査した。
- Quint specification自体が意図したsystemを正しく表現している。

その他の実装上の制約:

- Quintのset、map、tuple、variantは、domain adapterがdecodeするまでraw ITF JSONのままです。
- Quint integerは通常 `{ "#bigint": "..." }` とencodeされます。BankAccountに明示的なdecoderがあります。
- MoonBit coreのJSON numberは `Double` を使うため、`2^53` を超えるintegerにはfloating-point変換ではなく、
  string / `#bigint` decoderが必要です。
- Action callbackはsynchronousです。asyncなproduction operationには追加のdriver abstractionが必要です。
- Quintの `--mbt` metadataはexperimentalと記載されており、Quint version間で変わる可能性があります。

## 開発command

```sh
just fmt          # MoonBit sourceをformat
just --fmt        # justfileをformat
just fmt-check    # MoonBit formatを検査
just typecheck    # warningを拒否してMoonBitをtype check
just test         # portableなunit / contract test 14件
just integration  # 実際のQuint traceを生成してreplay
just check        # すべてを実行
```

## 参考資料

- [Quint model-based testing](https://quint.sh/docs/model-based-testing)
- [Quint CLI and `--mbt` metadata](https://quint.sh/docs/quint)
- [Official Quint Connect for Rust](https://github.com/quint-co/quint-connect)
- [Quint Connect announcement](https://quint.sh/posts/quint_connect)
- [Informal Trace Format](https://apalache-mc.org/docs/adr/015adr-trace.html)

## License

Apache-2.0。詳細は [`LICENSE`](LICENSE) を参照してください。
