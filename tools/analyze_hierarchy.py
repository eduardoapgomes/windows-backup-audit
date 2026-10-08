"""Read-only experiment on an inventory snapshot. Never opens source/destination files.
NCD below compares bounded path manifests, not document content or semantic topics.
"""
import argparse
import csv
import hashlib
import html
import itertools
import json
import ntpath
from pathlib import Path
import zlib

DEPENDENCY_NAMES = {'node_modules', 'site-packages'}

def parts(path):
    return path.replace('/', '\\').split('\\')

def dependency_root(path):
    segments = parts(path)
    for index, name in enumerate(segments):
        if name.lower() in DEPENDENCY_NAMES:
            return '\\'.join(segments[:index + 1])
    return None

def within(path, root):
    path, root = ntpath.normcase(path), ntpath.normcase(root).rstrip('\\')
    return path == root or path.startswith(root + '\\')

def ncd(left, right):
    """Symmetrized, practical zlib NCD. No identity or topic guarantee."""
    a, b = len(zlib.compress(left, 6)), len(zlib.compress(right, 6))
    joined = min(len(zlib.compress(left + right, 6)), len(zlib.compress(right + left, 6)))
    return (joined - min(a, b)) / max(a, b)

def analyze(rows, max_groups=64, enable_ncd=False):
    project_roots = set()
    for row in rows:
        segments = parts(row['Source'])
        lower = [value.lower() for value in segments]
        for marker in ('.git', 'node_modules'):
            if marker in lower:
                project_roots.add('\\'.join(segments[:lower.index(marker)]))
    # Longest enclosing project wins; it remains an indivisible unit for suggestions.
    project_roots = sorted(project_roots, key=lambda value: (-len(value), value.casefold()))
    groups, dependencies, tree = {}, {}, {}
    for row in rows:
        source = row['Source']
        size = int(row['Bytes'])
        dep = dependency_root(source)
        segments = parts(source)
        for depth in range(1, len(segments)):
            parent = '\\'.join(segments[:depth])
            entry = tree.setdefault(parent, {'files': 0, 'bytes': 0, 'dependency_files': 0})
            entry['files'] += 1
            entry['bytes'] += size
            entry['dependency_files'] += int(dep is not None)
        if dep:
            entry = dependencies.setdefault(dep, {'files': 0, 'bytes': 0})
            entry['files'] += 1
            entry['bytes'] += size
            continue
        if '.git' in [segment.lower() for segment in segments]:
            continue  # Only the experiment ignores Git internals; backup preserves them.
        root = next((root for root in project_roots if within(source, root)), ntpath.dirname(source))
        groups.setdefault(root, []).append(row)
    summaries = []
    for root, members in sorted(groups.items()):
        manifest = sorted({ntpath.relpath(row['Source'], root).lower() for row in members})
        canonical = sorted((ntpath.relpath(row['Source'], root), int(row['Bytes']), row.get('SHA256', '')) for row in members)
        payload = '\n'.join(manifest).encode('utf-8')
        summaries.append({'path': root, 'project': root in project_roots, 'files': len(members),
                          'bytes': sum(int(row['Bytes']) for row in members),
                          'manifest': payload[:16384], 'names': set(manifest), 'manifest_truncated': len(payload) > 16384,
                          'observed_fingerprint': hashlib.sha256(json.dumps(canonical, ensure_ascii=False).encode('utf-8')).hexdigest(),
                          'all_observed_hashes_present': all(len(row.get('SHA256', '')) == 64 for row in members)})
    selected = sorted(summaries, key=lambda row: (-row['files'], row['path']))[:max_groups]
    similarities = []
    for left, right in itertools.combinations(selected, 2):
        if within(left['path'], right['path']) or within(right['path'], left['path']):
            continue  # Ancestor/descendant is already a known hierarchy, not a cluster discovery.
        shared = left['names'] & right['names']
        union = left['names'] | right['names']
        similarities.append({'left': left['path'], 'right': right['path'],
                             'shared_relative_paths': len(shared),
                             'jaccard': len(shared) / len(union) if union else 0.0,
                             'ncd_manifest': None})
    candidates = sorted((pair for pair in similarities if pair['shared_relative_paths'] >= 2),
                        key=lambda pair: (-pair['jaccard'], -pair['shared_relative_paths'], pair['left'], pair['right']))[:30]
    if enable_ncd:
        selected_by_path = {entry['path']: entry for entry in selected}
        for pair in candidates:
            pair['ncd_manifest'] = round(ncd(selected_by_path[pair['left']]['manifest'], selected_by_path[pair['right']]['manifest']), 6)
    for entry in summaries:
        del entry['manifest']
        del entry['names']
    return {'scope': 'PARTIAL_INVENTORY_ONLY', 'automatic_file_actions': False,
            'method': 'Jaccard of relative paths; optional zlib level 6 symmetric NCD on at most 30 candidate manifests of 16 KiB',
            'ncd_enabled': enable_ncd,
            'warning': 'Not semantic similarity, not duplicate proof, not full folder coverage. No source content was read.',
            'input_files': len(rows), 'dependency_files': sum(row['files'] for row in dependencies.values()),
            'groups_total': len(summaries), 'groups_compared': len(selected), 'pairs_compared': len(similarities),
            'dependency_folders': dependencies, 'hierarchy': tree, 'groups': summaries,
            'candidate_pairs': candidates}

