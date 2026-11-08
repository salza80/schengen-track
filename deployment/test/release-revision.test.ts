import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const { releaseRevision } = require('../scripts/release_revision.cjs');
const script = resolve(__dirname, '../scripts/release_revision.cjs');

let directory: string;
let firstCommit: string;
let masterCommit: string;

function git(args: string[]): string {
  return execFileSync('git', args, {
    cwd: directory, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

beforeEach(() => {
  directory = mkdtempSync(join(tmpdir(), 'schengen-release-revision-'));
  git(['init', '-q', '-b', 'master']);
  git(['config', 'user.name', 'Release tests']);
  git(['config', 'user.email', 'release-tests@example.invalid']);
  git(['config', 'commit.gpgsign', 'false']);
  git(['config', 'tag.gpgsign', 'false']);
  git(['config', 'core.hooksPath', '/dev/null']);
  git(['commit', '-q', '--allow-empty', '-m', 'First release']);
  firstCommit = git(['rev-parse', 'HEAD']);
  git(['tag', 'v1.0.0']);
  git(['tag', '-a', 'v1.0.0-annotated', '-m', 'Annotated release']);
  git(['commit', '-q', '--allow-empty', '-m', 'Next release']);
  masterCommit = git(['rev-parse', 'HEAD']);
  git(['update-ref', 'refs/remotes/origin/master', masterCommit]);
});

afterEach(() => {
  rmSync(directory, { recursive: true, force: true });
});

test('pins the dispatch commit when master has advanced', () => {
  expect(releaseRevision('refs/heads/master', firstCommit, git)).toBe(firstCommit);
  expect(releaseRevision('refs/heads/master', masterCommit, git)).toBe(masterCommit);
});

test.each(['v1.0.0', 'v1.0.0-annotated'])(
  'resolves release tag %s to its older commit on master', tag => {
    const dispatchedObject = git(['rev-parse', `refs/tags/${tag}`]);
    expect(releaseRevision(`refs/tags/${tag}`, dispatchedObject, git)).toBe(firstCommit);
  },
);

test('does not follow a tag moved after dispatch', () => {
  const dispatchedObject = git(['rev-parse', 'refs/tags/v1.0.0-annotated']);
  git(['tag', '-f', 'v1.0.0-annotated', masterCommit]);
  expect(releaseRevision('refs/tags/v1.0.0-annotated', dispatchedObject, git)).toBe(firstCommit);
});

test('rejects a tag pointing to an unmerged commit', () => {
  git(['checkout', '-q', '-b', 'unmerged', firstCommit]);
  git(['commit', '-q', '--allow-empty', '-m', 'Unmerged change']);
  git(['tag', 'unmerged-release']);
  const unmergedCommit = git(['rev-parse', 'HEAD']);
  expect(() => releaseRevision('refs/tags/unmerged-release', unmergedCommit, git))
    .toThrow('The release commit must belong to master.');
});

test.each([
  ['refs/heads/feature', 'a'.repeat(40)],
  ['refs/pull/1/merge', 'a'.repeat(40)],
  [undefined, 'a'.repeat(40)],
  ['refs/heads/master', undefined],
  ['refs/heads/master', 'master'],
  ['refs/heads/master', `${'a'.repeat(40)}\nsha=other`],
])('rejects invalid dispatch %s / %s before running git', (ref, sha) => {
  const runGit = jest.fn();
  expect(() => releaseRevision(ref, sha, runGit))
    .toThrow('Run production releases from master or a release tag.');
  expect(runGit).not.toHaveBeenCalled();
});

test.each(['refs/tags/', 'refs/tags/../master', 'refs/tags/release name'])(
  'rejects malformed tag ref %s', ref => {
    expect(() => releaseRevision(ref, masterCommit, git))
      .toThrow('Unable to resolve the requested release commit.');
  },
);

test('rejects a missing commit object', () => {
  expect(() => releaseRevision('refs/tags/missing', 'f'.repeat(40), git))
    .toThrow('Unable to resolve the requested release commit.');
});

test('fails closed when the master ancestry cannot be verified', () => {
  git(['update-ref', '-d', 'refs/remotes/origin/master']);
  expect(() => releaseRevision('refs/tags/v1.0.0', firstCommit, git))
    .toThrow('The release commit must belong to master.');
});

test('writes only the pinned commit as a GitHub Actions output', () => {
  const tagObject = git(['rev-parse', 'refs/tags/v1.0.0-annotated']);
  const result = spawnSync(process.execPath, [script], {
    cwd: directory, encoding: 'utf8',
    env: { ...process.env, RELEASE_REF: 'refs/tags/v1.0.0-annotated', RELEASE_SHA: tagObject },
  });
  expect(result.status).toBe(0);
  expect(result.stdout).toBe(`sha=${firstCommit}\n`);
  expect(result.stderr).toBe('');
});

test('CLI exits unsuccessfully without publishing a revision for a feature branch', () => {
  const result = spawnSync(process.execPath, [script], {
    cwd: directory, encoding: 'utf8',
    env: { ...process.env, RELEASE_REF: 'refs/heads/feature', RELEASE_SHA: masterCommit },
  });
  expect(result.status).toBe(1);
  expect(result.stdout).toBe('');
  expect(result.stderr).toContain('Run production releases from master or a release tag.');
});
