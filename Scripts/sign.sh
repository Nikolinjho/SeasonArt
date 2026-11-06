#!/bin/bash
set -euo pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }

[[ -n "${SEASONART_SIGN_ID:-}" && "${SEASONART_SIGN_ID}" != '-' ]] ||
    fail 'Set SEASONART_SIGN_ID to an existing Keychain signing identity name or SHA-1; ad-hoc signing is disabled.'
export SEASONART_SIGN_ID
seasonart_identities="$(security find-identity -v -p codesigning)" || fail 'Cannot read Keychain signing identities.'
seasonart_matches="$(printf '%s\n' "$seasonart_identities" | awk '
    /^[[:space:]]*[0-9]+\) [[:xdigit:]]+ "/ {
        hash = $2
        name = $0
        sub(/^[^"]*"/, "", name)
        sub(/"[^\"]*$/, "", name)
        if (length(hash) == 40 && (name == ENVIRON["SEASONART_SIGN_ID"] ||
            toupper(hash) == toupper(ENVIRON["SEASONART_SIGN_ID"]))) print hash
    }' | sort -u)"
[[ -n "$seasonart_matches" ]] || fail 'No valid signing identity exactly matches SEASONART_SIGN_ID.'
[[ "$seasonart_matches" != *$'\n'* ]] || fail 'SEASONART_SIGN_ID matches multiple valid signing identities; use its SHA-1.'

if [[ "${1:-}" == '--check-identity' && "$#" == 1 ]]; then
    printf '%s\n' "$seasonart_matches"
    exit 0
fi
[[ "$#" == 1 && -d "$1" ]] || fail 'Usage: sign.sh --check-identity | sign.sh path/to/SeasonArt.app'
codesign --force --sign "$seasonart_matches" "$1"
codesign --verify --deep --strict "$1"
