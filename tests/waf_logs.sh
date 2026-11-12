#!/usr/bin/env bash
# Logs Insights over the WAF log group. Usage: waf_logs.sh <start-epoch> <end-epoch> [extra filter]
# Client IPs are masked (IPv4 to /16, IPv6 to /32) so results can be shared.
set -euo pipefail
export AWS_REGION=us-east-1
start=$1; end=$2; extra=${3:-}
q="fields @timestamp, action, terminatingRuleId, responseCodeSent, httpRequest.httpMethod as method, httpRequest.clientIp as ip, labels.0.name as label0, labels.1.name as label1, nonTerminatingMatchingRules.0.ruleId as countRule | filter httpSourceName = \"CF\" $extra | sort @timestamp asc | limit 1000"
id=$(aws logs start-query --log-group-name aws-waf-logs-mcp-edge --start-time "$start" --end-time "$end" --query-string "$q" --query queryId --output text)
for _ in $(seq 1 30); do
  sleep 2
  res=$(aws logs get-query-results --query-id "$id" --output json)
  st=$(echo "$res" | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])")
  [ "$st" = Complete ] && break
done
echo "$res" | python3 -c '
import json,sys,re
rows=json.load(sys.stdin)["results"]
for r in rows:
    d={c["field"]:c["value"] for c in r if c["field"]!="@ptr"}
    if "ip" in d:
        ip=d["ip"]
        d["ip"]=":".join(ip.split(":")[:2])+":x:x:x:x:x:x" if ":" in ip else ".".join(ip.split(".")[:2])+".x.x"
    print(json.dumps(d))
'
