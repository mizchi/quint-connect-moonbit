# CommandSink

実装stateをQuint stateと比較せず、生成されたactionをすべて実行できることだけを検査する
`replay_stateless` example。外部API clientやcommand dispatcherのmapping smoke testに相当する。

```sh
moon run examples/command_sink/cmd
```

fixed seed `0x1234`では8 traces / 72 actionsを実行する。次のnegative controlは`reset` mappingを
意図的に拒否し、`DriverRejected`になる。

```sh
moon run examples/command_sink/cmd -- --reject-reset
```

| 層 | ファイル |
|---|---|
| spec | [`CommandSink.qnt`](CommandSink.qnt) |
| driver | [`driver.mbt`](driver.mbt) |
| executable | [`cmd/main.mbt`](cmd/main.mbt) |
| contract test | [`driver_test.mbt`](driver_test.mbt) |

stateless replayはaction mappingを検査するが、実装stateのdriftは検出しない。比較できるstateがある場合は
`replay_suite`とprojectionを優先する。
