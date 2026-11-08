const { execFileSync } = require('node:child_process');

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function releaseRevision(ref, sha, runGit = git) {
  if (typeof ref !== 'string' || (ref !== 'refs/heads/master' && !ref.startsWith('refs/tags/'))
      || !/^[a-f0-9]{40}$/.test(sha || '')) {
    throw new Error('Run production releases from master or a release tag.');
  }
  let commit;
  try {
    runGit(['check-ref-format', ref]);
    // Peel annotated tags and pin once; subsequent jobs never resolve a moving ref.
    commit = runGit(['rev-parse', '--verify', `${sha}^{commit}`]).trim();
  } catch {
    throw new Error('Unable to resolve the requested release commit.');
  }
  if (!/^[a-f0-9]{40}$/.test(commit)) throw new Error('Invalid release commit.');
  try {
    runGit(['merge-base', '--is-ancestor', commit, 'origin/master']);
  } catch {
    throw new Error('The release commit must belong to master.');
  }
  return commit;
}

if (require.main === module) {
  try {
    console.log(`sha=${releaseRevision(process.env.RELEASE_REF, process.env.RELEASE_SHA)}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { releaseRevision };
