#!/usr/bin/env bash
# T2: 300 tools/list calls in ~60 s from one IP. Run once with the rate rule in
# Count (cdk deploy -c rateAction=count) and once in Block (-c rateAction=block).
# Optional $1: file to write the per-request timeline ("<n> <epoch> <http_code>").
source "$(dirname "$0")/env.sh"
timeline="${1:-/dev/null}"
for i in $(seq 1 300); do
  ( code=$(mcp "$EDGE_URL" '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -o /dev/null -w "%{http_code}")
    echo "$i $(date +%s) $code" ) &
  sleep 0.2
done | tee "$timeline" | awk '{print $3}' | sort | uniq -c
wait
