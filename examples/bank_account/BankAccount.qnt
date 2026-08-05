// Stateful example: nondeterministic amounts are replayed against a MoonBit
// bank-account implementation. The implementation's observable state is the
// integer balance.
module BankAccount {
  pure val amounts = Set(1, 2)

  var balance: int

  action init = balance' = 4

  action deposit(amount: int): bool = all {
    amount.in(amounts),
    balance' = balance + amount,
  }

  action withdraw(amount: int): bool = all {
    amount.in(amounts),
    balance >= amount,
    balance' = balance - amount,
  }

  action step = {
    nondet amount = amounts.oneOf()
    any {
      deposit(amount),
      withdraw(amount),
    }
  }

  val nonNegative = balance >= 0
}
