///|
pub(all) enum OrderState {
  Cart
  PaymentPending
  Paid
  Shipped
  Refunded
  Cancelled
} derive(Eq, Debug)

///|
/// Observable state shared by the Quint model and MoonBit implementation.
/// The two-item set is encoded as a bit mask to make order irrelevant.
pub(all) struct OrderSnapshot {
  state : OrderState
  cart_mask : Int
  refunded : Bool
} derive(Eq, Debug)

///|
pub struct OrderDriver {
  state : OrderState
  cart_mask : Int
  refunded : Bool
  broken_cancel : Bool
}

///|
pub fn new_order_driver(broken_cancel? : Bool = false) -> OrderDriver {
  { state: Cart, cart_mask: 0, refunded: false, broken_cancel }
}

///|
fn OrderDriver::snapshot(self : OrderDriver) -> OrderSnapshot {
  { state: self.state, cart_mask: self.cart_mask, refunded: self.refunded }
}

///|
fn item_bit(candidate : String) -> Result[Int, String] {
  match candidate {
    "i1" => Ok(1)
    "i2" => Ok(2)
    _ => Err("unknown item \{candidate}")
  }
}

///|
fn decode_candidate(picks : Json) -> Result[String, String] {
  match required_nondet(picks, "candidate") {
    Ok(String(value)) => Ok(value)
    Ok(_) => Err("candidate must be a string")
    Err(_) => Err("addItem requires nondet pick candidate")
  }
}

///|
fn require_state(
  actual : OrderState,
  required : OrderState,
  action : String,
) -> Result[Unit, String] {
  if actual == required {
    Ok(())
  } else {
    Err(
      "\{action} requires \{@debug.to_string(required)}, got \{@debug.to_string(actual)}",
    )
  }
}

///|
fn OrderDriver::apply(
  self : OrderDriver,
  action : String,
  picks : Json,
) -> Result[OrderDriver, String] {
  match action {
    "init" | "Init" =>
      Ok({ ..self, state: Cart, cart_mask: 0, refunded: false })
    "addItem" => {
      match require_state(self.state, Cart, action) {
        Err(reason) => return Err(reason)
        Ok(_) => ()
      }
      let candidate = match decode_candidate(picks) {
        Ok(value) => value
        Err(reason) => return Err(reason)
      }
      let bit = match item_bit(candidate) {
        Ok(value) => value
        Err(reason) => return Err(reason)
      }
      if (self.cart_mask & bit) != 0 {
        Err("addItem requires an item not already in the cart")
      } else {
        Ok({ ..self, cart_mask: self.cart_mask | bit })
      }
    }
    "checkout" => {
      match require_state(self.state, Cart, action) {
        Err(reason) => return Err(reason)
        Ok(_) => ()
      }
      if self.cart_mask == 0 {
        Err("checkout requires a non-empty cart")
      } else {
        Ok({ ..self, state: PaymentPending })
      }
    }
    "paymentSucceeded" =>
      match require_state(self.state, PaymentPending, action) {
        Err(reason) => return Err(reason)
        Ok(_) => Ok({ ..self, state: Paid })
      }
    "paymentFailed" =>
      match require_state(self.state, PaymentPending, action) {
        Err(reason) => return Err(reason)
        Ok(_) => Ok({ ..self, state: Cart })
      }
    "paymentTimeout" =>
      match require_state(self.state, PaymentPending, action) {
        Err(reason) => return Err(reason)
        Ok(_) => Ok({ ..self, state: Cancelled })
      }
    "ship" =>
      match require_state(self.state, Paid, action) {
        Err(reason) => return Err(reason)
        Ok(_) => Ok({ ..self, state: Shipped })
      }
    "refund" =>
      if self.state == Paid || self.state == Shipped {
        Ok({ ..self, state: Refunded, refunded: true })
      } else {
        Err(
          "refund requires Paid or Shipped, got \{@debug.to_string(self.state)}",
        )
      }
    "cancelCart" | "CancelCart" => {
      match require_state(self.state, Cart, action) {
        Err(reason) => return Err(reason)
        Ok(_) => ()
      }
      if self.broken_cancel {
        Ok({ ..self, state: Refunded, refunded: true })
      } else {
        Ok({ ..self, state: Cancelled })
      }
    }
    _ => Err("unknown Quint action \{action}")
  }
}

///|
fn decode_order_state(value : Json) -> Result[OrderState, String] {
  guard value is Object(variant) else {
    return Err("state must be an ITF variant object")
  }
  match variant.get("tag") {
    Some(String("Cart")) => Ok(Cart)
    Some(String("PaymentPending")) => Ok(PaymentPending)
    Some(String("Paid")) => Ok(Paid)
    Some(String("Shipped")) => Ok(Shipped)
    Some(String("Refunded")) => Ok(Refunded)
    Some(String("Cancelled")) => Ok(Cancelled)
    Some(String(tag)) => Err("unknown OrderState tag \{tag}")
    _ => Err("state variant is missing tag")
  }
}

///|
fn decode_cart(value : Json) -> Result[Int, String] {
  guard value is Object(encoded_set) else {
    return Err("cart must be an ITF set object")
  }
  guard encoded_set.get("#set") is Some(Array(items)) else {
    return Err("cart is missing #set")
  }
  let mut mask = 0
  for item in items {
    guard item is String(candidate) else {
      return Err("cart entries must be strings")
    }
    let bit = match item_bit(candidate) {
      Ok(value) => value
      Err(reason) => return Err(reason)
    }
    mask = mask | bit
  }
  Ok(mask)
}

///|
fn decode_order_snapshot(value : Json) -> Result[OrderSnapshot, String] {
  guard value is Object(fields) else {
    return Err("ITF state must be an object")
  }
  let state = match fields.get("state") {
    Some(value) =>
      match decode_order_state(value) {
        Ok(state) => state
        Err(reason) => return Err(reason)
      }
    None => return Err("ITF state is missing state")
  }
  let cart_mask = match fields.get("cart") {
    Some(value) =>
      match decode_cart(value) {
        Ok(mask) => mask
        Err(reason) => return Err(reason)
      }
    None => return Err("ITF state is missing cart")
  }
  let refunded = match fields.get("refunded") {
    Some(true) => true
    Some(false) => false
    _ => return Err("ITF state is missing boolean refunded")
  }
  Ok({ state, cart_mask, refunded })
}

///|
pub fn replay_order(
  trace : ItfTrace,
  driver : OrderDriver,
) -> Result[ReplaySummary, ConnectError] {
  replay(
    trace,
    driver,
    (driver, action, picks) => driver.apply(action, picks),
    driver => driver.snapshot(),
    decode_order_snapshot,
  )
}

///|
pub fn replay_order_suite(
  traces : Array[ItfTrace],
  broken_cancel? : Bool = false,
) -> Result[ReplaySuiteSummary, SuiteError] {
  replay_suite(
    traces,
    () => new_order_driver(broken_cancel~),
    (driver, action, picks) => driver.apply(action, picks),
    driver => driver.snapshot(),
    decode_order_snapshot,
  )
}
