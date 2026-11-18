#!/usr/bin/env bash
# Section 2 "naked test": all three tools straight against the AgentCore endpoint.
source "$(dirname "$0")/env.sh"
echo '$ mcp "$DIRECT_URL" '\''{"jsonrpc":"2.0","id":1,"method":"tools/list"}'\'' -w "\nHTTP %{http_code}\n"'
mcp "$DIRECT_URL" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -w "\nHTTP %{http_code}\n"
echo '$ mcp "$DIRECT_URL" '\''{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lookup_order","arguments":{"order_id":"A1001"}}}'\'' -w "\nHTTP %{http_code}\n"'
mcp "$DIRECT_URL" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lookup_order","arguments":{"order_id":"A1001"}}}' -w "\nHTTP %{http_code}\n"
echo '$ mcp "$DIRECT_URL" '\''{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_account_balance","arguments":{"customer_id":"cust-7"}}}'\'' -w "\nHTTP %{http_code}\n"'
mcp "$DIRECT_URL" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_account_balance","arguments":{"customer_id":"cust-7"}}}' -w "\nHTTP %{http_code}\n"
echo '$ mcp "$DIRECT_URL" '\''{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"refund_payment","arguments":{"order_id":"A1001","amount":42.5}}}'\'' -w "\nHTTP %{http_code}\n"'
mcp "$DIRECT_URL" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"refund_payment","arguments":{"order_id":"A1001","amount":42.5}}}' -w "\nHTTP %{http_code}\n"
# Same call with no token
curl -s -X POST "$DIRECT_URL" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -w "\nHTTP %{http_code}\n"
