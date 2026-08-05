///|
let usage =
  #|usage:
  #|  connect run <spec.qnt> [--main NAME] [--init NAME] [--step NAME]
  #|    [--max-samples N] [--max-steps N] [--seed SEED]
  #|    [--backend typescript|rust] (default: typescript)
  #|    [--state-path A.B] [--nondet-path A.B]
  #|    [--broken-cancel] [--keep-traces]
  #|  connect test <spec.qnt> --test NAME [--main NAME]
  #|    [--max-samples N] [--seed SEED]
  #|    [--backend typescript|rust] (default: typescript)
  #|    [--state-path A.B] [--nondet-path A.B]
  #|    [--broken-cancel] [--keep-traces]

///|
fn option_value(
  args : ArrayView[String],
  name : String,
) -> Result[String?, String] {
  for index, arg in args {
    if arg == name {
      if index + 1 >= args.length() || args[index + 1].has_prefix("--") {
        return Err("\{name} requires a value")
      }
      return Ok(Some(args[index + 1]))
    }
  }
  Ok(None)
}

///|
fn has_flag(args : ArrayView[String], name : String) -> Bool {
  args.any(arg => arg == name)
}

///|
fn parse_positive(value : String?, name : String) -> Result[Int?, String] {
  match value {
    None => Ok(None)
    Some(value) => {
      let parsed = @string.parse_int(value) catch {
        _ => return Err("\{name} must be a positive integer")
      }
      if parsed > 0 {
        Ok(Some(parsed))
      } else {
        Err("\{name} must be a positive integer")
      }
    }
  }
}

///|
fn parse_path(value : String?) -> Array[String] {
  match value {
    None => []
    Some("") => []
    Some(path) => path.split(".").map(part => part.to_owned()).to_array()
  }
}

///|
fn validate_options(
  args : ArrayView[String],
  mode : String,
) -> Result[Unit, String] {
  let value_options = if mode == "run" {
    Set::from_array([
      "--main", "--init", "--step", "--max-samples", "--max-steps", "--seed", "--state-path",
      "--nondet-path", "--backend",
    ])
  } else {
    Set::from_array([
      "--test", "--main", "--max-samples", "--seed", "--state-path", "--nondet-path",
      "--backend",
    ])
  }
  let flags = Set::from_array(["--broken-cancel", "--keep-traces"])
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if value_options.contains(arg) {
      if index + 1 >= args.length() || args[index + 1].has_prefix("--") {
        return Err("\{arg} requires a value")
      }
      index += 2
    } else if flags.contains(arg) {
      index += 1
    } else {
      return Err("unknown option \{arg}")
    }
  }
  Ok(())
}

///|
fn generated_seed() -> String {
  let value = @random.Rand::new().uint()
  "0x\{value.to_string(radix=16)}"
}

///|
fn print_verbose_traces(
  traces : Array[@quint_connect.ItfTrace],
  verbose : Bool,
) -> Unit {
  if verbose {
    for index, trace in traces {
      let actions = trace.states.map(state => state.action).join(" -> ")
      println("[Trace \{index + 1}] \{actions}")
    }
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 3 || (args[1] != "run" && args[1] != "test") {
    abort(usage)
  }
  let mode = args[1]
  let spec = args[2]
  let options = args[3:]
  match validate_options(options, mode) {
    Err(reason) => abort("\{reason}\n\n\{usage}")
    Ok(_) => ()
  }
  let cli_seed = option_value(options, "--seed").unwrap()
  let seed = @quint_connect.resolve_seed(
    cli_seed,
    @env.get_env_var("QUINT_SEED"),
    generated_seed(),
  ).unwrap()
  let max_samples = parse_positive(
    option_value(options, "--max-samples").unwrap(),
    "--max-samples",
  ).unwrap()
  let backend = match option_value(options, "--backend").unwrap() {
    Some(value) => Some(value)
    None => Some("typescript")
  }
  let trace_config : @quint_connect.TraceConfig = {
    state_path: parse_path(option_value(options, "--state-path").unwrap()),
    nondet_path: parse_path(option_value(options, "--nondet-path").unwrap()),
  }
  println("MoonBit Connect mode: \{mode}")
  println("MoonBit Connect seed: \{seed}")
  let batch = if mode == "run" {
    let config : @quint_connect.RunConfig = {
      spec,
      main: option_value(options, "--main").unwrap(),
      init: option_value(options, "--init").unwrap(),
      step: option_value(options, "--step").unwrap(),
      max_samples,
      max_steps: parse_positive(
        option_value(options, "--max-steps").unwrap(),
        "--max-steps",
      ).unwrap(),
      backend,
      seed,
    }
    @runner.generate_run(config, trace_config~)
  } else {
    let test_name = match option_value(options, "--test").unwrap() {
      Some(name) => name
      None => abort("test mode requires --test\n\n\{usage}")
    }
    let config : @quint_connect.TestConfig = {
      spec,
      main: option_value(options, "--main").unwrap(),
      test_name,
      max_samples,
      backend,
      seed,
    }
    @runner.generate_test(config, trace_config~)
  }
  let batch = match batch {
    Ok(batch) => batch
    Err(reason) => abort("MoonBit Connect generation failed: \{reason}")
  }
  let keep_traces = has_flag(options, "--keep-traces")
  let verbose = match @env.get_env_var("QUINT_VERBOSE") {
    Some("0") | None => false
    _ => true
  }
  print_verbose_traces(batch.traces, verbose)
  let result = @quint_connect.replay_order_suite(
    batch.traces,
    broken_cancel=has_flag(options, "--broken-cancel"),
  )
  if keep_traces {
    println("MoonBit Connect traces kept at: \{batch.temp_dir}")
  } else {
    @runner.cleanup(batch.temp_dir)
  }
  match result {
    Ok(summary) =>
      println(
        "MoonBit Connect passed: \{summary.traces_checked} traces, \{summary.states_checked} states matched",
      )
    Err(TraceFailed(trace_index, error)) => {
      let file = batch.files.get(trace_index).unwrap_or("<unknown trace>")
      abort(
        "MoonBit Connect replay failed in \{file}: \{@debug.to_string(error)}\nReproduce with QUINT_SEED=\{seed}",
      )
    }
    Err(EmptySuite) => abort("MoonBit Connect replay failed: empty trace suite")
  }
}
