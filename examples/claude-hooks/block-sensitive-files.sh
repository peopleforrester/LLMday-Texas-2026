#!/usr/bin/env bash
# ABOUTME: Blocks writes to sensitive files (.env, credentials, keys, secrets).
# ABOUTME: Returns exit 2 (BLOCK) if the target file matches a sensitive pattern.

set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE" ]]; then
    exit 0
fi

BASENAME=$(basename "$FILE")
LOWER_BASENAME=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')

# Block exact sensitive filenames
case "$LOWER_BASENAME" in
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks)
        echo "BLOCKED: Cannot write to sensitive file: $BASENAME" >&2
        exit 2
        ;;
esac

# Block files with sensitive keywords in the name
case "$LOWER_BASENAME" in
    *credential*|*secret*|*password*|*token*|*apikey*|*api_key*|*private_key*)
        echo "BLOCKED: Cannot write to file with sensitive name: $BASENAME" >&2
        exit 2
        ;;
esac

# Block known sensitive config files
case "$BASENAME" in
    id_rsa|id_ed25519|id_ecdsa|authorized_keys|known_hosts)
        echo "BLOCKED: Cannot write to SSH file: $BASENAME" >&2
        exit 2
        ;;
esac

exit 0
