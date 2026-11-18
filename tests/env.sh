# Source me: `source tests/env.sh`. Exports the lab variables and defines mcp().
# Nothing here is written to disk: tokens and the admin key live only in this shell.
# Region is pinned to us-east-1; set AWS_PROFILE yourself if you need a non-default one.
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_outputs="${OUTPUTS_FILE:-$_root/results/cdk-outputs.json}"
_out() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['McpEdgeLab'][sys.argv[2]])" "$_outputs" "$1"; }

export RUNTIME_ARN=$(_out RuntimeArn)
export CLIENT_ID=$(_out ClientId)
export USER_POOL_ID=$(_out UserPoolId)
export EDGE_URL=$(_out EdgeUrl)
export WEB_ACL_ID=$(_out WebAclId)
export DISTRIBUTION_ID=$(_out DistributionId)

# Same construction as the article (section 2).
export ENC_ARN=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$RUNTIME_ARN")
export DIRECT_URL="https://bedrock-agentcore.us-east-1.amazonaws.com/runtimes/${ENC_ARN}/invocations?qualifier=DEFAULT"

PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$(_out TestUserSecretArn)" --query SecretString --output text)
export TOKEN=$(aws cognito-idp initiate-auth \
  --client-id "$CLIENT_ID" --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=testuser,PASSWORD="$PASSWORD" \
  --query 'AuthenticationResult.AccessToken' --output text)
unset PASSWORD

# The admin key is readable by anyone who can read the web ACL (that's the point
# the article makes about shared header keys), so the tests just fetch it from WAF.
export ADMIN_KEY=$(aws wafv2 get-web-acl --scope CLOUDFRONT --name mcp-edge --id "$WEB_ACL_ID" \
  --query "WebACL.Rules[?Name=='refund-needs-admin-key'].Statement.AndStatement.Statements[2].NotStatement.Statement.ByteMatchStatement.SearchString | [0]" \
  --output text | python3 -c "import base64,sys;s=sys.stdin.read().strip();print(base64.b64decode(s).decode() if not all(c in '0123456789abcdef' for c in s) else s)")

mcp() {  # usage: mcp <url> '<json-rpc body>' [extra curl args]
  curl -s -X POST "$1" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$2" "${@:3}"
}
export -f mcp
