"""Resolve trusted merged releases and publish immutable Android assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

REPO = 'macorisd/microplanner'
TAG = re.compile(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')
SHA1 = '7d77b708821002addfface4d26e32ef4ab6ec4ee'
MARKER = re.compile(r'<!-- release-metadata (\{[^\r\n]*\}) -->')


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected:
            redirected.remove_header('Authorization')
        return redirected


def api(method, path, data=None, binary=False):
    url = path if path.startswith('https://') else f'https://api.github.com/repos/{REPO}{path}'
    if urllib.parse.urlparse(url).hostname not in ('api.github.com', 'uploads.github.com'):
        raise ValueError('Unexpected GitHub API destination')
    headers = {'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'],
               'Accept': 'application/octet-stream' if binary else 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'microplanner-release'}
    if isinstance(data, bytes):
        headers['Content-Type'] = 'application/octet-stream'
    elif data is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(data).encode()
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.build_opener(SafeRedirect()).open(request, timeout=120) as response:
        return response.read() if binary else json.load(response)


def release_for(tag):
    try:
        return api('GET', f'/releases/tags/{tag}')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        error.close()
        return None


def names(tag):
    apk = f'microplanner-{tag[1:]}-android.apk'
    return apk, apk + '.sha256'


def verify_published(release, tag):
    apk, checksum = names(tag)
    assets = {asset['name']: asset for asset in release['assets']}
    if set(assets) != {apk, checksum} or not release['prerelease']:
        raise ValueError('Published release is incomplete or has unexpected assets')
    content = api('GET', f'/releases/assets/{assets[checksum]["id"]}', binary=True)
    digest = assets[apk].get('digest', '')
    expected = f'{digest.removeprefix("sha256:")}  {apk}\n'.encode()
    if not re.fullmatch('sha256:[0-9a-f]{64}', digest) or content != expected:
        raise ValueError('Published APK checksum does not match GitHub asset digest')


def verified_commit(tag):
    if not TAG.fullmatch(tag):
        raise ValueError('Expected a version tag such as v0.2.0')
    ref = api('GET', f'/git/ref/tags/{tag}')['object']
    if ref['type'] != 'tag':
        raise ValueError('Expected an annotated release tag')
    obj = api('GET', f'/git/tags/{ref["sha"]}')['object']
    if obj['type'] != 'commit' or not re.fullmatch('[0-9a-f]{40}', obj['sha']):
        raise ValueError('Release tag must identify a commit')
    sha = obj['sha']
    comparison = api('GET', f'/compare/{sha}...main')
    if comparison.get('merge_base_commit', {}).get('sha') != sha:
        raise ValueError('Release commit is not part of main')
    return sha


def resolve(event):
    if event['repository']['full_name'] != REPO:
        raise ValueError('Unexpected repository')
    if 'workflow_run' in event:
        run = event['workflow_run']
        actual = api('GET', f'/actions/runs/{int(run["id"])}')
        if (actual['conclusion'] != 'success' or actual['event'] != 'pull_request_target'
                or actual['path'] != '.github/workflows/version-release.yml'
                or actual['head_repository']['full_name'] != REPO):
            raise ValueError('Expected a successful trusted version-tag workflow')
        # The tag workflow run identifies the PR's source head, not its merge SHA.
        candidates = api('GET', f'/commits/{actual["head_sha"]}/pulls?per_page=100')
        matches = []
        for candidate in candidates:
            if not candidate.get('merged_at') or candidate['base']['ref'] != 'main':
                continue
            pr = api('GET', f'/pulls/{int(candidate["number"])}')
            markers = MARKER.findall(pr.get('body') or '')
            if not markers:
                continue
            if (not pr.get('merged') or pr['head']['sha'] != actual['head_sha']
                    or pr['head']['repo']['full_name'] != REPO or len(markers) != 1):
                continue
            metadata = json.loads(markers[0])
            tag = 'v' + metadata['version']
            if (metadata.get('schema') != 1 or metadata.get('tagPrefix') != 'v'
                    or metadata.get('mainBranch') != 'main'
                    or metadata.get('branch') != pr['head']['ref']):
                raise ValueError('Unexpected release metadata')
            if verified_commit(tag) != pr['merge_commit_sha']:
                raise ValueError('Tag and merged PR do not match')
            matches.append(tag)
        if not matches:
            return {'skip': 'true'}
        if len(set(matches)) != 1:
            raise ValueError('Ambiguous release association')
        tag = matches[0]
    else:
        tag = event['inputs']['tag']
    sha = verified_commit(tag)
    existing = release_for(tag)
    if existing and not existing['draft']:
        verify_published(existing, tag)
        return {'skip': 'true', 'tag': tag, 'sha': sha, 'version': tag[1:]}
    return {'skip': 'false', 'tag': tag, 'sha': sha, 'version': tag[1:]}


def verify_apk(apk, tag):
    if not TAG.fullmatch(tag):
        raise ValueError('Invalid tag')
    pubspec = Path('pubspec.yaml').read_text(encoding='utf-8')
    version, build = re.search(r'^version: ([0-9.]+)\+([0-9]+)$', pubspec, re.M).groups()
    if version != tag[1:] or json.loads(Path('server/package.json').read_text())['version'] != version:
        raise ValueError('Version manifests do not match the release tag')
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools'
    versions = sorted((p for p in tools.iterdir() if p.is_dir() and re.fullmatch(r'\d+\.\d+\.\d+', p.name)),
                      key=lambda p: tuple(map(int, p.name.split('.'))))
    if not versions:
        raise ValueError('Stable Android SDK build tools are missing')
    tool = versions[-1]
    suffix = '.bat' if os.name == 'nt' else ''
    certificate = subprocess.check_output([str(tool / ('apksigner' + suffix)), 'verify', '--print-certs', str(apk)], text=True)
    if f'Signer #1 certificate SHA-1 digest: {SHA1}' not in certificate:
        raise ValueError('APK signing certificate does not match the persistent release identity')
    badging = subprocess.check_output([str(tool / ('aapt' + ('.exe' if os.name == 'nt' else ''))), 'dump', 'badging', str(apk)], text=True)
    if f"package: name='com.microplanner.microplanner' versionCode='{build}' versionName='{version}'" not in badging:
        raise ValueError('APK package or version metadata is incorrect')
    if "application-label:'microplanner'" not in badging:
        raise ValueError('Unexpected application label')
    print(f'Verified Android package, version {version}+{build}, and release certificate')


def publish(tag, directory):
    sha = verified_commit(tag)
    if os.environ.get('RELEASE_SHA') and os.environ['RELEASE_SHA'] != sha:
        raise ValueError('Release tag changed after source verification')
    apk, checksum = names(tag)
    apk_data = (directory / apk).read_bytes()
    expected = f'{hashlib.sha256(apk_data).hexdigest()}  {apk}\n'.encode()
    if (directory / checksum).read_bytes() != expected:
        raise ValueError('Local APK checksum mismatch')
    release = release_for(tag)
    if release and not release['draft']:
        verify_published(release, tag)
        return
    if release is None:
        release = api('POST', '/releases', {
            'tag_name': tag, 'name': f'microplanner {tag[1:]}', 'draft': True, 'prerelease': True,
            'body': f'Android test release of microplanner {tag[1:]}.\n\n'
                    'Download the APK and install it on Android. Updates are installed manually. '
                    'Google sign-in and cloud data use https://microplanner-api.vercel.app.\n\n'
                    'The SHA-256 file verifies download integrity. Versions signed with the old '
                    'development certificate require a deliberate migration; confirm cloud data '
                    'before replacing that installation. See README.md for setup and recovery.\n',
        })
    assets = {asset['name']: asset for asset in release['assets']}
    for name, content in ((apk, apk_data), (checksum, expected)):
        if name in assets:
            if assets[name].get('digest') != 'sha256:' + hashlib.sha256(content).hexdigest():
                raise ValueError('Different asset already exists; refusing to overwrite')
            continue
        api('POST', release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(name), content)
    # Publish only after both files have uploaded and their digests are verified.
    complete = release_for(tag)
    verify_published(complete, tag)
    api('PATCH', f'/releases/{release["id"]}', {'draft': False, 'prerelease': True})
    print(f'Published {tag}: APK and checksum')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['resolve', 'verify-apk', 'publish'])
    parser.add_argument('--tag')
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--directory', type=Path, default=Path('release-assets'))
    args = parser.parse_args()
    if args.command == 'resolve':
        result = resolve(json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8')))
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            for key, value in result.items():
                output.write(f'{key}={value}\n')
        print(json.dumps(result))
    elif args.command == 'verify-apk':
        verify_apk(args.apk, args.tag)
    else:
        publish(args.tag, args.directory)


if __name__ == '__main__':
    main()
