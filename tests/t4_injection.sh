#!/usr/bin/env bash
# T4: SQL injection and an SSRF string in tool arguments.
source "$(dirname "$0")/env.sh"
SQLI=$(cat <<'JSON'
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"lookup_order","arguments":{"order_id":"A1001' OR '1'='1' --"}}}
JSON
)
echo "--- SQLi in order_id"
mcp "$EDGE_URL" "$SQLI" -w "\nHTTP %{http_code}\n"
echo "--- SSRF to instance metadata in order_id"
mcp "$EDGE_URL" '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"lookup_order","arguments":{"order_id":"http://169.254.169.254/latest/meta-data/iam/security-credentials/"}}}' \
  -w "\nHTTP %{http_code}\n"
