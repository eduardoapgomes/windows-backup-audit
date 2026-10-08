"""Bounded deterministic MinHash + banded LSH; advisory structural similarity only."""
from collections import defaultdict
import hashlib
import ntpath
import random

PERMUTATIONS = 64
BANDS = 16
ROWS = 4
PRIME = (1 << 61) - 1
_rng = random.Random(20261008)
COEFFICIENTS = [(_rng.randrange(1, PRIME), _rng.randrange(PRIME)) for _ in range(PERMUTATIONS)]
SCHEME = 'affine61-sha256-v1-64x16x4-seed20261008'


def signature(names):
    result = [PRIME] * PERMUTATIONS
    for name in names:
        value = int.from_bytes(hashlib.sha256(name.encode('utf-8')).digest()[:8], 'big') % PRIME
        for i, (a, b) in enumerate(COEFFICIENTS):
            result[i] = min(result[i], (a * value + b) % PRIME)
    return result


def compare_folders(catalog, previous=None, max_groups=5000, max_names=4096, max_bucket=64, max_pairs=50000):
    groups = defaultdict(set)
    paths = {entry['path'].lower().replace('/', '\\'): entry['path'] for entry in catalog['groups']}
    for file in catalog['files']:
        if not file['hidden']:
            groups[file['group']].add(ntpath.relpath(file['source'], paths[file['group']]).casefold())
    old = {}
    if previous and previous.get('scheme') == SCHEME:
        old = {item['path']: item for item in previous.get('signatures', []) if isinstance(item, dict) and 'path' in item}
    selected = sorted(groups, key=lambda key: (-len(groups[key]), key))[:max_groups]
    sketches, manifests, reused = [], {}, 0
    for group in selected:
        names = sorted(groups[group])[:max_names]
        if len(names) < 2:
            continue
        fingerprint = hashlib.sha256('\0'.join(names).encode('utf-8')).hexdigest()
        cached = old.get(paths[group], {})
        cached_signature = cached.get('signature', [])
        if cached.get('fingerprint') == fingerprint and len(cached_signature) == PERMUTATIONS and all(type(x) is int and 0 <= x < PRIME for x in cached_signature):
            sketch = cached_signature
            reused += 1
        else:
            sketch = signature(names)
        sketches.append({'path': paths[group], 'signature': sketch, 'fingerprint': fingerprint,
                         'names_used': len(names), 'names_total': len(groups[group]), 'truncated': len(groups[group]) > max_names})
        manifests[paths[group]] = set(names)
    buckets = defaultdict(list)
    for i, item in enumerate(sketches):
        for band in range(BANDS):
            buckets[(band, tuple(item['signature'][band * ROWS:(band + 1) * ROWS]))].append(i)
    candidates, saturated = set(), 0
    limited = False
    for bucket in buckets.values():
        if len(bucket) > max_bucket:
            saturated += 1
            continue
        for index, left in enumerate(bucket):
            for right in bucket[index + 1:]:
                if len(candidates) >= max_pairs:
                    limited = True
                    break
                candidates.add((left, right))
            if limited: break
        if limited: break
    pairs = []
    for left, right in sorted(candidates):
        a, b = sketches[left], sketches[right]
        x, y = manifests[a['path']], manifests[b['path']]
        shared = len(x & y)
        exact = shared / len(x | y)
        if shared >= 2 and exact >= 0.5:
            pairs.append({'left': a['path'], 'right': b['path'], 'shared_names': shared,
                'jaccard': round(exact, 5), 'minhash_estimate': sum(i == j for i, j in zip(a['signature'], b['signature'])) / PERMUTATIONS,
                'truncated': a['truncated'] or b['truncated'], 'action': 'REVIEW_ONLY'})
    pairs.sort(key=lambda pair: (-pair['jaccard'], pair['left'], pair['right']))
    return {'scheme': SCHEME, 'groups_available': len(groups), 'groups_sketches': len(sketches),
            'signatures_reused': reused, 'candidates_compared': len(candidates), 'saturated_buckets': saturated,
            'candidate_limit_reached': limited, 'groups_limited': len(groups) > max_groups,
            'pairs': pairs[:500], 'pairs_found': len(pairs), 'signatures': sketches,
            'warning': 'Nomes relativos, não assunto ou igualdade de conteúdo. LSH pode omitir relações. Jaccard conferido nos conjuntos limitados; até 500 pares exibidos.'}
