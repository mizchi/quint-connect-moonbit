///|
pub struct BankDriver {
  balance : Int
  broken_withdraw : Bool
}

///|
pub fn new_bank_driver(broken_withdraw? : Bool = false) -> BankDriver {
  { balance: 0, broken_withdraw }
}

///|
fn decode_amount(picks : Json) -> Result[Int, String] {
  match @quint_connect.required_nondet(picks, "amount") {
    Ok(value) => {
      let amount = match @quint_connect.decode_itf_int(value) {
        Ok(amount) => amount
        Err(reason) => return Err(reason)
      }
      if amount > 0 {
        Ok(amount)
      } else {
        Err("amount must be positive")
      }
    }
    Err(reason) => Err(reason)
  }
}

///|
fn BankDriver::apply(
  self : BankDriver,
  action : String,
  picks : Json,
) -> Result[BankDriver, String] {
  match action {
    "init" => Ok({ ..self, balance: 4 })
    "deposit" => {
      let amount = match decode_amount(picks) {
        Ok(amount) => amount
        Err(reason) => return Err(reason)
      }
      Ok({ ..self, balance: self.balance + amount })
    }
    "withdraw" => {
      let amount = match decode_amount(picks) {
        Ok(amount) => amount
        Err(reason) => return Err(reason)
      }
      if self.balance < amount {
        Err("withdraw requires sufficient funds")
      } else {
        let debit = if self.broken_withdraw { amount * 2 } else { amount }
        Ok({ ..self, balance: self.balance - debit })
      }
    }
    _ => Err("unknown BankAccount action \{action}")
  }
}

///|
fn decode_balance(value : Json) -> Result[Int, String] {
  guard value is Object(fields) else {
    return Err("BankAccount state must be an object")
  }
  match fields.get("balance") {
    Some(balance) => @quint_connect.decode_itf_int(balance)
    _ => Err("BankAccount state is missing integer balance")
  }
}

///|
pub fn replay_bank_suite(
  traces : Array[@quint_connect.ItfTrace],
  broken_withdraw? : Bool = false,
) -> Result[@quint_connect.ReplaySuiteSummary, @quint_connect.SuiteError] {
  @quint_connect.replay_suite(
    traces,
    () => new_bank_driver(broken_withdraw~),
    (driver, action, picks) => driver.apply(action, picks),
    driver => driver.balance,
    decode_balance,
  )
}
