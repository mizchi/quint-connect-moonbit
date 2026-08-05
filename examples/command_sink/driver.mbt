///|
pub struct CommandDriver {
  commands_seen : Int
  reject_reset : Bool
}

///|
fn new_command_driver(reject_reset : Bool) -> CommandDriver {
  { commands_seen: 0, reject_reset }
}

///|
fn CommandDriver::apply(
  self : CommandDriver,
  action : String,
  _picks : Json,
) -> Result[CommandDriver, String] {
  match action {
    "init" => Ok({ ..self, commands_seen: 0 })
    "ping" => Ok({ ..self, commands_seen: self.commands_seen + 1 })
    "reset" if self.reject_reset => Err("reset mapping is disabled")
    "reset" => Ok({ ..self, commands_seen: 0 })
    _ => Err("unknown CommandSink action \{action}")
  }
}

///|
pub fn replay_command_suite(
  traces : Array[@quint_connect.ItfTrace],
  reject_reset? : Bool = false,
) -> Result[@quint_connect.ReplaySuiteSummary, @quint_connect.SuiteError] {
  if traces.is_empty() {
    return Err(EmptySuite)
  }
  let mut states_checked = 0
  for trace_index, trace in traces {
    match
      @quint_connect.replay_stateless(trace, new_command_driver(reject_reset), (
        driver,
        action,
        picks,
      ) => driver.apply(action, picks)) {
      Ok(summary) => states_checked += summary.states_checked
      Err(error) => return Err(TraceFailed(trace_index, error))
    }
  }
  Ok({ traces_checked: traces.length(), states_checked })
}
