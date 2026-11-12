#!/usr/bin/env bash
# Creates the Cognito lab user "testuser" with the password the stack generated
# into Secrets Manager. Run once after `cdk deploy`.
set -euo pipefail
export AWS_REGION=us-east-1
root="$(cd "$(dirname "$0")/.." && pwd)"
out() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['McpEdgeLab'][sys.argv[2]])" "$root/results/cdk-outputs.json" "$1"; }
pool=$(out UserPoolId)
pw=$(aws secretsmanager get-secret-value --secret-id "$(out TestUserSecretArn)" --query SecretString --output text)
aws cognito-idp admin-create-user --user-pool-id "$pool" --username testuser --message-action SUPPRESS >/dev/null 2>&1 || true
aws cognito-idp admin-set-user-password --user-pool-id "$pool" --username testuser --password "$pw" --permanent
echo "testuser ready in $pool"
