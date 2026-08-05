# OrderCheckout

注文のlifecycleを扱うstateful example。Quintのvariant `OrderState`、itemのset、
nondeterministic `candidate`をMoonBitの`OrderDriver`へ写す。

このexampleは2つのtrace contractを示す。

- `quint run --mbt`: `mbt::actionTaken` / `mbt::nondetPicks`を使う複数trace
- `quint test`: nested `model` stateとcustom sum-type `actionTaken`を使うnamed trace

```sh
moon run examples/order_checkout/cmd run \
  examples/order_checkout/OrderCheckout.qnt \
  --main OrderCheckout --max-samples 8 --max-steps 8 --seed 0x1234

moon run examples/order_checkout/cmd test \
  examples/order_checkout/OrderCheckoutNamed.qnt \
  --main OrderCheckoutNamed --test cancelTest \
  --state-path model --nondet-path actionTaken --seed 0x1234
```

`--broken-cancel`を加えた実行は失敗し、Quintの`Cancelled`とMoonBitの`Refunded`の差を
`StateDiverged`として報告する。

| 層 | ファイル |
|---|---|
| spec | [`OrderCheckout.qnt`](OrderCheckout.qnt)、[`OrderCheckoutNamed.qnt`](OrderCheckoutNamed.qnt) |
| driver / projection | [`driver.mbt`](driver.mbt) |
| executable | [`cmd/main.mbt`](cmd/main.mbt) |
| contract test | [`driver_test.mbt`](driver_test.mbt) |
