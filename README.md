# quint-connect-moonbit

`quint-connect-moonbit` is a MoonBit implementation of the official
[quint-connect](https://github.com/quint-co/quint-connect) Rust runtime library for
[Quint model-based testing](https://quint.sh/docs/model-based-testing). Its MoonBit package name is
`mizchi/quint_connect`. This project is experimental and is not an official port.

[Japanese version](README-ja.md)

The repository connects an executable Quint specification to a MoonBit implementation:

1. Quint generates one or more allowed execution traces.
2. The adapter reads those traces in Informal Trace Format (ITF).
3. A domain driver maps each Quint action to an operation in the MoonBit implementation.
4. After every action, the adapter compares an observable implementation snapshot with the state expected by Quint.

This catches **specification/implementation drift** in generated scenarios. It does not prove that the MoonBit
implementation is correct for every possible execution.

Like the Rust library, this implementation replays Quint actions and compares projected implementation state. MoonBit
uses explicit functions and executable packages here instead of Rust attribute macros and Serde derives.

## Why this repository exists

A model can be correct while production code implements a transition incorrectly. Traditional example-based tests
usually cover a small number of hand-written scenarios. Model-based testing instead lets Quint generate many valid
action sequences and expected states from one model.

The important bridge is intentionally explicit:

- **Action mapping:** which implementation operation corresponds to each Quint action?
- **Input mapping:** how are Quint's nondeterministic choices decoded into implementation arguments?
- **State projection:** which implementation fields are observable and compared with the model?

Those mappings are application-specific and must be reviewed like any other API contract. This package provides the
ITF parsing, replay loop, trace generation, diagnostics, and reusable types around that bridge.

## How it works

```text
Quint specification
  -> quint run --mbt or quint test
  -> temporary ITF JSON traces
  -> parse_itf_with_config
  -> fresh MoonBit driver for each trace
  -> apply(action, nondet_picks)
  -> project(driver)
  -> compare with expected Quint state
```

For `quint run --mbt`, Quint records two fields that the default parser consumes:

- `mbt::actionTaken`: the action selected for the step
- `mbt::nondetPicks`: values selected by relevant `nondet` expressions

The adapter also supports named `quint test` traces that store their observable state and action data at custom nested
paths. The OrderCheckout example demonstrates that contract.

## Quick start

Requirements:

- the MoonBit toolchain installed at `~/.moon/bin`
- Nix with flakes enabled, or local installations of Quint 0.32, `just`, and `rg`

Run the complete validation suite from the repository root:

```sh
nix develop -c just check
```

If all tools are already available on `PATH`:

```sh
just check
```

The command runs formatting checks, all-target MoonBit type checking, 16 unit/contract tests on JavaScript, Wasm, and
native, Quint type checking, a Wasm replay executable, and all example integration controls on native. With the fixed seed used by this
repository, the integration suite checks:

| Example | Positive control | Negative control |
|---|---|---|
| OrderCheckout simulation | 8 traces / 34 states | cancellation produces the wrong terminal state |
| OrderCheckout named test | 1 trace / 2 states | the same cancellation drift through custom paths |
| BankAccount | 8 traces / 72 states | withdrawal debits twice the selected amount |
| CommandSink | 8 traces / 72 actions | the implementation omits the `reset` mapping |

These counts are deterministic regression fixtures, not coverage or proof claims.

## Repository layout

| Path | Responsibility |
|---|---|
| [`adapter.mbt`](adapter.mbt) | ITF types, parsing, path projection, replay, and error boundaries |
| [`generator.mbt`](generator.mbt) | validated `quint run` and `quint test` command construction plus seed precedence |
| [`runner/`](runner/) | native async Quint process execution and temporary ITF collection |
| [`examples/`](examples/) | complete Quint spec + MoonBit driver + executable + negative-control samples |
| [`scripts/check.sh`](scripts/check.sh) | end-to-end regression controls for every example |
| [`justfile`](justfile) | reproducible formatting, type-checking, unit-test, and integration tasks |

The reusable package is `mizchi/quint_connect`. Its ITF decoder and replay kernel are tested on JavaScript, Wasm, and
native targets. Process execution is separated into the native-only `mizchi/quint_connect/runner` package. Native
executables generate traces by starting Quint; the Wasm executable replays ITF supplied by or embedded in its host.

## Core API

### Trace parsing

- `parse_itf(text)` parses standard `quint run --mbt --out-itf` output.
- `parse_itf_with_config(text, config)` additionally projects nested state and custom action data.
- `TraceConfig.state_path` selects the model state that should be decoded by the domain adapter.
- `TraceConfig.nondet_path` selects a custom Quint variant containing the action tag and its arguments.
- `required_nondet` and `optional_nondet` decode named choices after Quint `Some`/`None` normalization.
- `decode_itf_bigint` decodes the canonical ITF `#bigint` representation without precision loss.
- `decode_itf_int` converts an ITF integer only after checking the MoonBit 32-bit `Int` range.

The parser deliberately keeps domain state as `Json`. Every domain adapter must explicitly decode the fields it
compares. This avoids pretending that an unreviewed automatic conversion is part of the trusted contract.

### Stateful replay

`replay` operates on one trace. `replay_suite` operates on multiple traces and constructs a fresh driver for each one.
Both use the same three callbacks:

```moonbit
apply    : (Driver, String, Json) -> Result[Driver, String]
project  : (Driver) -> Snapshot
expected : (Json) -> Result[Snapshot, String]
```

After every trace state, `apply` executes the selected action, `project` extracts the implementation snapshot, and
`expected` decodes the corresponding Quint snapshot. The two snapshots must implement `Eq` and `Debug` and must be
equal at every step.

### Stateless replay

`replay_stateless` executes every action without comparing implementation state. It is useful for command dispatchers,
API clients, and other adapters where only action mapping is observable. It still reports rejected or unknown actions,
but it cannot detect state drift. Prefer stateful replay whenever a meaningful snapshot is available.

### Trace generation

- `RunConfig` describes randomized simulation with `quint run --mbt`.
- `TestConfig` describes a named scenario selected with `quint test --match`.
- `runner.generate_run` and `runner.generate_test` start Quint, collect all generated ITF files, and parse them.
- CLI seed precedence is explicit: command-line seed, then `QUINT_SEED`, then a generated seed.

The runner requires native process and filesystem APIs. A browser or server-side Wasm host must obtain ITF JSON
separately and pass it to `parse_itf` or `parse_itf_with_config`; replay itself does not require native I/O.

The example executables use the TypeScript simulator backend by default. `--backend rust` is accepted by the
OrderCheckout CLI, but the TypeScript backend is the reproducible baseline tested by this repository.

## Failure model

Failures are separated by boundary so that a red test identifies what kind of contract broke:

| Error | Meaning |
|---|---|
| `TraceDecode` | ITF structure, configured path, metadata, or expected-state decoding is invalid |
| `DriverRejected` | the MoonBit driver cannot execute the Quint action or decode its arguments |
| `StateDiverged` | the action ran, but the projected MoonBit state differs from the Quint state |
| `TraceFailed` | one trace in a multi-trace suite failed; the trace index is preserved |
| process error | Quint failed, generated no traces, or an ITF file could not be read |

The integration suite includes deliberate failures for both `DriverRejected` and `StateDiverged`. A positive-only test
would not demonstrate that the mapping and comparison remain load-bearing.

## Examples

See the [examples guide](examples/) for a feature-oriented overview.

| Example | What it teaches |
|---|---|
| [OrderCheckout](examples/order_checkout/) | lifecycle transitions, sets and variants, nondeterministic item selection, generated traces, named traces, and nested projections |
| [BankAccount](examples/bank_account/) | integer arguments, Quint `#bigint` decoding, a minimal state projection, and embedded-ITF Wasm replay |
| [CommandSink](examples/command_sink/) | stateless action replay and detection of an incomplete command mapping |

Each example contains:

- an executable Quint model (`*.qnt`)
- a MoonBit driver that maps actions and decodes expected state
- a runnable native executable under `cmd/`
- MoonBit contract tests
- a deliberate broken mode used by the integration script

BankAccount additionally contains a runnable Wasm executable that replays an embedded trace without the native runner.

## Relationship to official Quint Connect

| Official Rust concept | This MoonBit package | Status |
|---|---|---|
| `Driver::step` | `apply` callback | supported |
| `State::from_driver` | `project` callback | supported |
| generated simulation traces | `RunConfig` + `runner.generate_run` | supported |
| named scenario traces | `TestConfig` + custom trace paths | supported |
| multiple traces | `replay_suite` with a fresh driver per trace | supported |
| nondeterministic value helpers | `required_nondet` / `optional_nondet` | supported manually |
| unit-state driver | `replay_stateless` | supported |
| `QUINT_SEED` | explicit seed resolution and reproduction output | supported |
| Rust `switch!` macro | ordinary MoonBit pattern matching | manual equivalent |
| Rust attribute macros | explicit config and executable code | not implemented |
| Serde-derived typed ITF conversion | domain-specific JSON decoding | not implemented |
| trace shrinking | — | not implemented |

## Guarantees and limitations

What a passing suite means:

- every generated trace was accepted by the driver;
- every selected action and nondeterministic input was mapped successfully;
- every field included in the state projection matched after every checked step.

What it does **not** mean:

- the implementation is formally verified;
- all possible executions were explored;
- fields omitted from the projection are correct;
- real network, clock, concurrency, failure injection, or external I/O semantics were tested;
- the Quint specification itself correctly represents the intended system.

Additional implementation constraints:

- Quint sets, maps, tuples, and variants remain raw ITF JSON until a domain adapter decodes them.
- ITF requires every integer, large or small, to use `{ "#bigint": "..." }`; JSON numbers are rejected by the decoder.
- `decode_itf_bigint` uses MoonBit core `BigInt`, preserving values such as `2^53 + 1` on JavaScript, Wasm, and native.
- `decode_itf_int` is an explicit narrowing operation. Domains that need arbitrary precision should retain `BigInt`
  instead of converting it.
- Action callbacks are synchronous. Async production operations need an additional driver abstraction.
- Quint's `--mbt` metadata is documented as experimental and may change between Quint versions.

## Development commands

```sh
just fmt          # format MoonBit source
just --fmt        # format the justfile
just fmt-check    # verify MoonBit formatting
just typecheck    # all-target MoonBit type checking with warnings denied
just test-js      # 16 unit/contract tests on JavaScript
just test-wasm    # the same 16 tests on Wasm
just test-native  # the same 16 tests on native
just test         # run all three runtime test suites
just wasm-demo    # replay an embedded ITF trace in Wasm
just integration  # generate and replay real Quint traces on native
just check        # run everything
```

## References

- [Quint model-based testing](https://quint.sh/docs/model-based-testing)
- [Quint CLI and `--mbt` metadata](https://quint.sh/docs/quint)
- [Official Quint Connect for Rust](https://github.com/quint-co/quint-connect)
- [Quint Connect announcement](https://quint.sh/posts/quint_connect)
- [Informal Trace Format](https://apalache-mc.org/docs/adr/015adr-trace.html)

## License

Apache-2.0. See [`LICENSE`](LICENSE).
