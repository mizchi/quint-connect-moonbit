///|
fn command_trace_fixture() -> String {
  (
    #|{
    #|  "states": [
    #|    {
    #|      "#meta": { "index": 0 },
    #|      "mbt::actionTaken": "init",
    #|      "mbt::nondetPicks": {},
    #|      "commandsSeen": 0
    #|    },
    #|    {
    #|      "#meta": { "index": 1 },
    #|      "mbt::actionTaken": "ping",
    #|      "mbt::nondetPicks": {},
    #|      "commandsSeen": 1
    #|    },
    #|    {
    #|      "#meta": { "index": 2 },
    #|      "mbt::actionTaken": "reset",
    #|      "mbt::nondetPicks": {},
    #|      "commandsSeen": 0
    #|    }
    #|  ]
    #|}
  )
}

///|
test "CommandSink example executes a stateless trace" {
  let trace = @quint_connect.parse_itf(command_trace_fixture()).unwrap()
  let summary = @command_sink.replay_command_suite([trace]).unwrap()
  assert_eq(summary.states_checked, 3)
}

///|
test "CommandSink example rejects a missing command mapping" {
  let trace = @quint_connect.parse_itf(command_trace_fixture()).unwrap()
  match @command_sink.replay_command_suite([trace], reject_reset=true) {
    Err(TraceFailed(_, DriverRejected(2, "reset", _))) => ()
    _ => fail("a missing reset mapping must be reported as DriverRejected")
  }
}
