#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
package_dir="$repo_root"
order_spec="$repo_root/examples/order_checkout/OrderCheckout.qnt"
named_order_spec="$repo_root/examples/order_checkout/OrderCheckoutNamed.qnt"
bank_spec="$repo_root/examples/bank_account/BankAccount.qnt"
command_spec="$repo_root/examples/command_sink/CommandSink.qnt"

for tool_name in quint moon rg; do
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "$tool_name is required to run the integration controls." >&2
    exit 127
  fi
done

probe_tmp_parent="${TMPDIR:-/tmp}"
probe_tmp_dir="$(mktemp -d "${probe_tmp_parent%/}/quint-connect-moonbit.XXXXXX")"

cleanup() {
  case "$probe_tmp_dir" in
    "${probe_tmp_parent%/}"/quint-connect-moonbit.*)
      rm -rf -- "$probe_tmp_dir"
      ;;
    *)
      echo "Refusing to clean unexpected path: $probe_tmp_dir" >&2
      ;;
  esac
}
trap cleanup EXIT

echo "== Examples: Quint typecheck"
quint typecheck "$order_spec"
quint typecheck "$named_order_spec"
quint typecheck "$bank_spec"
quint typecheck "$command_spec"

run_args=(
  run "$order_spec"
  --main OrderCheckout
  --max-samples 8
  --max-steps 8
  --seed 0x1234
)

echo "== MoonBit Connect: MoonBit runner generates and replays multiple traces"
(
  cd "$package_dir"
  moon run --target native examples/order_checkout/cmd "${run_args[@]}"
) >"$probe_tmp_dir/run-positive.log" 2>&1

rg -q 'MoonBit Connect seed: 0x1234' "$probe_tmp_dir/run-positive.log"
rg -q 'MoonBit Connect passed: 8 traces, 34 states matched' \
  "$probe_tmp_dir/run-positive.log"

echo "== MoonBit Connect: broken implementation must fail a generated trace"
if (
  cd "$package_dir"
  moon run --target native examples/order_checkout/cmd "${run_args[@]}" --broken-cancel
) >"$probe_tmp_dir/run-negative.log" 2>&1; then
  echo "Expected MoonBit Connect to reject the broken cancel transition" >&2
  exit 1
fi

if ! rg -Uq '(?s)StateDiverged\(.*"cancelCart".*Cancelled.*Refunded.*QUINT_SEED=0x1234' \
  "$probe_tmp_dir/run-negative.log"; then
  echo "The broken implementation failed for an unexpected reason" >&2
  sed -n '1,200p' "$probe_tmp_dir/run-negative.log" >&2
  exit 1
fi

test_args=(
  test "$named_order_spec"
  --main OrderCheckoutNamed
  --test cancelTest
  --max-samples 1
  --state-path model
  --nondet-path actionTaken
)

echo "== MoonBit Connect: named test uses nested state and custom action data"
(
  cd "$package_dir"
  QUINT_SEED=0x1234 moon run --target native examples/order_checkout/cmd "${test_args[@]}"
) >"$probe_tmp_dir/test-positive.log" 2>&1

rg -q 'MoonBit Connect seed: 0x1234' "$probe_tmp_dir/test-positive.log"
rg -q 'MoonBit Connect passed: 1 traces, 2 states matched' \
  "$probe_tmp_dir/test-positive.log"

echo "== MoonBit Connect: broken implementation must fail the named test"
if (
  cd "$package_dir"
  QUINT_SEED=0x1234 moon run --target native examples/order_checkout/cmd "${test_args[@]}" --broken-cancel
) >"$probe_tmp_dir/test-negative.log" 2>&1; then
  echo "Expected the named test to reject the broken cancel transition" >&2
  exit 1
fi

if ! rg -Uq '(?s)StateDiverged\(.*"CancelCart".*Cancelled.*Refunded' \
  "$probe_tmp_dir/test-negative.log"; then
  echo "The broken named test failed for an unexpected reason" >&2
  sed -n '1,200p' "$probe_tmp_dir/test-negative.log" >&2
  exit 1
fi

echo "== BankAccount: nondeterministic amounts and state projection"
(
  cd "$package_dir"
  moon run --target native examples/bank_account/cmd
) >"$probe_tmp_dir/bank-positive.log" 2>&1

rg -q 'BankAccount passed: 8 traces, 72 states matched' \
  "$probe_tmp_dir/bank-positive.log"

echo "== BankAccount: broken withdrawal must diverge"
if (
  cd "$package_dir"
  moon run --target native examples/bank_account/cmd -- --broken-withdraw
) >"$probe_tmp_dir/bank-negative.log" 2>&1; then
  echo "Expected BankAccount to reject the double withdrawal" >&2
  exit 1
fi

if ! rg -Uq '(?s)StateDiverged\(.*"withdraw".*' \
  "$probe_tmp_dir/bank-negative.log"; then
  echo "The broken BankAccount failed for an unexpected reason" >&2
  sed -n '1,200p' "$probe_tmp_dir/bank-negative.log" >&2
  exit 1
fi

echo "== CommandSink: stateless command replay"
(
  cd "$package_dir"
  moon run --target native examples/command_sink/cmd
) >"$probe_tmp_dir/command-positive.log" 2>&1

rg -q 'CommandSink passed: 8 traces, 72 actions executed' \
  "$probe_tmp_dir/command-positive.log"

echo "== CommandSink: missing reset mapping must be rejected"
if (
  cd "$package_dir"
  moon run --target native examples/command_sink/cmd -- --reject-reset
) >"$probe_tmp_dir/command-negative.log" 2>&1; then
  echo "Expected CommandSink to reject the missing reset mapping" >&2
  exit 1
fi

if ! rg -Uq '(?s)DriverRejected\(.*"reset".*reset mapping is disabled' \
  "$probe_tmp_dir/command-negative.log"; then
  echo "The broken CommandSink failed for an unexpected reason" >&2
  sed -n '1,200p' "$probe_tmp_dir/command-negative.log" >&2
  exit 1
fi

echo "All MoonBit Connect examples passed their positive and negative controls"
