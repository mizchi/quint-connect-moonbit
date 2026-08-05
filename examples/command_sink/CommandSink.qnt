// Stateless example: the MoonBit adapter executes every command but does not
// compare implementation state. Driver rejection still detects an incomplete
// action mapping.
module CommandSink {
  var commandsSeen: int

  action init = commandsSeen' = 0

  action ping = commandsSeen' = commandsSeen + 1

  action reset = commandsSeen' = 0

  action step = any {
    ping,
    reset,
  }
}
