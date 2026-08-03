#!/usr/bin/env bash
set -euo pipefail

fatal() {
    echo "FATAL: $*" >&2
    exit 1
}
