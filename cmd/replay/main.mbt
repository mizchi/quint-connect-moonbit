///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    abort("usage: replay <trace.itf.json> [--broken-cancel]")
  }
  println("MoonBit Connect trace: \{args[1]}")
  let broken_cancel = args.length() > 2 && args[2] == "--broken-cancel"
  let text = @fs.read_file(args[1]).text()
  let trace = match @quint_connect.parse_itf(text) {
    Ok(trace) => trace
    Err(error) =>
      abort("MoonBit Connect decode failed: \{@debug.to_string(error)}")
  }
  match
    @quint_connect.replay_order(
      trace,
      @quint_connect.new_order_driver(broken_cancel~),
    ) {
    Ok(summary) =>
      println(
        "MoonBit Connect passed: \{summary.states_checked} states matched",
      )
    Err(error) =>
      abort("MoonBit Connect replay failed: \{@debug.to_string(error)}")
  }
}
