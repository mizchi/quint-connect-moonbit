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
fn main {
  let trace = match @quint_connect.parse_itf(bank_trace_fixture()) {
    Ok(trace) => trace
    Err(error) => abort("Wasm ITF decode failed: \{@debug.to_string(error)}")
  }
  match @bank_account.replay_bank_suite([trace]) {
    Ok(summary) =>
      println(
        "Wasm BankAccount passed: \{summary.traces_checked} trace, \{summary.states_checked} states matched",
      )
    Err(error) =>
      abort("Wasm BankAccount replay failed: \{@debug.to_string(error)}")
  }
}
