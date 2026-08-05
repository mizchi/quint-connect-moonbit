///|
fn order_trace_fixture() -> String {
  let fixture =
    #|{
    #|  "#meta": { "format": "ITF" },
    #|  "vars": ["cart", "mbt::actionTaken", "mbt::nondetPicks", "refunded", "state"],
    #|  "states": [
    #|    {
    #|      "#meta": { "index": 0 },
    #|      "cart": { "#set": [] },
    #|      "mbt::actionTaken": "init",
    #|      "mbt::nondetPicks": {},
    #|      "refunded": false,
    #|      "state": { "tag": "Cart", "value": { "#tup": [] } }
    #|    },
    #|    {
    #|      "#meta": { "index": 1 },
    #|      "cart": { "#set": ["i1"] },
    #|      "mbt::actionTaken": "addItem",
    #|      "mbt::nondetPicks": {
    #|        "candidate": { "tag": "Some", "value": "i1" }
    #|      },
    #|      "refunded": false,
    #|      "state": { "tag": "Cart", "value": { "#tup": [] } }
    #|    },
    #|    {
    #|      "#meta": { "index": 2 },
    #|      "cart": { "#set": ["i1"] },
    #|      "mbt::actionTaken": "cancelCart",
    #|      "mbt::nondetPicks": {},
    #|      "refunded": false,
    #|      "state": { "tag": "Cancelled", "value": { "#tup": [] } }
    #|    }
    #|  ]
    #|}
  fixture
}

///|
test "ITF decoder preserves action metadata" {
  let trace = @quint_connect.parse_itf(order_trace_fixture()).unwrap()
  assert_eq(trace.states.length(), 3)
  assert_eq(trace.states[0].action, "init")
  assert_eq(trace.states[1].action, "addItem")
  assert_eq(trace.states[2].index, 2)
}

///|
test "OrderCheckout driver replays a valid Quint trace" {
  let trace = @quint_connect.parse_itf(order_trace_fixture()).unwrap()
  let result = @quint_connect.replay_order(
    trace,
    @quint_connect.new_order_driver(),
  )
  match result {
    Ok(summary) => assert_eq(summary.states_checked, 3)
    Err(error) => fail("expected valid trace, got \{@debug.to_string(error)}")
  }
}

///|
test "state comparison rejects a deliberately broken cancel transition" {
  let trace = @quint_connect.parse_itf(order_trace_fixture()).unwrap()
  let result = @quint_connect.replay_order(
    trace,
    @quint_connect.new_order_driver(broken_cancel=true),
  )
  match result {
    Err(StateDiverged(index, action, expected, actual)) => {
      assert_eq(index, 2)
      assert_eq(action, "cancelCart")
      assert_true(expected.contains("Cancelled"))
      assert_true(actual.contains("Refunded"))
    }
    Err(error) => fail("unexpected adapter error: \{@debug.to_string(error)}")
    Ok(_) => fail("the broken implementation must not match the Quint trace")
  }
}

///|
test "ITF decoder rejects a trace without states" {
  match @quint_connect.parse_itf("{\"vars\": []}") {
    Err(TraceDecode(_)) => ()
    Err(error) => fail("unexpected decode error: \{@debug.to_string(error)}")
    Ok(_) => fail("a trace without states must be rejected")
  }
}

///|
test "driver mapping failures stay distinct from state divergence" {
  let trace : @quint_connect.ItfTrace = {
    states: [
      {
        index: 7,
        action: "unknownAction",
        nondet_picks: Json::object({}),
        value: Json::object({}),
      },
    ],
  }
  let result = @quint_connect.replay_order(
    trace,
    @quint_connect.new_order_driver(),
  )
  match result {
    Err(DriverRejected(index, action, reason)) => {
      assert_eq(index, 7)
      assert_eq(action, "unknownAction")
      assert_true(reason.contains("unknown Quint action"))
    }
    Err(error) => fail("unexpected adapter error: \{@debug.to_string(error)}")
    Ok(_) => fail("an unknown action must be rejected by the driver")
  }
}

///|
test "MBT metadata is strict and rejects missing or anonymous actions" {
  let missing_picks =
    #|{"states":[{"mbt::actionTaken":"init","state":{"tag":"Cart"}}]}
  let anonymous =
    #|{"states":[{"mbt::actionTaken":"","mbt::nondetPicks":{},"state":{"tag":"Cart"}}]}
  match @quint_connect.parse_itf(missing_picks) {
    Err(TraceDecode(message)) =>
      assert_true(message.contains("mbt::nondetPicks"))
    _ => fail("missing nondet metadata must be rejected")
  }
  match @quint_connect.parse_itf(anonymous) {
    Err(TraceDecode(message)) => assert_true(message.contains("anonymous"))
    _ => fail("anonymous actions must be rejected")
  }
}

