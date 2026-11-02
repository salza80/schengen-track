import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { spawnSync } from 'child_process';
import { CACHE_POLICY_KEYS, SHARED_CACHE_POLICY_EXPORT_PREFIX, stagingCachePolicyProps } from '../lib/cache-policies';
import { stagingCachePolicyMode } from '../scripts/staging-cache-policy-mode';

const completeExports = [
  ...CACHE_POLICY_KEYS.map((key, index) => ({
    Name: `${SHARED_CACHE_POLICY_EXPORT_PREFIX}-${key}`,
    Value: `policy-${index}`,
  })),
  { Name: `${SHARED_CACHE_POLICY_EXPORT_PREFIX}-calculatorTtlSeconds`, Value: '2592000' },
];

test('staging retains local policies only while all shared exports are absent', () => {
  expect(stagingCachePolicyMode([])).toBe('local');
  expect(stagingCachePolicyMode([{ Name: 'UnrelatedExport', Value: 'unrelated' }])).toBe('local');
  expect(stagingCachePolicyProps('local', 2592000)).toEqual({ publicCalculatorCacheTtlSeconds: 2592000 });
});

test('staging imports policies once the complete shared contract exists', () => {
  expect(stagingCachePolicyMode(completeExports)).toBe('shared');
  expect(stagingCachePolicyProps('shared', 2592000)).toEqual({ sharedCachePolicyRole: 'consumer' });
});

test('partial, empty, and unreadable exports fail instead of recreating local policies', () => {
  expect(() => stagingCachePolicyMode(completeExports.slice(0, -1))).toThrow('exports are incomplete');
  expect(() => stagingCachePolicyMode(completeExports.map((item, index) => index === 0 ? { ...item, Value: '' } : item))).toThrow('exports are incomplete');
  expect(() => stagingCachePolicyMode(undefined)).toThrow('did not return an exports list');
  expect(() => stagingCachePolicyProps('typo', 2592000)).toThrow('must be local or shared');
});

const workflow = require('js-yaml').load(fs.readFileSync(path.join(__dirname, '../../.github/workflows/deploy-app.yml'), 'utf8'));
const deployScript = workflow.jobs.deploy.steps.find((step: any) => step.name === 'CDK Deploy').run;

test.each([
  { stack: 'RailsLambdaStack', mode: 'local', lookupStatus: '0' },
  { stack: 'RailsLambdaStack', mode: 'shared', lookupStatus: '0' },
  { stack: 'RailsLambdaStack', mode: '', lookupStatus: '1' },
  { stack: 'SchengTrackProd', mode: '', lookupStatus: '1' },
])('deployment shell respects the staging transition and stops on lookup errors: $stack/$mode/$lookupStatus', ({ stack, mode, lookupStatus }) => {
  const taskDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'schengen-cache-rollout-'));
  const deployedArguments = path.join(taskDirectory, 'deployed-arguments');
  const lookupArguments = path.join(taskDirectory, 'lookup-arguments');
  try {
    // Run the real workflow shell with only the two external commands replaced.
    const result = spawnSync('bash', ['-c', `
      npx() {
        printf '%s\\n' "$@" > "$LOOKUP_ARGUMENTS"
        printf '%s\\n' "$MOCK_MODE"
        return "$MOCK_LOOKUP_STATUS"
      }
      cdk() { printf '%s\\n' "$@" > "$DEPLOYED_ARGUMENTS"; }
      ${deployScript}
    `], {
      encoding: 'utf8',
      env: {
        ...process.env,
        STACK_NAME: stack,
        MOCK_MODE: mode,
        MOCK_LOOKUP_STATUS: lookupStatus,
        DEPLOYED_ARGUMENTS: deployedArguments,
        LOOKUP_ARGUMENTS: lookupArguments,
      },
    });
    if (stack === 'RailsLambdaStack' && lookupStatus !== '0') {
      expect(result.status).not.toBe(0);
      expect(fs.existsSync(deployedArguments)).toBe(false);
      return;
    }
    expect(result.status).toBe(0);
    const args = fs.readFileSync(deployedArguments, 'utf8').trim().split('\n');
    expect(args).toEqual([
      'deploy', stack, '--exclusively', '--require-approval', 'never',
      ...(stack === 'RailsLambdaStack' ? ['--context', `stagingCachePolicies=${mode}`] : []),
    ]);
    if (stack === 'RailsLambdaStack') {
      expect(fs.readFileSync(lookupArguments, 'utf8').trim().split('\n')).toEqual([
        'ts-node', '--prefer-ts-exts', 'scripts/staging-cache-policy-mode.ts',
      ]);
    } else {
      expect(fs.existsSync(lookupArguments)).toBe(false);
    }
  } finally {
    fs.rmSync(taskDirectory, { recursive: true, force: true });
  }
});
