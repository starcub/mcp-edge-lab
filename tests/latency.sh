#!/usr/bin/env bash
# 20 tools/call lookup_order round trips direct vs through CloudFront + WAF,
# one warm-up call dropped per path. Prints median and p90 in ms.
#
# Two modes:
#   new    – exactly the article's loop: no Mcp-Session-Id, so AgentCore starts a
#            fresh runtime session (microVM) for every call.
#   reuse  – the warm-up call's Mcp-Session-Id is sent on every timed call, so all
#            calls land on the same warm session. This isolates the edge overhead.
source "$(dirname "$0")/env.sh"
BODY='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lookup_order","arguments":{"order_id":"A1001"}}}'
stats() { sort -n | awk -v n="$1" '{a[NR]=$1*1000} END {printf "%-14s n=%d median_ms=%.0f p90_ms=%.0f min_ms=%.0f max_ms=%.0f\n", n, NR, (a[10]+a[11])/2, a[18], a[1], a[20]}'; }
for mode in ${MODES:-new reuse}; do
  for name in direct edge; do
    [ "$name" = direct ] && url="$DIRECT_URL" || url="$EDGE_URL"
    sid=$(mcp "$url" "$BODY" -D - -o /dev/null | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' | tr -d '\r')  # warm-up
    extra=(); [ "$mode" = reuse ] && extra=(-H "Mcp-Session-Id: $sid")
    for i in $(seq 1 20); do mcp "$url" "$BODY" "${extra[@]}" -o /dev/null -w "%{time_total}\n"; done | stats "$mode/$name"
  done
done
