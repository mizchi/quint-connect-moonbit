///|
async fn main {
  let broken_withdraw = @env.args().any(arg => arg == "--broken-withdraw")
  let config : @quint_connect.RunConfig = {
    spec: "examples/bank_account/BankAccount.qnt",
    main: Some("BankAccount"),
    init: None,
    step: None,
    max_samples: Some(8),
    max_steps: Some(8),
    backend: Some("typescript"),
    seed: "0x1234",
  }
  let batch = match @runner.generate_run(config) {
    Ok(batch) => batch
    Err(reason) => abort("BankAccount generation failed: \{reason}")
  }
  let result = @bank_account.replay_bank_suite(batch.traces, broken_withdraw~)
  @runner.cleanup(batch.temp_dir)
  match result {
    Ok(summary) =>
      println(
        "BankAccount passed: \{summary.traces_checked} traces, \{summary.states_checked} states matched",
      )
    Err(error) => abort("BankAccount replay failed: \{@debug.to_string(error)}")
  }
}