///|
test "nested state and custom sum-type nondeterminism can be projected" {
  let fixture =
    #|{
    #|  "states": [{
    #|    "#meta": { "index": 4 },
    #|    "global": {
    #|      "model": { "count": 1 },
    #|      "choice": {
    #|        "tag": "addItem",
    #|        "value": {
    #|          "candidate": { "tag": "Some", "value": "i2" },
    #|          "unused": { "tag": "None", "value": { "#tup": [] } }
    #|        }
    #|      }
    #|    }
    #|  }]
    #|}
  let config : @quint_connect.TraceConfig = {
    state_path: ["global", "model"],
    nondet_path: ["global", "choice"],
  }
  let trace = @quint_connect.parse_itf_with_config(fixture, config).unwrap()
  assert_eq(trace.states[0].index, 4)
  assert_eq(trace.states[0].action, "addItem")
  match
    @quint_connect.required_nondet(trace.states[0].nondet_picks, "candidate") {
    Ok(String(value)) => assert_eq(value, "i2")
    _ => fail("candidate should be unwrapped from Quint Some")
  }
  match @quint_connect.optional_nondet(trace.states[0].nondet_picks, "unused") {
    Ok(None) => ()
    _ => fail("Quint None should be absent from normalized nondet picks")
  }
  guard trace.states[0].value is Object(state) else {
    fail("nested model state should be an object")
  }
  assert_true(state.contains("count"))
  assert_false(state.contains("global"))
}

///|
test "run and named-test configurations build Quint commands" {
  let run_config : @quint_connect.RunConfig = {
    spec: "OrderCheckout.qnt",
    main: Some("OrderCheckout"),
    init: Some("init"),
    step: Some("step"),
    max_samples: Some(12),
    max_steps: Some(9),
    backend: Some("typescript"),
    seed: "0xabc",
  }
  let run_args = run_config.quint_args("tmp/run_{seq}.itf.json").unwrap()
  assert_eq(
    run_args.join(" "),
    "run OrderCheckout.qnt --seed 0xabc --max-samples 12 --n-traces 12 --out-itf tmp/run_{seq}.itf.json --mbt --verbosity 0 --main OrderCheckout --init init --step step --max-steps 9 --backend typescript",
  )
  let test_config : @quint_connect.TestConfig = {
    spec: "OrderCheckout.qnt",
    main: Some("OrderCheckout"),
    test_name: "cancelTest",
    max_samples: Some(3),
    backend: Some("typescript"),
    seed: "0xdef",
  }
  let test_args = test_config.quint_args("tmp/test_{seq}.itf.json").unwrap()
  assert_eq(
    test_args.join(" "),
    "test OrderCheckout.qnt --seed 0xdef --match ^cancelTest$ --max-samples 3 --out-itf tmp/test_{seq}.itf.json --verbosity 0 --main OrderCheckout --backend typescript",
  )
}

///|
test "multi-trace replay creates a fresh driver and aggregates coverage" {
  let step : @quint_connect.ItfState = {
    index: 0,
    action: "increment",
    nondet_picks: Json::object({}),
    value: Json::object({}),
  }
  let traces : Array[@quint_connect.ItfTrace] = [
    { states: [step] },
    { states: [step] },
  ]
  let result = @quint_connect.replay_suite(
    traces,
    () => 0,
    (driver, _, _) => Ok(driver + 1),
    driver => driver,
    _ => Ok(1),
  ).unwrap()
  assert_eq(result.traces_checked, 2)
  assert_eq(result.states_checked, 2)
}

///|
test "stateless replay still executes every action" {
  let trace = @quint_connect.parse_itf(order_trace_fixture()).unwrap()
  let result = @quint_connect.replay_stateless(trace, 0, (steps, _, _) => {
    Ok(steps + 1)
  }).unwrap()
  assert_eq(result.states_checked, 3)
}

///|
test "seed precedence and generation config validation are explicit" {
  assert_eq(
    @quint_connect.resolve_seed(Some("cli"), Some("env"), "generated"),
    Ok("cli"),
  )
  assert_eq(
    @quint_connect.resolve_seed(None, Some("env"), "generated"),
    Ok("env"),
  )
  assert_eq(
    @quint_connect.resolve_seed(None, None, "generated"),
    Ok("generated"),
  )
  let invalid : @quint_connect.RunConfig = {
    spec: "spec.qnt",
    main: None,
    init: None,
    step: None,
    max_samples: Some(0),
    max_steps: None,
    backend: Some("typescript"),
    seed: "0x1",
  }
  match invalid.quint_args("trace_{seq}.itf.json") {
    Err(reason) => assert_true(reason.contains("max_samples"))
    Ok(_) => fail("zero samples must be rejected before spawning Quint")
  }
}
