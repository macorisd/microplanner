"""Link verified Android releases in README without changing release source tags."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import urllib.error

import android_release as release

ROOT = f'https://github.com/{release.REPO}'
FALLBACK = f'[Browse Android releases]({ROOT}/releases)'


def version(tag):
    if not release.TAG.fullmatch(tag):
        raise ValueError('Expected a version tag')
    return tuple(map(int, tag[1:].split('.')))


def region(text, name):
    start, end = f'<!-- {name}:start -->', f'<!-- {name}:end -->'
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError(f'Expected one {name} region in README')
    left, right = text.index(start) + len(start), text.index(end)
    if left >= right:
        raise ValueError(f'Invalid {name} region in README')
    return left, right


def download_links(tag):
    apk, _ = release.names(tag)
    return (f'[Download Android APK ({tag[1:]})]({ROOT}/releases/download/{tag}/{apk})\n\n'
            f'[Release notes]({ROOT}/releases/tag/{tag})')


def update_text(text, tag):
    """Only edit the requested version cell and the managed download region."""
    target = version(tag)
    left, right = region(text, 'release-history')
    history = text[left:right]
    cells = list(re.finditer(r'^\| ([^|\r\n]+) \|', history, re.M))
    label = re.escape(tag[1:])
    matches = [cell for cell in cells if re.fullmatch(
        rf'(?:{label}(?: \(unreleased\))?|\[{label}\]\([^)]+\))', cell[1])]
    if len(matches) != 1:
        raise ValueError(f'Expected exactly one history row for {tag}')
    cell = matches[0]
    history = (history[:cell.start(1)] + f'[{tag[1:]}]({ROOT}/releases/tag/{tag})'
               + history[cell.end(1):])
    text = text[:left] + history + text[right:]

    left, right = region(text, 'android-download')
    current = text[left:right].strip().replace('\r\n', '\n')
    if current != FALLBACK:
        match = re.search(r'\[Download Android APK \(([0-9.]+)\)\]', current)
        if not match or current != download_links('v' + match[1]):
            raise ValueError('Unexpected content in managed Android download region')
        if version('v' + match[1]) > target:
            return text  # Retrying an older release must never downgrade the download.
    newline = '\r\n' if '\r\n' in text else '\n'
    return text[:left] + newline + download_links(tag).replace('\n', newline) + newline + text[right:]


def update_readme(tag):
    sha = release.verified_commit(tag)
    if os.environ.get('RELEASE_SHA') and os.environ['RELEASE_SHA'] != sha:
        raise ValueError('Release tag changed after source verification')
    published = release.release_for(tag)
    if not published or published.get('draft') or published.get('tag_name') != tag:
        raise ValueError('README requires an already published release')
    release.verify_published(published, tag)
    for attempt in range(3):
        # Read current main, not the tagged checkout: retain intervening edits.
        record = release.api('GET', '/contents/README.md?ref=main')
        if record.get('type') != 'file' or record.get('encoding') != 'base64':
            raise ValueError('Expected a base64 README file on main')
        original = base64.b64decode(''.join(record['content'].split()), validate=True).decode('utf-8')
        updated = update_text(original, tag)
        if updated == original:
            return {'status': 'unchanged', 'tag': tag}
        try:
            result = release.api('PUT', '/contents/README.md', {
                'branch': 'main', 'sha': record['sha'],
                'message': f'docs: link published Android release {tag}',
                'content': base64.b64encode(updated.encode('utf-8')).decode('ascii'),
            })
            return {'status': 'updated', 'tag': tag, 'commit': result['commit']['sha']}
        except urllib.error.HTTPError as error:
            error.close()
            if error.code != 409 or attempt == 2:
                raise
            # Reload/reapply rather than overwrite a concurrent edit.
    raise AssertionError('Unreachable retry state')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['check', 'publish'])
    parser.add_argument('--tag', required=True)
    args = parser.parse_args()
    if args.command == 'check':
        update_text(Path('README.md').read_text(encoding='utf-8'), args.tag)
        print(f'Checked README release regions and history row for {args.tag}')
    else:
        print(json.dumps(update_readme(args.tag)))


if __name__ == '__main__':
    main()
