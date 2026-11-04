"""Remove only the unchanged source branch of a verified published release PR."""
import argparse
import base64
import json
import os
import re
import subprocess
from urllib.error import HTTPError
from urllib.parse import quote, urlencode

import android_release as release

BRANCH = re.compile(r'(feature|feat|fix|bugfix|chore|docs|refactor|test|ci|perf|build|release)/[A-Za-z0-9][A-Za-z0-9._/-]*\Z')


def delete_branch(branch, head_sha):
    # This command can only delete a ref. Its explicit lease makes the server
    # reject deletion if new work arrives after our API checks; it never rewrites
    # branch history. Authentication stays in the child environment, not argv.
    env = os.environ.copy()
    index = int(env.get('GIT_CONFIG_COUNT', '0'))
    env['GIT_CONFIG_COUNT'] = str(index + 1)
    env[f'GIT_CONFIG_KEY_{index}'] = 'http.https://github.com/.extraheader'
    credential = base64.b64encode(('x-access-token:' + env['GITHUB_TOKEN']).encode()).decode()
    env[f'GIT_CONFIG_VALUE_{index}'] = 'AUTHORIZATION: basic ' + credential
    env['GIT_TERMINAL_PROMPT'] = '0'
    result = subprocess.run([
        'git', 'push', '--porcelain', f'--force-with-lease=refs/heads/{branch}:{head_sha}',
        f'https://github.com/{release.REPO}.git', f':refs/heads/{branch}',
    ], env=env, capture_output=True, text=True, timeout=60)
    if result.returncode == 0:
        return 'deleted'
    current = branch_ref(branch)
    if current is None:
        return 'already-absent'
    if current['object'].get('sha') != head_sha:
        return 'preserved-new-work'
    raise RuntimeError('Git rejected branch cleanup; the branch was preserved')


def branch_ref(branch):
    try:
        return release.api('GET', '/git/ref/heads/' + quote(branch, safe=''))
    except HTTPError as error:
        if error.code != 404:
            raise
        error.close()
        return None


def cleanup(tag, expected_sha):
    sha = release.verified_commit(tag)
    if sha != expected_sha:
        raise ValueError('Release commit changed; refusing branch cleanup')
    published = release.release_for(tag)
    if not published or published.get('draft') or published.get('tag_name') != tag:
        raise ValueError('Branch cleanup requires a published release')
    release.verify_published(published, tag)

    matches = []
    page = 1
    while True:
        candidates = release.api('GET', f'/commits/{sha}/pulls?per_page=100&page={page}')
        for candidate in candidates:
            pr = release.api('GET', f'/pulls/{int(candidate["number"])}')
            head, base = pr['head'], pr['base']
            if (not pr.get('merged') or pr['merge_commit_sha'] != sha
                    or base['ref'] != 'main' or base['repo']['full_name'] != release.REPO
                    or (head.get('repo') or {}).get('full_name') != release.REPO):
                continue
            markers = release.MARKER.findall(pr.get('body') or '')
            if len(markers) != 1:
                continue
            metadata = json.loads(markers[0])
            if (metadata.get('schema') == 1 and 'v' + metadata.get('version', '') == tag
                    and metadata.get('tagPrefix') == 'v' and metadata.get('mainBranch') == 'main'
                    and metadata.get('branch') == head['ref']):
                matches.append(pr)
        if len(candidates) < 100:
            break
        page += 1
    if len(matches) != 1:
        raise ValueError('Expected exactly one merged release PR')

    pr = matches[0]
    branch, head_sha = pr['head']['ref'], pr['head']['sha']
    if not BRANCH.fullmatch(branch) or '..' in branch or branch.endswith('/'):
        raise ValueError('Not a temporary product branch')
    ref = branch_ref(branch)
    if ref is None:
        return {'status': 'already-absent', 'branch': branch}
    if ref['object'].get('type') != 'commit' or ref['object'].get('sha') != head_sha:
        return {'status': 'preserved-new-work', 'branch': branch}
    details = release.api('GET', '/branches/' + quote(branch, safe=''))
    if details.get('protected'):
        return {'status': 'preserved-protected', 'branch': branch}
    query = urlencode({'state': 'open', 'head': release.REPO.split('/')[0] + ':' + branch, 'per_page': 100})
    if release.api('GET', '/pulls?' + query):
        return {'status': 'preserved-open-pr', 'branch': branch}
    # Re-read immediately before deletion, after the slower publication/PR checks.
    current = branch_ref(branch)
    if current is None:
        return {'status': 'already-absent', 'branch': branch}
    if current['object'].get('type') != 'commit' or current['object'].get('sha') != head_sha:
        return {'status': 'preserved-new-work', 'branch': branch}
    return {'status': delete_branch(branch, head_sha), 'branch': branch, 'pr': pr['number']}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--sha', required=True)
    args = parser.parse_args()
    print(json.dumps(cleanup(args.tag, args.sha)))


if __name__ == '__main__':
    main()
