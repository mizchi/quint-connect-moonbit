# OrderCheckout

OrderCheckout is the most complete example in this repository. It models an order lifecycle, maps the model to a
MoonBit implementation, and exercises both randomized simulation traces and a deterministic named scenario.

Use this example to learn how to connect:

- Quint variants to a MoonBit enum;
- Quint sets to an order-independent implementation snapshot;
- nondeterministic model choices to implementation arguments;
- nested model state and a custom action variant to `TraceConfig` paths;
- multiple traces to a fresh implementation driver for every trace.

## Domain model

[`OrderCheckout.qnt`](OrderCheckout.qnt) defines these lifecycle states:

```text
Cart -> PaymentPending
PaymentPending -> Cart | Paid | Cancelled
Paid -> Shipped
Paid | Shipped -> Refunded
Cart -> Cancelled
```

Its observable state contains:

- `state`: the current `OrderState` variant;
- `cart`: a set containing zero, one, or two sample item identifiers;
- `refunded`: whether a refund has been recorded.

The `step` action can add an item, start checkout, resolve or time out payment, ship, refund, or cancel. `addItem` uses a
Quint `nondet` choice named `candidate`, so the generated trace contains the exact item that the MoonBit driver must add.

[`OrderCheckoutNamed.qnt`](OrderCheckoutNamed.qnt) contains a smaller deterministic scenario:

```text
Init -> CancelCart
```

It deliberately stores the observable state under `model` and the action under the custom sum type `actionTaken`. This
shows how `quint test` output can be replayed without relying on the default `mbt::*` fields.

## MoonBit driver

[`driver.mbt`](driver.mbt) implements the application side of the contract:

- `OrderDriver::apply` maps every Quint action to a MoonBit state transition.
- `required_nondet(..., "candidate")` retrieves the selected item for `addItem`.
- `OrderDriver::snapshot` projects implementation state to `OrderSnapshot`.
- `decode_order_snapshot` decodes the matching state from ITF JSON.
- `replay_order_suite` constructs a fresh `OrderDriver` for every generated trace.

The Quint cart is a mathematical set. The MoonBit snapshot encodes the two possible items as a bit mask so comparison is
independent of JSON array order.

## Run randomized simulation traces

Enter the development shell at the repository root:

```sh
nix develop
```

Then run:

```sh
moon run --target native examples/order_checkout/cmd run \
  examples/order_checkout/OrderCheckout.qnt \
  --main OrderCheckout \
  --max-samples 8 \
  --max-steps 8 \
  --seed 0x1234
```

Expected result:

```text
MoonBit Connect passed: 8 traces, 34 states matched
```

The executable asks Quint to generate eight `--mbt` traces, decodes `mbt::actionTaken` and `mbt::nondetPicks`, replays
all actions, and compares `OrderSnapshot` after every step.

## Run the named nested-state scenario

```sh
moon run --target native examples/order_checkout/cmd test \
  examples/order_checkout/OrderCheckoutNamed.qnt \
  --main OrderCheckoutNamed \
  --test cancelTest \
  --state-path model \
  --nondet-path actionTaken \
  --seed 0x1234
```

Expected result:

```text
MoonBit Connect passed: 1 traces, 2 states matched
```

`--state-path model` selects the nested observable state. `--nondet-path actionTaken` selects a Quint variant whose tag
is treated as the action name and whose value contains its arguments.

## Negative control

Add `--broken-cancel` to either command. The broken MoonBit driver marks a cancelled cart as `Refunded` and sets the
refund flag, while the Quint model expects `Cancelled` with no refund.

The command must exit unsuccessfully with a diagnostic equivalent to:

```text
StateDiverged(..., "cancelCart", ...Cancelled..., ...Refunded...)
```

In domain terms: **cancelling an unpaid cart was implemented as if money had been refunded**. This also demonstrates that
the lifecycle state and refund flag remain part of the observable projection.

## Files

| File | Purpose |
|---|---|
| [`OrderCheckout.qnt`](OrderCheckout.qnt) | randomized lifecycle model |
| [`OrderCheckoutNamed.qnt`](OrderCheckoutNamed.qnt) | deterministic nested-state scenario |
| [`driver.mbt`](driver.mbt) | action mapping, ITF decoding, and state projection |
| [`driver_test.mbt`](driver_test.mbt) | small positive/negative contract test |
| [`cmd/main.mbt`](cmd/main.mbt) | configurable `run` / `test` executable |
| [`replay/main.mbt`](replay/main.mbt) | replay an already generated ITF file |

## Scope of the check

The example compares lifecycle state, cart membership, and the refund flag. It does not model a payment provider,
inventory service, shipping system, retries, clocks, or concurrent requests. A production adapter would need to decide
which of those effects are part of the observable contract and how to make them deterministic during replay.
