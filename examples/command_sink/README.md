# CommandSink

CommandSink demonstrates stateless replay. The adapter executes every action selected by Quint but intentionally does
not compare implementation state with model state.

This pattern is useful for a command dispatcher, external API client, hardware adapter, or smoke-test harness where the
main question is: **can every modeled action be translated into a valid implementation call?**

Use stateful replay instead when a meaningful deterministic snapshot can be observed.

## Domain model

[`CommandSink.qnt`](CommandSink.qnt) defines two commands:

- `ping` increments the model's `commandsSeen` counter;
- `reset` sets the counter back to zero.

The counter gives Quint a concrete state machine from which to generate traces. The MoonBit replay deliberately ignores
its value: this example checks only that `init`, `ping`, and `reset` are all recognized and executable.

## MoonBit driver

[`driver.mbt`](driver.mbt) maps the action names to a small `CommandDriver`. `replay_command_suite` iterates over all
traces and calls the core package's `replay_stateless` function for each one.

`replay_stateless` still executes the `apply` callback and therefore still reports:

- an unknown action;
- missing or malformed arguments;
- an implementation precondition failure;
- a deliberately rejected mapping.

It does **not** invoke an expected-state decoder or compare an implementation snapshot.

## Run the example

From the repository root:

```sh
nix develop -c moon run examples/command_sink/cmd
```

Expected result with the fixed seed `0x1234`:

```text
CommandSink passed: 8 traces, 72 actions executed
```

The result counts executed trace states as actions, including each trace's `init` action.

## Negative control

```sh
nix develop -c moon run examples/command_sink/cmd -- --reject-reset
```

The broken driver refuses to map `reset`. The generated trace reaches that action and fails with:

```text
DriverRejected(..., "reset", "reset mapping is disabled")
```

In domain terms: **the specification permits resetting the sink, but the implementation adapter has no working reset
operation**. This proves that stateless replay can detect an incomplete action mapping even though it cannot detect
incorrect internal state.

## Files

| File | Purpose |
|---|---|
| [`CommandSink.qnt`](CommandSink.qnt) | command state machine used for trace generation |
| [`driver.mbt`](driver.mbt) | stateless action mapping and suite wrapper |
| [`driver_test.mbt`](driver_test.mbt) | hand-written positive and missing-mapping tests |
| [`cmd/main.mbt`](cmd/main.mbt) | fixed-seed trace generation and replay executable |

## Scope of the check

This example cannot detect a wrong command counter, an incorrect API response, or any other state drift because state
comparison is intentionally disabled. In a real integration, use stateless replay only when action acceptance is the
actual contract or when implementation state is genuinely unavailable.
