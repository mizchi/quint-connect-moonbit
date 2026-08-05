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
    moon test --target js -p mizchi/quint_connect --deny-warn

integration:
    ./scripts/check.sh

check: fmt-check typecheck test integration
