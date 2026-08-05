set shell := ["zsh", "-cu"]

default:
    just --list

fmt:
    moon fmt

fmt-check:
    moon fmt --check

typecheck:
    moon check --deny-warn

test:
    moon test --target js \
        -p mizchi/quint_connect \
        -p mizchi/quint_connect/examples/order_checkout \
        -p mizchi/quint_connect/examples/bank_account \
        -p mizchi/quint_connect/examples/command_sink \
        --deny-warn

integration:
    ./scripts/check.sh

check: fmt-check typecheck test integration
