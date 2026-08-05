#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
package_dir="$repo_root"
spec="$repo_root/fixtures/OrderCheckout.qnt"

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

run_args=(
  run "$spec"
  --main OrderCheckout
  --max-samples 8
  --max-steps 8
  --seed 0x1234
)

echo "== MoonBit Connect: MoonBit runner generates and replays multiple traces"
(
  cd "$package_dir"
  moon run cmd/connect "${run_args[@]}"
) >"$probe_tmp_dir/run-positive.log" 2>&1

rg -q 'MoonBit Connect seed: 0x1234' "$probe_tmp_dir/run-positive.log"
rg -q 'MoonBit Connect passed: 8 traces, 34 states matched' \
  "$probe_tmp_dir/run-positive.log"

echo "== MoonBit Connect: broken implementation must fail a generated trace"
if (
  cd "$package_dir"
  moon run cmd/connect "${run_args[@]}" --broken-cancel
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

named_spec="$package_dir/fixtures/OrderCheckoutNamed.qnt"
test_args=(
  test "$named_spec"
  --main OrderCheckoutNamed
  --test cancelTest
  --max-samples 1
  --state-path model
  --nondet-path actionTaken
)

echo "== MoonBit Connect: named test uses nested state and custom action data"
(
  cd "$package_dir"
  QUINT_SEED=0x1234 moon run cmd/connect "${test_args[@]}"
) >"$probe_tmp_dir/test-positive.log" 2>&1

rg -q 'MoonBit Connect seed: 0x1234' "$probe_tmp_dir/test-positive.log"
rg -q 'MoonBit Connect passed: 1 traces, 2 states matched' \
  "$probe_tmp_dir/test-positive.log"

echo "== MoonBit Connect: broken implementation must fail the named test"
if (
  cd "$package_dir"
  QUINT_SEED=0x1234 moon run cmd/connect "${test_args[@]}" --broken-cancel
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

echo "MoonBit Connect controls passed: generated and named traces detect state drift"