def render(result):
    esc = lambda value: html.escape(str(value), quote=True)
    folders = ''.join('<tr><td>' + esc(path) + '</td><td>' + str(data['files']) + '</td><td>' + str(data['dependency_files']) + '</td></tr>'
                      for path, data in sorted(result['hierarchy'].items()) if path.count('\\') <= 6)
    pairs = ''.join('<tr><td>' + esc(pair['left']) + '</td><td>' + esc(pair['right']) + '</td><td>' + str(round(pair['jaccard'], 4)) + '</td><td>' + str(pair['ncd_manifest']) + '</td></tr>'
                    for pair in result['candidate_pairs'])
    return ('<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Análise hierárquica experimental</title>'
            '<style>body{max-width:1200px;margin:30px auto;font:16px/1.5 system-ui;padding:20px}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:8px;overflow-wrap:anywhere}</style>'
            '<h1>Análise hierárquica experimental</h1><p>Somente o inventário fornecido. Nenhum arquivo original foi lido, movido ou apagado.</p>'
            '<p>A NCD compara nomes/caminhos relativos, não o assunto dos documentos. Menor distância não comprova igualdade. Não use para excluir cópias.</p>'
            '<p>Arquivos observados: ' + str(result['input_files']) + '. Arquivos em pastas de dependências: ' + str(result['dependency_files']) + '.</p>'
            '<h2>Hierarquia observada (até seis separadores)</h2><p>Contagens incluem descendentes; não somar linhas de ancestrais e filhos.</p><table><tr><th>Pasta</th><th>Arquivos</th><th>Dependências</th></tr>' + folders + '</table>'
            '<h2>Pares candidatos para revisão</h2><p>Projetos identificados por .git/node_modules permanecem como unidades. Há no máximo 64 unidades comparadas. O fingerprint refere-se só às linhas observadas, nunca prova cobertura completa.</p>'
            '<table><tr><th>Pasta A</th><th>Pasta B</th><th>Jaccard estrutural</th><th>NCD opcional</th></tr>' + pairs + '</table></html>')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory', type=Path)
    parser.add_argument('--output', type=Path, required=True, help='New output directory; existing directories are refused')
    parser.add_argument('--ncd', action='store_true', help='Experimental NCD only for at most 30 Jaccard candidates')
    args = parser.parse_args()
    with args.inventory.open(encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.DictReader(stream))
    result = analyze(rows, enable_ncd=args.ncd)
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'hierarquia.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    (args.output / 'hierarquia.html').write_text(render(result), encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('input_files', 'dependency_files', 'groups_total', 'groups_compared', 'pairs_compared')}))

if __name__ == '__main__':
    main()
