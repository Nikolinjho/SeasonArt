#!/bin/bash
set -euo pipefail
seasonart_root="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$seasonart_root/Scripts/installation.py" rollback "$@"
