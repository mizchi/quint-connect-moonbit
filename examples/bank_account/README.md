# BankAccount

入出金額をQuintがnondeterministically選び、MoonBit実装の残高と各stepで比較するstateful example。
Quint ITFのintegerは `{ "#bigint": "4" }` のようにencodeされるため、driver boundaryで明示decodeする。

```sh
moon run examples/bank_account/cmd
```

fixed seed `0x1234`では8 traces / 72 statesを比較する。次のnegative controlはwithdraw額を
二重に引き、最初の該当stepで`StateDiverged`になる。

```sh
moon run examples/bank_account/cmd -- --broken-withdraw
```

| 層 | ファイル |
|---|---|
| spec | [`BankAccount.qnt`](BankAccount.qnt) |
| driver / projection | [`driver.mbt`](driver.mbt) |
| executable | [`cmd/main.mbt`](cmd/main.mbt) |
| contract test | [`driver_test.mbt`](driver_test.mbt) |

このexampleが比較するobservable stateは`balance`だけである。ledger entryや外部送金effectまで
検査する場合は、specとprojectionの両方へそのstateを追加する必要がある。
