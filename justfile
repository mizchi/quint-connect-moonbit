set shell := ["zsh", "-cu"]

default:
    just --list

fmt:
    moon fmt

fmt-check:
    moon fmt --check

typecheck:
    moon check --target all --deny-warn

test: test-js test-wasm test-native

test-js:
    moon test --target js \
        -p mizchi/quint_connect \
        -p mizchi/quint_connect/examples/order_checkout \
        -p mizchi/quint_connect/examples/bank_account \
        -p mizchi/quint_connect/examples/command_sink \
        --deny-warn

test-wasm:
    moon test --target wasm \
        -p mizchi/quint_connect \
        -p mizchi/quint_connect/examples/order_checkout \
        -p mizchi/quint_connect/examples/bank_account \
        -p mizchi/quint_connect/examples/command_sink \
        --deny-warn

test-native:
    moon test --target native --release \
        -p mizchi/quint_connect \
        -p mizchi/quint_connect/examples/order_checkout \
        -p mizchi/quint_connect/examples/bank_account \
        -p mizchi/quint_connect/examples/command_sink \
        --deny-warn

integration:
    ./scripts/check.sh

wasm-demo:
    moon run --target wasm examples/bank_account/wasm

check: fmt-check typecheck test wasm-demo integration
