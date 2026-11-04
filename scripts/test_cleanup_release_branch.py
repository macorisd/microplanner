import copy
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from urllib.error import HTTPError
import android_release as release
import cleanup_release_branch as cleanup


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.deletions = []
        self.ref_reads = 0
        self.ref_sha = 'b' * 40
        self.second_sha = self.ref_sha
        self.protected = False
        self.open_prs = []
        self.published = {'draft': False, 'tag_name': 'v0.11.1'}
        metadata = {'schema': 1, 'version': '0.11.1', 'tagPrefix': 'v',
                    'mainBranch': 'main', 'branch': 'fix/form-submit-and-direct-pickers'}
        self.pr = {'number': 17, 'merged': True, 'merge_commit_sha': 'a' * 40,
                   'base': {'ref': 'main', 'repo': {'full_name': release.REPO}},
                   'head': {'ref': metadata['branch'], 'sha': self.ref_sha,
                            'repo': {'full_name': release.REPO}},
                   'body': '<!-- release-metadata ' + json.dumps(metadata) + ' -->'}

    def api(self, method, path, *args, **kwargs):
        self.calls.append((method, path))
        if path.startswith('/commits/'):
            return [{'number': 17}]
        if path == '/pulls/17':
            return copy.deepcopy(self.pr)
        if path.startswith('/git/ref/heads/'):
            self.ref_reads += 1
            sha = self.ref_sha if self.ref_reads == 1 else self.second_sha
            if sha is None:
                raise HTTPError(path, 404, 'Missing', {}, None)
            return {'object': {'type': 'commit', 'sha': sha}}
        if path.startswith('/branches/'):
            return {'protected': self.protected}
        if path.startswith('/pulls?'):
            return self.open_prs
        if method == 'DELETE':
            return b''
        raise AssertionError((method, path))

    def run_cleanup(self):
        with patch.object(release, 'verified_commit', return_value='a' * 40), \
                patch.object(release, 'release_for', return_value=self.published), \
                patch.object(release, 'verify_published') as verified, \
                patch.object(release, 'api', self.api), \
                patch.object(cleanup, 'delete_branch', self.delete):
            result = cleanup.cleanup('v0.11.1', 'a' * 40)
            verified.assert_called_once_with(self.published, 'v0.11.1')
            return result

    def delete(self, branch, sha):
        self.deletions.append((branch, sha))
        return 'deleted'

    def assert_preserved(self):
        self.assertFalse(any(method == 'DELETE' for method, _ in self.calls))
        self.assertEqual(self.deletions, [])

    def test_deletes_only_verified_merged_head_after_publication(self):
        self.assertEqual(self.run_cleanup()['status'], 'deleted')
        self.assertEqual(self.deletions, [('fix/form-submit-and-direct-pickers', 'b' * 40)])
        self.assertEqual(self.ref_reads, 2)

    def test_final_deletion_uses_an_exact_head_lease_and_never_exposes_token(self):
        with patch.dict(os.environ, {'GITHUB_TOKEN': 'private-test-token'}), \
                patch.object(cleanup.subprocess, 'run', return_value=SimpleNamespace(returncode=0)) as run:
            self.assertEqual(cleanup.delete_branch('fix/example', 'b' * 40), 'deleted')
            argv = run.call_args.args[0]
            self.assertIn('--force-with-lease=refs/heads/fix/example:' + 'b' * 40, argv)
            self.assertEqual(argv[-1], ':refs/heads/fix/example')
            self.assertNotIn('private-test-token', ' '.join(argv))

    def test_final_deletion_race_rejects_new_commits_instead_of_retrying(self):
        with patch.dict(os.environ, {'GITHUB_TOKEN': 'private-test-token'}), \
                patch.object(cleanup.subprocess, 'run', return_value=SimpleNamespace(returncode=1)) as run, \
                patch.object(cleanup, 'branch_ref', return_value={'object': {'sha': 'c' * 40}}):
            self.assertEqual(cleanup.delete_branch('fix/example', 'b' * 40), 'preserved-new-work')
            self.assertEqual(run.call_count, 1)

    def test_new_commits_on_branch_are_preserved(self):
        self.ref_sha = 'c' * 40
        self.assertEqual(self.run_cleanup()['status'], 'preserved-new-work')
        self.assert_preserved()

    def test_branch_moving_during_checks_is_preserved(self):
        self.second_sha = 'c' * 40
        self.assertEqual(self.run_cleanup()['status'], 'preserved-new-work')
        self.assert_preserved()

    def test_protected_branch_is_preserved(self):
        self.protected = True
        self.assertEqual(self.run_cleanup()['status'], 'preserved-protected')
        self.assert_preserved()

    def test_reused_branch_with_open_pr_is_preserved(self):
        self.open_prs = [{'number': 18}]
        self.assertEqual(self.run_cleanup()['status'], 'preserved-open-pr')
        self.assert_preserved()

    def test_repeated_cleanup_handles_absent_branch(self):
        self.ref_sha = None
        self.assertEqual(self.run_cleanup()['status'], 'already-absent')
        self.assert_preserved()

    def test_unmerged_fork_or_unrelated_merge_cannot_delete(self):
        variants = [
            {'merged': False}, {'merge_commit_sha': 'c' * 40},
            {'head': {**self.pr['head'], 'repo': {'full_name': 'other/repo'}}},
            {'base': {'ref': 'main', 'repo': {'full_name': 'other/repo'}}},
            {'body': ''},
        ]
        original = copy.deepcopy(self.pr)
        for variant in variants:
            with self.subTest(variant=variant):
                self.pr = {**copy.deepcopy(original), **variant}
                with self.assertRaisesRegex(ValueError, 'exactly one'):
                    self.run_cleanup()
                self.assert_preserved()

    def test_main_or_non_temporary_branch_cannot_delete(self):
        for branch in ['main', 'release', 'fix/../main']:
            with self.subTest(branch=branch):
                self.pr['head']['ref'] = branch
                self.pr['body'] = '<!-- release-metadata ' + json.dumps({
                    'schema': 1, 'version': '0.11.1', 'tagPrefix': 'v',
                    'mainBranch': 'main', 'branch': branch}) + ' -->'
                with self.assertRaisesRegex(ValueError, 'temporary'):
                    self.run_cleanup()
                self.assert_preserved()

    def test_unpublished_release_never_reaches_deletion(self):
        self.published['draft'] = True
        with self.assertRaisesRegex(ValueError, 'published'):
            self.run_cleanup()
        self.assert_preserved()

    def test_workflow_cleanup_depends_on_all_successful_publication_jobs(self):
        workflow = (Path(__file__).parents[1] / '.github/workflows/android-release.yml').read_text()
        job = workflow.split('\n  cleanup:\n', 1)[1]
        for text in ['needs: [resolve, build, publish, readme]', "needs.readme.result == 'success'",
                     "needs.build.result == 'success'", "needs.publish.result == 'success'", '!cancelled()',
                     'ref: ${{ needs.resolve.outputs.sha }}']:
            self.assertIn(text, job)
        self.assertNotIn('continue-on-error', job)


if __name__ == '__main__':
    unittest.main()
