///|
async fn main {
  let reject_reset = @env.args().any(arg => arg == "--reject-reset")
  let config : @quint_connect.RunConfig = {
    spec: "examples/command_sink/CommandSink.qnt",
    main: Some("CommandSink"),
    init: None,
    step: None,
    max_samples: Some(8),
    max_steps: Some(8),
    backend: Some("typescript"),
    seed: "0x1234",
  }
  let batch = match @runner.generate_run(config) {
    Ok(batch) => batch
    Err(reason) => abort("CommandSink generation failed: \{reason}")
  }
  let result = @command_sink.replay_command_suite(batch.traces, reject_reset~)
  @runner.cleanup(batch.temp_dir)
  match result {
    Ok(summary) =>
      println(
        "CommandSink passed: \{summary.traces_checked} traces, \{summary.states_checked} actions executed",
      )
    Err(error) => abort("CommandSink replay failed: \{@debug.to_string(error)}")
  }
}
