# BankAccount

BankAccount is a compact stateful example focused on nondeterministic action arguments and integer decoding. Quint
chooses deposit and withdrawal amounts; the MoonBit driver executes the same operations and compares the balance after
every step.

Use this example when your implementation has a small, stable observable state and actions whose arguments come from
Quint `nondet` choices.

## Domain model

[`BankAccount.qnt`](BankAccount.qnt) defines one state variable:

- `balance: int`, initialized to `4`.

At every step Quint selects an amount from `{1, 2}` and then selects one enabled action:

- `deposit(amount)` adds the amount;
- `withdraw(amount)` subtracts the amount when sufficient funds are available.

The model declares `nonNegative = balance >= 0`. The integration suite type-checks the specification and generates valid
simulation traces, but it does not run exhaustive model checking for this invariant. The purpose of this example is
implementation conformance, not a proof of the bank model.

## MoonBit driver

[`driver.mbt`](driver.mbt) contains four important pieces:

1. `decode_amount` reads the selected `amount` from `mbt::nondetPicks`.
2. `BankDriver::apply` maps `init`, `deposit`, and `withdraw` to implementation updates.
3. `decode_balance` extracts the expected balance from each Quint state.
4. `replay_bank_suite` compares the MoonBit integer balance after every action in every trace.

Quint integers in ITF are encoded as tagged JSON objects, for example:

```json
{ "#bigint": "4" }
```

The core package's `decode_itf_bigint` reads this representation without precision loss on JavaScript or native.
BankAccount then uses `decode_itf_int`, which rejects values outside MoonBit's 32-bit `Int` range before narrowing.

## Run the example

From the repository root:

```sh
nix develop -c moon run --target native examples/bank_account/cmd
```

Expected result with the fixed seed `0x1234`:

```text
BankAccount passed: 8 traces, 72 states matched
```

Each trace starts with a fresh `BankDriver`. Quint chooses the action and amount; MoonBit performs the update; the
resulting balance must equal the balance stored in the trace.

## Run replay on Wasm

The Wasm executable cannot start Quint because the portable replay package has no process or filesystem dependency.
Instead, it demonstrates the deployment boundary by parsing and replaying an embedded ITF document:

```sh
nix develop -c moon run --target wasm examples/bank_account/wasm
```

Expected result:

```text
Wasm BankAccount passed: 1 trace, 2 states matched
```

In a browser or server-side Wasm application, the host can fetch or receive ITF JSON and pass its text to the same
`parse_itf` and `replay_bank_suite` APIs.

## Negative control

```sh
nix develop -c moon run --target native examples/bank_account/cmd -- --broken-withdraw
```

The broken driver subtracts twice the selected withdrawal amount. The first generated withdrawal must fail with
`StateDiverged`.

In domain terms: **the implementation debited the account twice even though the model authorized one withdrawal**.
Because `balance` is the observable projection, the mismatch is detected immediately after that action.

## Files

| File | Purpose |
|---|---|
| [`BankAccount.qnt`](BankAccount.qnt) | state and action model |
| [`driver.mbt`](driver.mbt) | amount decoding, implementation transitions, and balance projection |
| [`driver_test.mbt`](driver_test.mbt) | hand-written ITF positive/negative contract tests |
| [`cmd/main.mbt`](cmd/main.mbt) | fixed-seed trace generation and replay executable |
| [`wasm/main.mbt`](wasm/main.mbt) | process-free Wasm replay executable with embedded ITF |

## Scope of the check

Only `balance` is compared. The example does not include accounts, a transaction ledger, idempotency keys, transfer
authorization, persistence, or external payment effects. If those fields determine correctness in a real system, they
must be represented in both the Quint model and the MoonBit projection.
