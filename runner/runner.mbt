///|
pub struct TraceBatch {
  seed : String
  temp_dir : String
  files : Array[String]
  traces : Array[@quint_connect.ItfTrace]
}

///|
pub async fn cleanup(temp_dir : String) -> Unit {
  if @fs.exists(temp_dir) {
    @fs.rmdir(temp_dir, recursive=true)
  }
}

///|
async fn[T] fail_after_cleanup(
  temp_dir : String,
  message : String,
) -> Result[T, String] {
  cleanup(temp_dir)
  Err(message)
}

///|
async fn generate(
  args : Array[String],
  seed : String,
  temp_dir : String,
  trace_config : @quint_connect.TraceConfig,
) -> Result[TraceBatch, String] {
  let (exit_code, _stdout, stderr) = @process.collect_output("quint", args)
  if exit_code != 0 {
    return fail_after_cleanup(
      temp_dir,
      "Quint exited with code \{exit_code}: \{stderr.text()}",
    )
  }
  let files = @fs.readdir(temp_dir, sort=true).filter(name => {
    name.has_suffix(".itf.json")
  })
  if files.is_empty() {
    return fail_after_cleanup(temp_dir, "Quint generated zero ITF traces")
  }
  let traces : Array[@quint_connect.ItfTrace] = []
  for name in files {
    let path = "\{temp_dir}/\{name}"
    let text = @fs.read_file(path).text()
    match @quint_connect.parse_itf_with_config(text, trace_config) {
      Ok(trace) => traces.push(trace)
      Err(error) =>
        return fail_after_cleanup(
          temp_dir,
          "Failed to decode \{name}: \{@debug.to_string(error)}",
        )
    }
  }
  Ok({ seed, temp_dir, files, traces })
}

///|
pub async fn generate_run(
  config : @quint_connect.RunConfig,
  trace_config? : @quint_connect.TraceConfig = @quint_connect.default_trace_config(),
) -> Result[TraceBatch, String] {
  let temp_dir = @fs.tmpdir(prefix="/quint-connect-moonbit")
  let out_pattern = "\{temp_dir}/run_{seq}.itf.json"
  let args = match config.quint_args(out_pattern) {
    Ok(args) => args
    Err(reason) => return fail_after_cleanup(temp_dir, reason)
  }
  generate(args, config.seed, temp_dir, trace_config)
}

///|
pub async fn generate_test(
  config : @quint_connect.TestConfig,
  trace_config? : @quint_connect.TraceConfig = @quint_connect.default_trace_config(),
) -> Result[TraceBatch, String] {
  let temp_dir = @fs.tmpdir(prefix="/quint-connect-moonbit")
  let out_pattern = "\{temp_dir}/test_{seq}.itf.json"
  let args = match config.quint_args(out_pattern) {
    Ok(args) => args
    Err(reason) => return fail_after_cleanup(temp_dir, reason)
  }
  generate(args, config.seed, temp_dir, trace_config)
}
