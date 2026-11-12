#!/usr/bin/env bash
# T3: refund_payment with and without the admin key, the batch bypass, and the direct URL.
source "$(dirname "$0")/env.sh"
REFUND='{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"refund_payment","arguments":{"order_id":"A1001","amount":42.5}}}'

echo "--- edge, without the key"
mcp "$EDGE_URL" "$REFUND" -w "\nHTTP %{http_code}\n"
echo "--- edge, with the key"
mcp "$EDGE_URL" "$REFUND" -H "x-admin-key: $ADMIN_KEY" -w "\nHTTP %{http_code}\n"
echo "--- edge, JSON-RPC batch without the key"
mcp "$EDGE_URL" "[$REFUND]" -w "\nHTTP %{http_code}\n"
echo "--- direct AgentCore URL, without the key (skips CloudFront and WAF)"
mcp "$DIRECT_URL" "$REFUND" -w "\nHTTP %{http_code}\n"
