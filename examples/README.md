# Examples

各exampleは、Quint spec、MoonBit driver、実行可能なentrypoint、contract testを同じdirectoryに置く。
repository rootで `nix develop -c just check` を実行すると、全exampleのpositive / negative controlが走る。

| Example | 主な用途 | Connect API | 負例 |
|---|---|---|---|
| [`order_checkout/`](order_checkout/) | lifecycle、set、variant、nested named test | `replay_suite`、`TraceConfig` | cancel後のstateを`Refunded`へ壊す |
| [`bank_account/`](bank_account/) | nondeterministic integer argument、state projection | `required_nondet`、`replay_suite` | withdrawを二重に引き落とす |
| [`command_sink/`](command_sink/) | observable stateを持たないcommand adapter | `replay_stateless` | `reset` mappingを欠落させる |

共通構造は次の通り。

```text
*.qnt
  -> quint run --mbt
  -> runner.generate_run
  -> ITF traces
  -> example driver apply
  -> project and compare, or stateless action execution
```

exampleのmodelはproduction requirementではなく、adapter APIを説明するmachine-checked sampleである。
positive controlだけではmappingの識別力が分からないため、各exampleに意図的な破壊optionを固定している。
