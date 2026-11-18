import * as fs from 'fs';
import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as agentcore from 'aws-cdk-lib/aws-bedrockagentcore';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';

const WAF_DIR = path.join(__dirname, '../../waf');
const readJson = (file: string) => JSON.parse(fs.readFileSync(path.join(WAF_DIR, file), 'utf8'));

// Swap every occurrence of a placeholder string inside the plain WAF JSON.
function substitute(node: any, placeholder: string, value: string): any {
  if (typeof node === 'string') return node === placeholder ? value : node;
  if (Array.isArray(node)) return node.map((n) => substitute(n, placeholder, value));
  if (node && typeof node === 'object') {
    return Object.fromEntries(Object.entries(node).map(([k, v]) => [k, substitute(v, placeholder, value)]));
  }
  return node;
}

export class McpEdgeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Context flags: -c rateAction=count|block, -c originRequestPolicy=allViewer|allViewerExceptHost
    const rateAction = String(this.node.tryGetContext('rateAction') ?? 'count').toLowerCase();
    const orpChoice = String(this.node.tryGetContext('originRequestPolicy') ?? 'allViewer');

    const adminKey = new cdk.CfnParameter(this, 'AdminKey', {
      type: 'String',
      noEcho: true,
      minLength: 16,
      description: 'Value the x-admin-key header must carry to call refund_payment through the edge',
    });

    // ---------- Cognito (inbound OAuth for the runtime) ----------
    const pool = new cognito.UserPool(this, 'Pool', {
      selfSignUpEnabled: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    const client = pool.addClient('McpClient', {
      authFlows: { userPassword: true },
      accessTokenValidity: cdk.Duration.minutes(60),
    });
    const testUserSecret = new secretsmanager.Secret(this, 'TestUserPassword', {
      description: 'Password for the Cognito lab user "testuser"',
      generateSecretString: {
        passwordLength: 24,
        requireEachIncludedType: true,
        excludeCharacters: '"\'`$\\/@,;:&|<>(){}[]!*?#~%^= ',
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ---------- AgentCore Runtime (MCP protocol, Cognito JWT authorizer) ----------
    // Direct code deployment (no Docker needed): see infra/scripts/package-server.sh.
    const runtime = new agentcore.Runtime(this, 'OrdersMcp', {
      runtimeName: 'orders_mcp',
      agentRuntimeArtifact: agentcore.AgentRuntimeArtifact.fromCodeAsset({
        path: path.join(__dirname, '../build/server-pkg'),
        runtime: agentcore.AgentCoreRuntime.PYTHON_3_12,
        entrypoint: ['server.py'],
      }),
      protocolConfiguration: agentcore.ProtocolType.MCP,
      authorizerConfiguration: agentcore.RuntimeAuthorizerConfiguration.usingCognito(pool, [client]),
    });

    // The runtime ARN is a deploy-time token, so URL-encode it from its parts.
    const encodedArn = cdk.Fn.join('', [
      'arn%3Aaws%3Abedrock-agentcore%3A', this.region, '%3A', this.account,
      '%3Aruntime%2F', runtime.agentRuntimeId,
    ]);
    const originPath = cdk.Fn.join('', ['/runtimes/', encodedArn, '/invocations']);

    // ---------- WAF web ACL (rules come straight from waf/*.json) ----------
    let rules = substitute(readJson('rules.json'), '{{ADMIN_KEY}}', adminKey.valueAsString);
    if (rateAction === 'block') {
      const blockAction = readJson('rate-block-action.json');
      rules = rules.map((r: any) => (r.Name === 'rate-per-ip' ? { ...r, Action: blockAction } : r));
    }

    const acl = new wafv2.CfnWebACL(this, 'EdgeAcl', {
      name: 'mcp-edge',
      scope: 'CLOUDFRONT',
      defaultAction: { allow: {} },
      visibilityConfig: { cloudWatchMetricsEnabled: true, sampledRequestsEnabled: true, metricName: 'mcp-edge' },
    });
    // Raw WAF JSON (PascalCase) is valid CloudFormation for these properties.
    acl.addPropertyOverride('Rules', rules);
    acl.addPropertyOverride('CustomResponseBodies', readJson('custom-response-bodies.json'));

    const wafLogs = new logs.LogGroup(this, 'WafLogs', {
      logGroupName: 'aws-waf-logs-mcp-edge',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    const wafLogging = new wafv2.CfnLoggingConfiguration(this, 'WafLogging', {
      resourceArn: acl.attrArn,
      // WAF rejects logGroupArn because it ends in ":*".
      logDestinationConfigs: [this.formatArn({
        service: 'logs', resource: 'log-group',
        resourceName: wafLogs.logGroupName, arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
      })],
      redactedFields: [
        { singleHeader: { Name: 'authorization' } },
        { singleHeader: { Name: 'x-admin-key' } },
      ],
    });
    wafLogging.node.addDependency(wafLogs);

    // ---------- CloudFront ----------
    const originRequestPolicy = orpChoice === 'allViewer'
      ? cloudfront.OriginRequestPolicy.ALL_VIEWER
      : cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER;

    const dist = new cloudfront.Distribution(this, 'Edge', {
      comment: 'MCP edge lab: CloudFront + WAF in front of AgentCore Runtime',
      webAclId: acl.attrArn,
      defaultBehavior: {
        origin: new origins.HttpOrigin(`bedrock-agentcore.${this.region}.amazonaws.com`, {
          originPath,
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
        }),
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
    });

    // ---------- Outputs ----------
    new cdk.CfnOutput(this, 'RuntimeArn', { value: runtime.agentRuntimeArn });
    new cdk.CfnOutput(this, 'UserPoolId', { value: pool.userPoolId });
    new cdk.CfnOutput(this, 'ClientId', { value: client.userPoolClientId });
    new cdk.CfnOutput(this, 'TestUserSecretArn', { value: testUserSecret.secretArn });
    new cdk.CfnOutput(this, 'EdgeUrl', { value: `https://${dist.distributionDomainName}/` });
    new cdk.CfnOutput(this, 'DirectUrl', {
      value: cdk.Fn.join('', [
        `https://bedrock-agentcore.${this.region}.amazonaws.com/runtimes/`, encodedArn,
        '/invocations?qualifier=DEFAULT',
      ]),
    });
    new cdk.CfnOutput(this, 'DistributionId', { value: dist.distributionId });
    new cdk.CfnOutput(this, 'WebAclArn', { value: acl.attrArn });
    new cdk.CfnOutput(this, 'WebAclId', { value: acl.attrId });
    new cdk.CfnOutput(this, 'WafLogGroup', { value: wafLogs.logGroupName });
    new cdk.CfnOutput(this, 'RateAction', { value: rateAction });
  }
}
