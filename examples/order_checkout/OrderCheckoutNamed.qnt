// Named-test fixture for the MoonBit Quint Connect runner.
//
// `quint test` does not expose mbt::actionTaken/mbt::nondetPicks. This fixture
// demonstrates Connect's alternative contract: a sum type records the action,
// while the observable state is nested under `model`.
module OrderCheckoutNamed {
  type OrderState = Cart | Cancelled | Refunded
  type ConnectAction = Init | CancelCart

  var model: { state: OrderState, cart: Set[str], refunded: bool }
  var actionTaken: ConnectAction

  action init = all {
    model' = { state: Cart, cart: Set(), refunded: false },
    actionTaken' = Init,
  }

  action cancelCart = all {
    model.state == Cart,
    model' = { ...model, state: Cancelled },
    actionTaken' = CancelCart,
  }

  run cancelTest = init.then(cancelCart)
}
