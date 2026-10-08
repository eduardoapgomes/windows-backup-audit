import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('hierarchy', Path(__file__).parents[1] / 'tools' / 'analyze_hierarchy.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def row(path, digest='a' * 64):
    return {'Source': path, 'Bytes': '10', 'SHA256': digest, 'Status': 'NEEDS_COPY'}

class HierarchyTests(unittest.TestCase):
    def test_fingerprint_order_and_content(self):
        rows = [row(r'C:\docs\a.txt'), row(r'C:\docs\b.txt')]
        first = module.analyze(rows)['groups'][0]['observed_fingerprint']
        self.assertEqual(first, module.analyze(list(reversed(rows)))['groups'][0]['observed_fingerprint'])
        rows[0]['SHA256'] = 'b' * 64
        self.assertNotEqual(first, module.analyze(rows)['groups'][0]['observed_fingerprint'])

    def test_collapse_dependencies_preserve_project_boundary(self):
        result = module.analyze([row(r'C:\project\node_modules\pkg\x.js'), row(r'C:\project\src\a.js'), row(r'C:\project\docs\notes.txt')])
        self.assertEqual(result['dependency_files'], 1)
        self.assertEqual(result['groups_total'], 1)
        self.assertTrue(result['groups'][0]['project'])
        self.assertEqual(result['groups'][0]['files'], 2)

    def test_bounded_pairs_and_html_escape(self):
        result = module.analyze([row('C:\\folder' + str(i) + '\\<script>.txt') for i in range(80)])
        self.assertEqual(result['groups_compared'], 64)
        self.assertLessEqual(result['pairs_compared'], 2016)
        self.assertFalse(result['automatic_file_actions'])
        self.assertNotIn('<script>', module.render(result))
        self.assertEqual(result['scope'], 'PARTIAL_INVENTORY_ONLY')

    def test_jaccard_baseline_and_optional_ncd(self):
        data = [row('C:\\' + folder + '\\' + name) for folder in ['alpha', 'beta'] for name in ['a.txt', 'b.txt']]
        baseline = module.analyze(data)
        self.assertEqual(baseline['candidate_pairs'][0]['jaccard'], 1.0)
        self.assertIsNone(baseline['candidate_pairs'][0]['ncd_manifest'])
        self.assertIsNotNone(module.analyze(data, enable_ncd=True)['candidate_pairs'][0]['ncd_manifest'])

    def test_empty_and_missing_hash_do_not_claim_complete_folders(self):
        self.assertEqual(module.analyze([])['pairs_compared'], 0)
        self.assertFalse(module.analyze([row(r'C:\docs\a', '')])['groups'][0]['all_observed_hashes_present'])

if __name__ == '__main__':
    unittest.main()
