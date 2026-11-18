#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { McpEdgeStack } from '../lib/mcp-edge-stack';

const app = new cdk.App();
new McpEdgeStack(app, 'McpEdgeLab', {
  // WAF for CloudFront must live in us-east-1; the runtime sits there too.
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: 'us-east-1' },
});
