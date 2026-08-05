# Examples

This directory contains complete, runnable examples of the `mizchi/quint_connect` contract. Each example keeps the
formal model and the implementation adapter close together so that the mapping can be reviewed as one unit.

Every example includes:

- a Quint specification that defines allowed states and actions;
- a MoonBit driver that maps those actions to implementation behavior;
- an observable-state decoder, or an explicit decision to use stateless replay;
- a native executable that generates and replays real Quint traces;
- contract tests with a small hand-written trace;
- a deliberately broken mode that proves the integration check can detect the intended mismatch.

BankAccount also includes a Wasm executable that replays embedded ITF without process or filesystem access.

Run all examples from the repository root:

```sh
nix develop -c just integration
```

Run the complete project check, including formatting, all-target type checking, and 16 unit/contract tests on
JavaScript, Wasm, and native:

```sh
nix develop -c just check
```

## Choosing an example

| Example | Start here when you need to understand | Main API | Deliberate failure |
|---|---|---|---|
| [OrderCheckout](order_checkout/) | lifecycle state machines, sets/variants, generated and named traces, nested state | `replay_suite`, `TraceConfig` | cancellation reaches `Refunded` instead of `Cancelled` |
| [BankAccount](bank_account/) | nondeterministic integer arguments and a small state projection | `required_nondet`, `replay_suite` | withdrawal debits twice the selected amount |
| [CommandSink](command_sink/) | an implementation whose internal state is not compared | `replay_stateless` | the `reset` action mapping is missing |

## Shared execution pattern

```text
example/*.qnt
  -> runner.generate_run or runner.generate_test
  -> Quint process
  -> ITF JSON files
  -> example driver
  -> state comparison or stateless action execution
  -> positive/negative regression result
```

The Quint model is the expected behavior for each sample, while the MoonBit driver is the explicit bridge to the
implementation. A green result says that the generated traces agree through that bridge. It does not establish that
the model captures the right product requirements or that ungenerated executions are correct.

## Why every example has a broken mode

A positive replay can become vacuous if the driver stops executing an action, the projection drops an important field,
or the expected-state decoder reads the wrong path. Each example therefore contains a negative control aimed at its
main teaching point:

- OrderCheckout proves that a wrong lifecycle transition becomes `StateDiverged`.
- BankAccount proves that a wrong arithmetic update becomes `StateDiverged`.
- CommandSink proves that an incomplete stateless action mapping becomes `DriverRejected`.

The fixed seed `0x1234` makes those witnesses reproducible in `scripts/check.sh`.
