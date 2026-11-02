import { execFileSync } from 'child_process';
import { CACHE_POLICY_KEYS, SHARED_CACHE_POLICY_EXPORT_PREFIX, StagingCachePolicyMode } from '../lib/cache-policies';

export function stagingCachePolicyMode(exports: unknown): StagingCachePolicyMode {
  if (!Array.isArray(exports)) throw new Error('CloudFormation did not return an exports list');
  const expectedNames = [
    ...CACHE_POLICY_KEYS.map(key => `${SHARED_CACHE_POLICY_EXPORT_PREFIX}-${key}`),
    `${SHARED_CACHE_POLICY_EXPORT_PREFIX}-calculatorTtlSeconds`,
  ];
  const present = exports.filter(item => expectedNames.includes(item?.Name));
  if (present.length === 0) return 'local';

  const missing = expectedNames.filter(name => !present.some(item => item.Name === name && item.Value));
  if (missing.length) {
    throw new Error(`Shared cache policy exports are incomplete: ${missing.join(', ')}`);
  }
  return 'shared';
}

if (require.main === module) {
  // The AWS CLI handles pagination. Failed lookups must stop deployment, not
  // silently choose local policies and recreate resources after migration.
  const response = JSON.parse(execFileSync('aws', [
    'cloudformation', 'list-exports', '--region', 'eu-central-1', '--output', 'json',
  ], { encoding: 'utf8' }));
  const mode = stagingCachePolicyMode(response.Exports);
  console.error(mode === 'local'
    ? 'Production has not published shared policies; preserving existing staging policies.'
    : 'Using the six exported production cache policies.');
  process.stdout.write(`${mode}\n`);
}
