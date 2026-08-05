///|
/// One state from a Quint Informal Trace Format (ITF) document.
///
/// `value` deliberately keeps the complete JSON state. Domain adapters decode
/// only the observable fields they intend to compare.
pub(all) struct ItfState {
  index : Int
  action : String
  nondet_picks : Json
  value : Json
}

///|
pub(all) struct ItfTrace {
  states : Array[ItfState]
}

///|
pub(all) struct ReplaySummary {
  states_checked : Int
}

///|
pub(all) struct ReplaySuiteSummary {
  traces_checked : Int
  states_checked : Int
}

///|
pub(all) struct TraceConfig {
  state_path : Array[String]
  nondet_path : Array[String]
}

///|
/// Failures are split by boundary so callers can tell malformed traces,
/// driver mapping failures, and actual specification drift apart.
pub(all) enum ConnectError {
  TraceDecode(String)
  DriverRejected(Int, String, String)
  StateDiverged(Int, String, String, String)
} derive(Eq, Debug)

///|
pub(all) enum SuiteError {
  EmptySuite
  TraceFailed(Int, ConnectError)
} derive(Eq, Debug)

///|
fn[T] trace_decode(message : String) -> Result[T, ConnectError] {
  Err(TraceDecode(message))
}

///|
fn decode_index(state : Map[String, Json], fallback : Int) -> Int {
  match state.get("#meta") {
    Some(Object(meta)) =>
      match meta.get("index") {
        Some(Number(index, ..)) => index.to_int()
        _ => fallback
      }
    _ => fallback
  }
}

///|
pub fn default_trace_config() -> TraceConfig {
  { state_path: [], nondet_path: [] }
}

///|
fn value_at_path(
  value : Json,
  path : Array[String],
) -> Result[Json, ConnectError] {
  let mut current = value
  for segment in path {
    guard current is Object(fields) else {
      return trace_decode(
        "cannot read \{segment} from a non-object path segment",
      )
    }
    current = match fields.get(segment) {
      Some(next) => next
      None =>
        return trace_decode("cannot find \{segment} in configured JSON path")
    }
  }
  Ok(current)
}

///|
fn option_value(value : Json) -> Json? {
  match value {
    Object(variant) =>
      match variant.get("tag") {
        Some(String("Some")) => variant.get("value")
        Some(String("None")) => None
        _ => Some(value)
      }
    _ => Some(value)
  }
}

///|
fn normalize_nondet(value : Json) -> Result[Json, ConnectError] {
  guard value is Object(fields) else {
    return trace_decode("nondeterministic picks must be an object")
  }
  let normalized : Map[String, Json] = Map([])
  for name, candidate in fields {
    match option_value(candidate) {
      Some(inner) => normalized[name] = inner
      None => ()
    }
  }
  Ok(Json::object(normalized))
}

///|
pub fn optional_nondet(picks : Json, name : String) -> Result[Json?, String] {
  guard picks is Object(fields) else {
    return Err("nondeterministic picks must be an object")
  }
  Ok(fields.get(name))
}

///|
pub fn required_nondet(picks : Json, name : String) -> Result[Json, String] {
  match optional_nondet(picks, name) {
    Ok(Some(value)) => Ok(value)
    Ok(None) => Err("unknown nondeterministic pick \{name}")
    Err(reason) => Err(reason)
  }
}

///|
fn decode_itf_state(
  value : Json,
  fallback_index : Int,
  config : TraceConfig,
) -> Result[ItfState, ConnectError] {
  guard value is Object(state) else {
    return trace_decode("states[\{fallback_index}] must be an object")
  }
  let (action, nondet_picks) = if config.nondet_path.is_empty() {
    let action = match state.get("mbt::actionTaken") {
      Some(String(action)) => action
      _ =>
        return trace_decode(
          "states[\{fallback_index}] is missing mbt::actionTaken",
        )
    }
    let picks = match state.get("mbt::nondetPicks") {
      Some(picks) => picks
      None =>
        return trace_decode(
          "states[\{fallback_index}] is missing mbt::nondetPicks",
        )
    }
    let picks = match normalize_nondet(picks) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    (action, picks)
  } else {
    let encoded = match value_at_path(value, config.nondet_path) {
      Ok(Object(encoded)) => encoded
      Ok(_) =>
        return trace_decode(
          "configured nondet path must contain a variant object",
        )
      Err(error) => return Err(error)
    }
    let action = match encoded.get("tag") {
      Some(String(action)) => action
      _ => return trace_decode("custom nondet variant is missing a string tag")
    }
    let picks = match encoded.get("value") {
      Some(Object(tuple)) if tuple.get("#tup") is Some(Array(items)) &&
        items.is_empty() => Json::object({})
      Some(value) =>
        match normalize_nondet(value) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
      None => return trace_decode("custom nondet variant is missing value")
    }
    (action, picks)
  }
  if action.is_empty() {
    return trace_decode(
      "states[\{fallback_index}] contains an anonymous action",
    )
  }
  let projected = if config.state_path.is_empty() {
    let fields = state.copy()
    fields.remove("#meta")
    fields.remove("mbt::actionTaken")
    fields.remove("mbt::nondetPicks")
    Json::object(fields)
  } else {
    match value_at_path(value, config.state_path) {
      Ok(projected) => projected
      Err(error) => return Err(error)
    }
  }
  Ok({
    index: decode_index(state, fallback_index),
    action,
    nondet_picks,
    value: projected,
  })
}

