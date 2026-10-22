import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
import android_release as release


class ReleaseTests(unittest.TestCase):
    def fake_api(self, method, path, data=None, binary=False):
        self.calls.append((method, path))
        if path == '/actions/runs/1':
            return {'conclusion': 'success', 'event': 'pull_request_target',
                    'path': '.github/workflows/version-release.yml',
                    'head_repository': {'full_name': release.REPO}, 'head_sha': 'b' * 40}
        if path.startswith('/commits/'):
            return [{'number': 3, 'merged_at': '2026-10-22', 'base': {'ref': 'main'}}]
        if path == '/pulls/3':
            metadata = {'schema': 1, 'version': '0.2.0', 'tagPrefix': 'v',
                        'mainBranch': 'main', 'branch': 'feature/android-releases'}
            return {'merged': True, 'merge_commit_sha': 'a' * 40,
                    'head': {'sha': 'b' * 40, 'ref': 'feature/android-releases',
                             'repo': {'full_name': release.REPO}},
                    'body': '<!-- release-metadata ' + json.dumps(metadata) + ' -->'}
        if path == '/git/ref/tags/v0.2.0':
            return {'object': {'type': 'tag', 'sha': 'c' * 40}}
        if path == '/git/tags/' + 'c' * 40:
            return {'object': {'type': 'commit', 'sha': 'a' * 40}}
        if path == '/compare/' + 'a' * 40 + '...main':
            return {'merge_base_commit': {'sha': 'a' * 40}}
        if path == '/releases/tags/v0.2.0':
            raise HTTPError(path, 404, 'Not found', {}, None)
        raise AssertionError((method, path))

    def setUp(self):
        self.calls = []

    def test_workflow_run_builds_merge_commit_instead_of_source_head(self):
        event = {'repository': {'full_name': release.REPO}, 'workflow_run': {'id': 1}}
        with patch.object(release, 'api', self.fake_api):
            result = release.resolve(event)
        self.assertEqual(result['sha'], 'a' * 40)
        self.assertEqual(result['tag'], 'v0.2.0')
        self.assertEqual(result['skip'], 'false')

    def test_unmerged_source_does_not_build_or_use_signing_secrets(self):
        def api(method, path, *args, **kwargs):
            return [] if path.startswith('/commits/') else self.fake_api(method, path, *args, **kwargs)
        with patch.object(release, 'api', api):
            self.assertEqual(release.resolve({'repository': {'full_name': release.REPO},
                                            'workflow_run': {'id': 1}}), {'skip': 'true'})

    def test_untrusted_origin_and_failed_run_are_rejected(self):
        for changed in ({'conclusion': 'failure'}, {'event': 'pull_request'},
                        {'head_repository': {'full_name': 'attacker/fork'}}):
            def api(method, path, *args, **kwargs):
                return {**self.fake_api(method, path, *args, **kwargs), **changed}
            with patch.object(release, 'api', api), self.assertRaises(ValueError):
                release.resolve({'repository': {'full_name': release.REPO}, 'workflow_run': {'id': 1}})

    def test_tag_must_be_annotated_and_reachable_from_main(self):
        for changed_path, response in (
                ('/git/ref/tags/v0.2.0', {'object': {'type': 'commit', 'sha': 'a' * 40}}),
                ('/compare/' + 'a' * 40 + '...main', {'merge_base_commit': {'sha': 'd' * 40}})):
            def api(method, path, *args, **kwargs):
                return response if path == changed_path else self.fake_api(method, path, *args, **kwargs)
            with patch.object(release, 'api', api), self.assertRaises(ValueError):
                release.verified_commit('v0.2.0')

    def test_invalid_tag_and_repository_are_rejected_before_output(self):
        for tag in ('v0.2.0\nsha=malicious', 'v00.2.0', 'main', '../../secret'):
            with self.assertRaises(ValueError):
                release.verified_commit(tag)
        with self.assertRaises(ValueError):
            release.resolve({'repository': {'full_name': 'attacker/fork'}})

    def test_published_asset_checksums_and_prerelease_flag_are_required(self):
        apk, checksum = release.names('v0.2.0')
        digest = hashlib.sha256(b'apk').hexdigest()
        record = {'prerelease': True, 'assets': [
            {'name': apk, 'id': 1, 'digest': 'sha256:' + digest}, {'name': checksum, 'id': 2}]}
        with patch.object(release, 'api', return_value=f'{digest}  {apk}\n'.encode()):
            release.verify_published(record, 'v0.2.0')
        with patch.object(release, 'api', return_value=b'wrong'), self.assertRaises(ValueError):
            release.verify_published(record, 'v0.2.0')
        record['prerelease'] = False
        with self.assertRaises(ValueError):
            release.verify_published(record, 'v0.2.0')

    def test_different_existing_draft_asset_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            apk, checksum = release.names('v0.2.0')
            (directory / apk).write_bytes(b'new-apk')
            (directory / checksum).write_text(hashlib.sha256(b'new-apk').hexdigest() + f'  {apk}\n')
            draft = {'id': 1, 'draft': True, 'assets': [{'name': apk, 'digest': 'sha256:other'}]}
            with patch.object(release, 'verified_commit', return_value='a' * 40), \
                    patch.object(release, 'release_for', return_value=draft), \
                    patch.object(release, 'api') as api, self.assertRaises(ValueError):
                release.publish('v0.2.0', directory)
            api.assert_not_called()


if __name__ == '__main__':
    unittest.main()
