const { reusableStagingRun } = require('../scripts/reuse_staging_tests.cjs');

const repository = 'salza80/schengen-track';
const sha = 'a'.repeat(40);
const steps = ['Check i18n translations', 'Run tests', 'Test Facebook web login workaround enabled',
  'Run MCP server tests', 'Compile production assets', 'Build CDK', 'Run CDK tests'];

function passingRun(overrides: any = {}) {
  return { id: 123, run_number: 7, path: '.github/workflows/deploy-stage.yml', event: 'push',
    head_branch: 'master', head_sha: sha, status: 'completed', conclusion: 'success',
    repository: { full_name: repository }, head_repository: { full_name: repository }, ...overrides };
}

function passingJob(overrides: any = {}) {
  return { name: 'tests / tests', run_id: 123, head_sha: sha, status: 'completed', conclusion: 'success',
    steps: steps.map(name => ({ name, status: 'completed', conclusion: 'success' })), ...overrides };
}

function apiFor(runs: any[], jobs = [passingJob()]) {
  return jest.fn((route: string) => route.includes('/jobs?')
    ? { total_count: jobs.length, jobs } : { total_count: runs.length, workflow_runs: runs });
}

test('reuses a complete successful staging push and its actual test job for the exact revision', () => {
  const api = apiFor([passingRun()]);
  expect(reusableStagingRun(repository, sha, api)).toBe(123);
  expect(api.mock.calls[0][0]).toContain(`head_sha=${sha}`);
  expect(api.mock.calls[1][0]).toContain('/runs/123/jobs?filter=latest');
});

test.each([
  { head_sha: 'b'.repeat(40) }, { head_branch: 'other' }, { event: 'pull_request' },
  { path: '.github/workflows/pr-tests.yml' }, { status: 'in_progress' }, { conclusion: 'failure' },
  { conclusion: 'cancelled' }, { repository: { full_name: 'other/repo' } },
  { head_repository: { full_name: 'fork/schengen-track' } }, { run_number: null }, { id: '123' },
])('does not trust an unrelated, incomplete or unsuccessful run: %j', override => {
  expect(reusableStagingRun(repository, sha, apiFor([passingRun(override)]))).toBeNull();
});

test.each(['failure', 'cancelled', null])('a newer %s result prevents reuse of an older success', conclusion => {
  const api = apiFor([passingRun(), passingRun({ id: 124, run_number: 8, conclusion })]);
  expect(reusableStagingRun(repository, sha, api)).toBeNull();
});

test.each([
  { name: 'deploy / deploy' }, { status: 'queued' }, { conclusion: 'skipped' },
  { head_sha: 'b'.repeat(40) }, { run_id: 999 }, { steps: [] },
])('requires a completed matching test job: %j', override => {
  expect(reusableStagingRun(repository, sha, apiFor([passingRun()], [passingJob(override)]))).toBeNull();
});

test.each(steps)('does not reuse a skipped or failed required test step: %s', name => {
  for (const conclusion of ['skipped', 'failure']) {
    const job = passingJob();
    job.steps.find((step: any) => step.name === name).conclusion = conclusion;
    expect(reusableStagingRun(repository, sha, apiFor([passingRun()], [job]))).toBeNull();
  }
});

test('does not reuse missing, ambiguous or incomplete evidence', () => {
  expect(reusableStagingRun(repository, sha, apiFor([]))).toBeNull();
  expect(reusableStagingRun(repository, sha, apiFor([passingRun()], []))).toBeNull();
  expect(reusableStagingRun(repository, sha, apiFor([passingRun()], [passingJob(), passingJob()]))).toBeNull();
  const incomplete = () => ({ total_count: 101, workflow_runs: [passingRun()] });
  expect(reusableStagingRun(repository, sha, incomplete)).toBeNull();
  expect(reusableStagingRun(repository, sha, () => ({ workflow_runs: [] }))).toBeNull();
  expect(reusableStagingRun(repository, sha, () => ({ total_count: 1, workflow_runs: [null] }))).toBeNull();
});

test('a tolerated failure or skipped setup step cannot count as a verified passing suite', () => {
  for (const conclusion of ['failure', 'skipped']) {
    const job = passingJob();
    job.steps.push({ name: 'Additional validation', status: 'completed', conclusion });
    expect(reusableStagingRun(repository, sha, apiFor([passingRun()], [job]))).toBeNull();
  }
});

test('API failures fall back to running tests without propagating authentication errors', () => {
  const api = () => { throw new Error('API request failed'); };
  expect(reusableStagingRun(repository, sha, api)).toBeNull();
  const jobsFail = (route: string) => {
    if (route.includes('/jobs?')) throw new Error('Jobs unavailable');
    return { total_count: 1, workflow_runs: [passingRun()] };
  };
  expect(reusableStagingRun(repository, sha, jobsFail)).toBeNull();
});

test('invalid revision or repository cannot construct an API request', () => {
  const api = jest.fn();
  expect(reusableStagingRun(repository, 'master', api)).toBeNull();
  expect(reusableStagingRun('../other/repo', sha, api)).toBeNull();
  expect(api).not.toHaveBeenCalled();
});