///|
/// Parse the JSON ITF emitted by `quint run --mbt --out-itf`.
pub fn parse_itf(text : String) -> Result[ItfTrace, ConnectError] {
  parse_itf_with_config(text, default_trace_config())
}

///|
/// Parse ITF while projecting nested state and/or custom sum-type action data.
pub fn parse_itf_with_config(
  text : String,
  config : TraceConfig,
) -> Result[ItfTrace, ConnectError] {
  let document = @json.parse(text) catch {
    error => return trace_decode("invalid JSON: \{error}")
  }
  guard document is Object(root) else {
    return trace_decode("ITF root must be an object")
  }
  guard root.get("states") is Some(Array(states)) else {
    return trace_decode("ITF root is missing states")
  }
  if states.is_empty() {
    return trace_decode("ITF trace must contain at least one state")
  }
  let decoded : Array[ItfState] = []
  for index, state in states {
    match decode_itf_state(state, index, config) {
      Ok(value) => decoded.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok({ states: decoded })
}

///|
/// Language-neutral replay kernel.
///
/// The three callbacks are the adapter contract:
///
/// - `apply` maps a Quint action and nondeterministic choices to implementation code
/// - `project` extracts only the implementation state intended for comparison
/// - `expected` decodes the corresponding projection from the Quint ITF state
pub fn[D, S : Eq + @debug.Debug] replay(
  trace : ItfTrace,
  initial_driver : D,
  apply : (D, String, Json) -> Result[D, String],
  project : (D) -> S,
  expected : (Json) -> Result[S, String],
) -> Result[ReplaySummary, ConnectError] {
  let mut driver = initial_driver
  for state in trace.states {
    driver = match apply(driver, state.action, state.nondet_picks) {
      Ok(next) => next
      Err(reason) =>
        return Err(DriverRejected(state.index, state.action, reason))
    }
    let expected_state = match expected(state.value) {
      Ok(value) => value
      Err(reason) => return trace_decode("states[\{state.index}]: \{reason}")
    }
    let actual_state = project(driver)
    if actual_state != expected_state {
      return Err(
        StateDiverged(
          state.index,
          state.action,
          @debug.to_string(expected_state),
          @debug.to_string(actual_state),
        ),
      )
    }
  }
  Ok({ states_checked: trace.states.length() })
}

///|
/// Replay actions without comparing state. This mirrors Connect's unit-state mode.
pub fn[D] replay_stateless(
  trace : ItfTrace,
  initial_driver : D,
  apply : (D, String, Json) -> Result[D, String],
) -> Result[ReplaySummary, ConnectError] {
  replay(trace, initial_driver, apply, _ => (), _ => Ok(()))
}

///|
/// Replay multiple traces, creating a fresh driver for every trace.
pub fn[D, S : Eq + @debug.Debug] replay_suite(
  traces : Array[ItfTrace],
  new_driver : () -> D,
  apply : (D, String, Json) -> Result[D, String],
  project : (D) -> S,
  expected : (Json) -> Result[S, String],
) -> Result[ReplaySuiteSummary, SuiteError] {
  if traces.is_empty() {
    return Err(EmptySuite)
  }
  let mut states_checked = 0
  for trace_index, trace in traces {
    match replay(trace, new_driver(), apply, project, expected) {
      Ok(summary) => states_checked += summary.states_checked
      Err(error) => return Err(TraceFailed(trace_index, error))
    }
  }
  Ok({ traces_checked: traces.length(), states_checked })
}
