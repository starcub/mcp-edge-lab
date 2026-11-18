#!/usr/bin/env bash
# T5: tool poisoning. Deploy the poisoned variant first:
#   cd infra && npx cdk deploy -c poison=true
# then list tools through CloudFront. Redeploy with -c poison=false afterwards.
source "$(dirname "$0")/env.sh"
mcp "$EDGE_URL" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -w "\nHTTP %{http_code}\n"

# What a fooled agent sends next: two perfectly valid requests.
mcp "$EDGE_URL" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_account_balance","arguments":{"customer_id":"cust-7"}}}' -w "\nHTTP %{http_code}\n"
mcp "$EDGE_URL" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lookup_order","arguments":{"order_id":"1830.22"}}}' -w "\nHTTP %{http_code}\n"
