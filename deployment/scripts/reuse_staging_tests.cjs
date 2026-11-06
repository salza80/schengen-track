const { execFileSync } = require('node:child_process');

const workflowPath = '.github/workflows/deploy-stage.yml';
const requiredTestSteps = [
  'Check i18n translations', 'Run tests', 'Test Facebook web login workaround enabled',
  'Run MCP server tests', 'Compile production assets', 'Build CDK', 'Run CDK tests',
];

function completeList(payload, key) {
  return Array.isArray(payload?.[key]) && Number.isInteger(payload.total_count)
    && payload.total_count === payload[key].length;
}

function findReusableStagingRun(repository, sha, api) {
  if (!/^[a-z0-9_-]+\/[a-z0-9][a-z0-9_.-]*$/i.test(repository || '')
      || !/^[a-f0-9]{40}$/.test(sha || '')) return null;

  const runs = api(`repos/${repository}/actions/workflows/deploy-stage.yml/runs?event=push&branch=master&head_sha=${sha}&per_page=100`);
  if (!completeList(runs, 'workflow_runs')) return null;
  const matching = runs.workflow_runs.filter(run => run.path === workflowPath
    && run.head_sha === sha && run.head_branch === 'master' && run.event === 'push');
  if (!matching.length || matching.some(run => !Number.isSafeInteger(run.run_number))) return null;
  const run = matching.sort((a, b) => b.run_number - a.run_number)[0];
  if (!Number.isSafeInteger(run.id) || run.id <= 0 || run.status !== 'completed'
      || run.conclusion !== 'success' || run.repository?.full_name !== repository
      || run.head_repository?.full_name !== repository) return null;

  const jobs = api(`repos/${repository}/actions/runs/${run.id}/jobs?filter=latest&per_page=100`);
  if (!completeList(jobs, 'jobs')) return null;
  const tests = jobs.jobs.filter(job => job.name === 'tests / tests');
  if (tests.length !== 1) return null;
  const test = tests[0];
  if (test.run_id !== run.id || test.head_sha !== sha || test.status !== 'completed'
      || test.conclusion !== 'success' || !Array.isArray(test.steps)) return null;
  if (!test.steps.every(step => step.status === 'completed' && step.conclusion === 'success')) return null;
  if (!requiredTestSteps.every(name => test.steps.some(step => step.name === name
      && step.status === 'completed' && step.conclusion === 'success'))) return null;
  return run.id;
}

function reusableStagingRun(repository, sha, api) {
  try {
    return findReusableStagingRun(repository, sha, api);
  } catch {
    return null;
  }
}

function githubApi(route) {
  return JSON.parse(execFileSync('gh', ['api', '--method', 'GET', route,
    '-H', 'Accept: application/vnd.github+json', '-H', 'X-GitHub-Api-Version: 2022-11-28'], {
    encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe'],
  }));
}

if (require.main === module) {
  const run = reusableStagingRun(process.env.GITHUB_REPOSITORY, process.env.RELEASE_SHA, githubApi);
  // Never print API responses, command errors or authentication material.
  if (run === null) console.error('No verified passing staging run found; running the test suite.');
  console.log(`reuse_tests=${run !== null}`);
  if (run !== null) console.log(`staging_run_id=${run}`);
}

module.exports = { reusableStagingRun };
