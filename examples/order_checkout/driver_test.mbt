///|
fn order_trace_fixture() -> String {
  (
    #|{
    #|  "states": [
    #|    {
    #|      "#meta": { "index": 0 },
    #|      "mbt::actionTaken": "init",
    #|      "mbt::nondetPicks": {},
    #|      "state": { "tag": "Cart", "value": { "#tup": [] } },
    #|      "cart": { "#set": [] },
    #|      "refunded": false
    #|    },
    #|    {
    #|      "#meta": { "index": 1 },
    #|      "mbt::actionTaken": "cancelCart",
    #|      "mbt::nondetPicks": {},
    #|      "state": { "tag": "Cancelled", "value": { "#tup": [] } },
    #|      "cart": { "#set": [] },
    #|      "refunded": false
    #|    }
    #|  ]
    #|}
  )
}

///|
test "OrderCheckout example detects cancel state drift" {
  let trace = @quint_connect.parse_itf(order_trace_fixture()).unwrap()
  let summary = @order_checkout.replay_order_suite([trace]).unwrap()
  assert_eq(summary.traces_checked, 1)
  match @order_checkout.replay_order_suite([trace], broken_cancel=true) {
    Err(TraceFailed(_, StateDiverged(_, "cancelCart", expected, actual))) => {
      assert_true(expected.contains("Cancelled"))
      assert_true(actual.contains("Refunded"))
    }
    _ => fail("broken cancel must diverge from the Quint state")
  }
}
