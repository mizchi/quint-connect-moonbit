///|
const DEFAULT_TRACES : Int = 100

///|
pub(all) struct RunConfig {
  spec : String
  main : String?
  init : String?
  step : String?
  max_samples : Int?
  max_steps : Int?
  backend : String?
  seed : String
}

///|
pub(all) struct TestConfig {
  spec : String
  main : String?
  test_name : String
  max_samples : Int?
  backend : String?
  seed : String
}

///|
fn validate_common(
  spec : String,
  seed : String,
  max_samples : Int?,
) -> Result[Int, String] {
  if spec.is_empty() {
    return Err("spec path must not be empty")
  }
  if seed.is_empty() {
    return Err("seed must not be empty")
  }
  let samples = max_samples.unwrap_or(DEFAULT_TRACES)
  if samples <= 0 {
    return Err("max_samples must be positive")
  }
  Ok(samples)
}

///|
fn append_option(args : Array[String], name : String, value : String?) -> Unit {
  match value {
    Some(value) => {
      args.push(name)
      args.push(value)
    }
    None => ()
  }
}

///|
fn validate_backend(backend : String?) -> Result[Unit, String] {
  match backend {
    Some("typescript") | Some("rust") | None => Ok(())
    Some(value) => Err("unsupported Quint backend \{value}")
  }
}

///|
pub fn RunConfig::quint_args(
  self : RunConfig,
  out_pattern : String,
) -> Result[Array[String], String] {
  let samples = match validate_common(self.spec, self.seed, self.max_samples) {
    Ok(samples) => samples
    Err(reason) => return Err(reason)
  }
  if out_pattern.is_empty() {
    return Err("output pattern must not be empty")
  }
  match self.max_steps {
    Some(steps) if steps <= 0 => return Err("max_steps must be positive")
    _ => ()
  }
  match validate_backend(self.backend) {
    Err(reason) => return Err(reason)
    Ok(_) => ()
  }
  let sample_text = samples.to_string()
  let args = [
    "run",
    self.spec,
    "--seed",
    self.seed,
    "--max-samples",
    sample_text,
    "--n-traces",
    sample_text,
    "--out-itf",
    out_pattern,
    "--mbt",
    "--verbosity",
    "0",
  ]
  append_option(args, "--main", self.main)
  append_option(args, "--init", self.init)
  append_option(args, "--step", self.step)
  append_option(
    args,
    "--max-steps",
    self.max_steps.map(value => value.to_string()),
  )
  append_option(args, "--backend", self.backend)
  Ok(args)
}

///|
pub fn TestConfig::quint_args(
  self : TestConfig,
  out_pattern : String,
) -> Result[Array[String], String] {
  let samples = match validate_common(self.spec, self.seed, self.max_samples) {
    Ok(samples) => samples
    Err(reason) => return Err(reason)
  }
  if self.test_name.is_empty() {
    return Err("test name must not be empty")
  }
  if out_pattern.is_empty() {
    return Err("output pattern must not be empty")
  }
  match validate_backend(self.backend) {
    Err(reason) => return Err(reason)
    Ok(_) => ()
  }
  let args = [
    "test",
    self.spec,
    "--seed",
    self.seed,
    "--match",
    "^\{self.test_name}$",
    "--max-samples",
    samples.to_string(),
    "--out-itf",
    out_pattern,
    "--verbosity",
    "0",
  ]
  append_option(args, "--main", self.main)
  append_option(args, "--backend", self.backend)
  Ok(args)
}

///|
/// CLI seed takes precedence, followed by QUINT_SEED, then a generated seed.
pub fn resolve_seed(
  cli_seed : String?,
  env_seed : String?,
  generated_seed : String,
) -> Result[String, String] {
  let seed = match cli_seed {
    Some(seed) => seed
    None => env_seed.unwrap_or(generated_seed)
  }
  if seed.is_empty() {
    Err("seed must not be empty")
  } else {
    Ok(seed)
  }
}
