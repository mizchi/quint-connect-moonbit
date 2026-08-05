///|
fn bank_trace_fixture() -> String {
  (
    #|{
    #|  "states": [
    #|    {
    #|      "#meta": { "index": 0 },
    #|      "mbt::actionTaken": "init",
    #|      "mbt::nondetPicks": {},
    #|      "balance": { "#bigint": "4" }
    #|    },
    #|    {
    #|      "#meta": { "index": 1 },
    #|      "mbt::actionTaken": "withdraw",
    #|      "mbt::nondetPicks": {
    #|        "amount": { "tag": "Some", "value": { "#bigint": "2" } }
    #|      },
    #|      "balance": { "#bigint": "2" }
    #|    }
    #|  ]
    #|}
  )
}

///|
test "BankAccount example replays nondeterministic amounts" {
  let trace = @quint_connect.parse_itf(bank_trace_fixture()).unwrap()
  let summary = @bank_account.replay_bank_suite([trace]).unwrap()
  assert_eq(summary.states_checked, 2)
}

///|
test "BankAccount example detects a broken withdrawal" {
  let trace = @quint_connect.parse_itf(bank_trace_fixture()).unwrap()
  match @bank_account.replay_bank_suite([trace], broken_withdraw=true) {
    Err(TraceFailed(_, StateDiverged(_, "withdraw", "2", "0"))) => ()
    _ => fail("double withdrawal must diverge from the Quint balance")
  }
}
