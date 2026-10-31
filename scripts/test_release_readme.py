import base64
from contextlib import ExitStack
from pathlib import Path
import re
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import android_release as release
import release_readme as readme


def document():
    return (f'Intro stays unchanged.\n<!-- android-download:start -->\n{readme.FALLBACK}\n'
            '<!-- android-download:end -->\n\n<!-- release-history:start -->\n'
            '| Version | Changes |\n| --- | --- |\n'
            '| 0.10.1 (unreleased) | <ul><li>Keep this change text.</li></ul> |\n'
            f'| [0.10.0]({readme.ROOT}/tree/v0.10.0) | Older changes. |\n'
            '<!-- release-history:end -->\nDeveloper details stay unchanged.\n')


class ReadmeTextTests(unittest.TestCase):
    def test_published_links_preserve_change_text_and_other_versions(self):
        updated = readme.update_text(document(), 'v0.10.1')
        self.assertIn(readme.download_links('v0.10.1'), updated)
        self.assertIn(f'| [0.10.1]({readme.ROOT}/releases/tag/v0.10.1) | '
                      '<ul><li>Keep this change text.</li></ul> |', updated)
        self.assertIn(f'| [0.10.0]({readme.ROOT}/tree/v0.10.0) | Older changes. |', updated)
        self.assertTrue(updated.startswith('Intro stays unchanged.\n'))
        self.assertTrue(updated.endswith('Developer details stay unchanged.\n'))
        self.assertEqual(readme.update_text(updated, 'v0.10.1'), updated)

    def test_retrying_older_version_links_its_row_without_downgrading_download(self):
        latest = readme.update_text(document(), 'v0.10.1')
        updated = readme.update_text(latest, 'v0.10.0')
        self.assertIn(readme.download_links('v0.10.1'), updated)
        self.assertIn(f'| [0.10.0]({readme.ROOT}/releases/tag/v0.10.0) | Older changes. |', updated)
        self.assertEqual(readme.update_text(updated, 'v0.10.0'), updated)

    def test_newer_version_replaces_download_and_uses_numeric_version_order(self):
        older = readme.update_text(document(), 'v0.10.0')
        updated = readme.update_text(older, 'v0.10.1')
        self.assertIn(readme.download_links('v0.10.1'), updated)
        self.assertNotIn('/releases/download/v0.10.0/', updated)
        self.assertGreater(readme.version('v0.10.0'), readme.version('v0.9.9'))

    def test_crlf_is_preserved_and_repeated_updates_are_noops(self):
        updated = readme.update_text(document().replace('\n', '\r\n'), 'v0.10.1')
        self.assertNotIn('\n', updated.replace('\r\n', ''))
        self.assertEqual(readme.update_text(updated, 'v0.10.1'), updated)

    def test_ambiguous_missing_or_reversed_regions_and_rows_are_rejected(self):
        for text in (
                document().replace('<!-- release-history:start -->', ''),
                document() + '<!-- android-download:start -->',
                document().replace('<!-- android-download:start -->', '<!-- android-download:end -->', 1),
                document().replace('| 0.10.1 (unreleased)', '| 0.11.0 (unreleased)'),
                document().replace('<!-- release-history:end -->',
                                   '| 0.10.1 | Duplicate |\n<!-- release-history:end -->'),
                document().replace(readme.FALLBACK, 'Unexpected manual text')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                readme.update_text(text, 'v0.10.1')

    def test_invalid_tags_cannot_be_injected_into_document(self):
        for tag in ('main', 'v00.10.1', 'v0.10.1\nmalicious', '../../file'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                readme.update_text(document(), tag)

    def test_repository_readme_has_a_valid_row_for_the_manifest_version(self):
        root = Path(__file__).resolve().parents[1]
        tag = 'v' + re.search(r'^version: ([0-9.]+)\+',
                             (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)[1]
        readme.update_text((root / 'README.md').read_text(encoding='utf-8'), tag)


class ReadmePublicationTests(unittest.TestCase):
    def setUp(self):
        self.tag = 'v0.10.1'
        self.text = document()
        self.writes = []
        self.reads = 0
        self.conflicts = 0
        self.published = {'tag_name': self.tag, 'draft': False, 'id': 42}
        stack = ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(patch.object(release, 'verified_commit', return_value='a' * 40))
        stack.enter_context(patch.object(release, 'release_for', side_effect=lambda _: self.published))
        self.verify = stack.enter_context(patch.object(release, 'verify_published'))
        stack.enter_context(patch.object(release, 'api', side_effect=self.api))
        stack.enter_context(patch.dict('os.environ', {'RELEASE_SHA': 'a' * 40}))

    def api(self, method, path, data=None, **kwargs):
        if method == 'GET' and path == '/contents/README.md?ref=main':
            self.reads += 1
            return {'type': 'file', 'encoding': 'base64', 'sha': str(self.reads) * 40,
                    'content': base64.b64encode(self.text.encode()).decode()}
        if method == 'PUT' and path == '/contents/README.md':
            self.writes.append(data)
            self.assertEqual(data['branch'], 'main')
            self.assertEqual(data['sha'], str(self.reads) * 40)
            if self.conflicts:
                self.conflicts -= 1
                self.text += 'Concurrent documentation edit.\n'
                raise HTTPError(path, 409, 'Conflict', {}, None)
            self.text = base64.b64decode(data['content']).decode()
            return {'commit': {'sha': 'd' * 40}}
        raise AssertionError((method, path))

    def test_only_verified_published_release_can_commit_and_retry_is_idempotent(self):
        self.assertEqual(readme.update_readme(self.tag)['status'], 'updated')
        self.verify.assert_called_once_with(self.published, self.tag)
        self.assertEqual(len(self.writes), 1)
        self.assertEqual(readme.update_readme(self.tag)['status'], 'unchanged')
        self.assertEqual(len(self.writes), 1)

    def test_missing_draft_wrong_release_checksum_or_changed_tag_never_writes(self):
        for published in (None, {'draft': True, 'tag_name': self.tag},
                          {'draft': False, 'tag_name': 'v0.10.0'}):
            self.published = published
            with self.subTest(published=published), self.assertRaises(ValueError):
                readme.update_readme(self.tag)
        self.published = {'draft': False, 'tag_name': self.tag}
        self.verify.side_effect = ValueError('Checksum mismatch')
        with self.assertRaisesRegex(ValueError, 'Checksum'):
            readme.update_readme(self.tag)
        self.verify.side_effect = None
        with patch.object(release, 'verified_commit', return_value='b' * 40), self.assertRaisesRegex(ValueError, 'tag changed'):
            readme.update_readme(self.tag)
        self.assertEqual(self.reads, 0)
        self.assertEqual(self.writes, [])

    def test_conflict_reloads_main_and_preserves_concurrent_changes(self):
        self.conflicts = 1
        self.assertEqual(readme.update_readme(self.tag)['status'], 'updated')
        self.assertEqual(self.reads, 2)
        self.assertEqual(len(self.writes), 2)
        self.assertIn('Concurrent documentation edit.\n', self.text)
        self.assertIn(readme.download_links(self.tag), self.text)

    def test_retry_detects_another_run_already_committed_without_duplicate_write(self):
        original_api = self.api
        def api(method, path, data=None, **kwargs):
            if method == 'PUT':
                self.writes.append(data)
                self.text = readme.update_text(self.text, self.tag)
                raise HTTPError(path, 409, 'Conflict', {}, None)
            return original_api(method, path, data, **kwargs)
        with patch.object(release, 'api', side_effect=api):
            self.assertEqual(readme.update_readme(self.tag)['status'], 'unchanged')
        self.assertEqual(len(self.writes), 1)

    def test_conflicts_are_bounded_and_permissions_are_never_bypassed(self):
        self.conflicts = 4
        with self.assertRaises(HTTPError):
            readme.update_readme(self.tag)
        self.assertEqual(len(self.writes), 3)
        self.writes.clear()
        original_api = self.api
        def forbidden(method, path, data=None, **kwargs):
            if method == 'PUT':
                self.writes.append(data)
                raise HTTPError(path, 403, 'Protected branch', {}, None)
            return original_api(method, path, data, **kwargs)
        with patch.object(release, 'api', side_effect=forbidden), self.assertRaises(HTTPError):
            readme.update_readme(self.tag)
        self.assertEqual(len(self.writes), 1)

    def test_invalid_main_document_does_not_commit(self):
        self.text = 'Unrelated README with no managed regions.'
        with self.assertRaises(ValueError):
            readme.update_readme(self.tag)
        self.assertEqual(self.writes, [])


if __name__ == '__main__':
    unittest.main()
