# mcp-edge-lab

Companion repo for **"Put Your MCP Servers Behind CloudFront and WAF Before Someone Else Finds Them"**.

One small MCP server on Amazon Bedrock AgentCore Runtime, one CloudFront distribution, one AWS WAF
web ACL with seven rules, and five red-team tests. Everything is one CDK stack in `us-east-1`.
Measured results from a real run are in [`results/RESULTS.md`](results/RESULTS.md).

```
mcp-edge-lab/
├── server/      server.py (FastMCP), Dockerfile, requirements.txt
├── infra/       CDK app (TypeScript): Cognito, AgentCore Runtime, CloudFront, WAF, WAF logging
├── waf/         rules.json (+ custom response body, 429 block action) – the stack loads these files as-is
├── tests/       env.sh, setup_user.sh, naked.sh, t1_client.py, t2_rate.sh, t3_refund.sh,
│                t4_injection.sh, t5_poison.sh, latency.sh, waf_logs.sh
└── results/     RESULTS.md, raw outputs, metric graphs
```

This lab builds **Option A** from the article (public AgentCore endpoint + OAuth as the second lock).
Anyone with a valid token can still call the AgentCore endpoint directly and skip WAF; T3 shows that.

## Prerequisites

- AWS credentials for an account where you can deploy CloudFormation (the lab uses `us-east-1` only)
- Node.js 22+, AWS CDK CLI 2.x, `uv`, `python3`, `curl`, `openssl`
- **No Docker needed.** The runtime uses AgentCore *direct code deployment*
  (`AgentRuntimeArtifact.fromCodeAsset`, `PYTHON_3_12`, entrypoint `server.py`).
  `infra/scripts/package-server.sh` cross-installs Linux ARM64 wheels with
  `uv pip install --python-platform aarch64-manylinux2014 --python-version 3.12` and copies `server.py` next to them.
  If you prefer a container, `server/Dockerfile` works with `AgentRuntimeArtifact.fromAsset('../server')`.

## Deploy

```bash
export AWS_PROFILE=<your-profile> AWS_REGION=us-east-1
cd infra
npm install
npx cdk bootstrap aws://<account-id>/us-east-1        # once per account/region
npm run package-server
ADMIN_KEY=$(openssl rand -hex 24)                      # keep it in your shell only
npx cdk deploy --parameters AdminKey="$ADMIN_KEY" --outputs-file ../results/cdk-outputs.json
cd .. && ./tests/setup_user.sh                         # creates Cognito user "testuser"
```

`AdminKey` is a `NoEcho` CloudFormation parameter, so it never lands in the repo. Later deploys reuse it
automatically (`cdk deploy` keeps previous parameter values), so you only pass it once.

Context flags (pass with `-c`):

| Flag | Values | Default | Used for |
|---|---|---|---|
| `rateAction` | `count`, `block` | `count` | T2: run once in Count, once in Block (429 + `retry-after: 60`) |
| `poison` | `true`, `false` | `false` | T5: ships the poisoned `lookup_order` description (`POISON=1` env var) |
| `originRequestPolicy` | `allViewer`, `allViewerExceptHost` | `allViewer` | CloudFront origin request policy |

Always pass every flag you want on each deploy, e.g. `npx cdk deploy -c rateAction=block -c poison=false`.

## Run the tests

```bash
export AWS_PROFILE=<your-profile>
source tests/env.sh            # exports RUNTIME_ARN, DIRECT_URL, EDGE_URL, TOKEN, ADMIN_KEY; defines mcp()
./tests/naked.sh               # section 2: all tools straight against AgentCore
uv run --python 3.12 --with 'mcp==1.30.0' python tests/t1_client.py   # T1
./tests/t2_rate.sh             # T2 with -c rateAction=count, then redeploy with block and run again
./tests/t3_refund.sh           # T3: no key / key / batch / direct URL
./tests/t4_injection.sh        # T4: SQLi + 169.254.169.254 SSRF
(cd infra && npx cdk deploy -c rateAction=block -c poison=true)  && ./tests/t5_poison.sh   # T5
(cd infra && npx cdk deploy -c rateAction=block -c poison=false)                            # undo T5
./tests/latency.sh             # 20 runs each, warm-up dropped, median + p90 (MODES="new reuse" by default)
./tests/waf_logs.sh <start-epoch> <end-epoch>   # Logs Insights evidence (client IPs masked)
```

`env.sh` keeps the access token and admin key in shell variables only. It reads the admin key back from
the web ACL, which is the article's point: anyone who can read the web ACL can read the key.

Notes:
- The Python MCP SDK 2.x removed `mcp.server.fastmcp`. The server and T1 pin `mcp==1.30.0`.
- Use the CloudFront URL exactly as output (`https://dxxxx.cloudfront.net/`), without `/mcp`.
- Every request without an `Mcp-Session-Id` header starts a new AgentCore session, and each session is
  billed until its 15-minute idle timeout. `MODES=new ./tests/latency.sh` is the article's loop and measures this
  session start-up. `MODES=reuse` sends the warm-up's session ID, the way a real client does.
  The T2 flood and the `new` loop created about 690 sessions, which was most of this lab's ~$1.50 cost.

## Clean up

```bash
cd infra && npx cdk destroy
```

Then check for leftovers: the Cognito user pool and the `aws-waf-logs-mcp-edge` log group are set to
`DESTROY`, but verify. The code asset zip stays in the CDK bootstrap bucket (`cdk-hnb659fds-assets-*`),
and the bootstrap stack (`CDKToolkit`) stays unless you delete it.
