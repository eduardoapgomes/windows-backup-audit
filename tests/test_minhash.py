from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'tools'))
from context_catalog import build_catalog
from folder_similarity import compare_folders, signature


def fixture(groups):
    return build_catalog([dict(Source='C:\\'+group+'\\'+name, Bytes='10', Status='NEEDS_COPY', SHA256=str(i%10)*64)
                          for i, (group, names) in enumerate(groups.items()) for name in names])

class MinHashTests(unittest.TestCase):
    def test_signature_order_independent_and_reproducible(self):
        self.assertEqual(signature(['a', 'b']), signature(['b', 'a', 'a']))
        self.assertNotEqual(signature(['a', 'b']), signature(['x', 'y']))

    def test_identical_names_different_content_only_review(self):
        result = compare_folders(fixture({'A':['a.py','b.txt'], 'B':['a.py','b.txt']}))
        self.assertEqual(len(result['pairs']), 1)
        self.assertEqual(result['pairs'][0]['jaccard'], 1)
        self.assertEqual(result['pairs'][0]['action'], 'REVIEW_ONLY')

    def test_exact_jaccard_on_candidates(self):
        common = [f'item{i}.txt' for i in range(20)]
        result = compare_folders(fixture({'A':common, 'B':common+['extra.txt']}))
        self.assertEqual(result['pairs'][0]['jaccard'], round(20/21, 5))

    def test_saturated_buckets_and_pair_limits(self):
        data = fixture({str(i):['a','b'] for i in range(70)})
        blocked = compare_folders(data)
        self.assertGreater(blocked['saturated_buckets'], 0)
        self.assertEqual(blocked['candidates_compared'], 0)
        bounded = compare_folders(data, max_bucket=100, max_pairs=12)
        self.assertTrue(bounded['candidate_limit_reached'])
        self.assertEqual(bounded['candidates_compared'], 12)

    def test_cache_reuse_requires_same_manifest(self):
        data = fixture({'A':['a','b'], 'B':['a','b']})
        first = compare_folders(data)
        second = compare_folders(data, first)
        self.assertEqual(second['signatures_reused'], 2)
        changed = compare_folders(fixture({'A':['a','c'], 'B':['a','b']}), first)
        self.assertEqual(changed['signatures_reused'], 1)

    def test_truncation_and_group_limits_explicit(self):
        result = compare_folders(fixture({'A':['a','b','c'], 'B':['a','b','c'], 'C':['d','e']}), max_names=2, max_groups=2)
        self.assertTrue(result['groups_limited'])
        self.assertTrue(result['pairs'][0]['truncated'])

    def test_empty_or_single_file_no_pairs(self):
        self.assertEqual(compare_folders(fixture({}))['pairs'], [])
        self.assertEqual(compare_folders(fixture({'A':['a'],'B':['a']}))['pairs'], [])

if __name__ == '__main__': unittest.main()
