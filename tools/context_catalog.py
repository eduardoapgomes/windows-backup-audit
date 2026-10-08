"""Offline, advisory catalogue. Paths in CSV are data, never filesystem inputs."""
from collections import Counter, defaultdict
import csv
import hashlib
import json
import ntpath
import re
import unicodedata

PROJECT_MARKERS = {'pyproject.toml', 'package.json', 'cargo.toml', 'go.mod', 'pom.xml'}
LOOSE_FOLDERS = {'downloads', 'download', 'desktop', 'área de trabalho', 'area de trabalho'}
DEPENDENCIES = {'node_modules', 'site-packages', '.git'}
STOP = {'users', 'user', 'onedrive', 'documents', 'documentos', 'downloads', 'desktop',
        'area', 'trabalho', 'projetos', 'projects', 'copia', 'copy', 'final', 'novo',
        'nova', 'arquivo', 'resultado', 'resultados', 'test', 'tests', 'src', 'data',
        'the', 'and', 'para', 'com', 'pdf', 'docx', 'txt', 'csv', 'png', 'jpg', 'ipynb'}
CONFIRMED = {'VERIFIED', 'REUSED_EXISTING', 'SKIP_IDENTICAL'}


def key(path):
    return ntpath.normcase(ntpath.normpath(path))


def ancestors(path):
    current = ntpath.dirname(path)
    while current:
        yield current
        parent = ntpath.dirname(current)
        if parent == current:
            break
        current = parent


def tokens(value):
    value = unicodedata.normalize('NFKD', value.casefold())
    value = ''.join(char for char in value if not unicodedata.combining(char))
    return {word for word in re.findall(r'[^\W_]+', value) if len(word) >= 3 and not word.isdigit() and word not in STOP}


def digest(row):
    value = row.get('SHA256', '')
    return value.lower() if row.get('Status') != 'ERROR' and re.fullmatch('[a-fA-F0-9]{64}', value) else ''


def category(path):
    ext = ntpath.splitext(path)[1].lower()
    for label, extensions in (
        ('Código e notebooks', {'.py', '.ipynb', '.js', '.ts', '.m', '.r', '.c', '.cpp', '.ps1'}),
        ('Documentos', {'.pdf', '.doc', '.docx', '.odt', '.txt', '.md', '.tex'}),
        ('Dados', {'.csv', '.xlsx', '.xls', '.json', '.parquet', '.mat', '.db'}),
        ('Imagens', {'.jpg', '.jpeg', '.png', '.svg', '.heic', '.tif'}),
        ('Áudio e vídeo', {'.mp4', '.mkv', '.mov', '.mp3', '.wav'}),
    ):
        if ext in extensions:
            return label
    return 'Outros'


def read_snapshot(path):
    """A concurrently appended final record may be incomplete: reject it explicitly."""
    valid, rejected = [], 0
    with path.open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        if not {'Source', 'Bytes', 'Status'}.issubset(reader.fieldnames or []):
            raise ValueError('Inventário precisa conter Source, Bytes e Status.')
        for row in reader:
            try:
                if None in row or any(value is None for value in row.values()):
                    raise ValueError('Linha incompleta')
                if not row['Source'] or not row['Status'] or int(row['Bytes']) < 0:
                    raise ValueError('Linha inválida')
            except (ValueError, TypeError):
                rejected += 1
                continue
            valid.append(row)
    return valid, rejected


def build_catalog(rows):
    """O(files * path depth) aggregation; bounded indexed context candidates."""
    projects = {}
    for row in rows:
        path = row['Source']
        name = ntpath.basename(path).lower()
        segments = path.replace('/', '\\').split('\\')
        in_dependency = any(segment.lower() in DEPENDENCIES for segment in segments[:-1])
        if not in_dependency and (name in PROJECT_MARKERS or name.endswith('.sln')):
            root = ntpath.dirname(path)
            projects[key(root)] = root
        segments = path.replace('/', '\\').split('\\')
        for i, segment in enumerate(segments):
            if segment.lower() == 'site-packages':
                break
            if segment.lower() in {'.git', 'node_modules'} and i:
                root = '\\'.join(segments[:i])
                projects[key(root)] = root
                break

    groups, tree, files = {}, {}, []
    for row in rows:
        path, size = row['Source'], int(row['Bytes'])
        parents = list(ancestors(path))
        project = next((projects[key(p)] for p in parents if key(p) in projects), None)
        hidden = any(part.lower() in DEPENDENCIES for part in path.replace('/', '\\').split('\\'))
        loose = not project and ntpath.basename(ntpath.dirname(path)).casefold() in LOOSE_FOLDERS
        root = project or ntpath.dirname(path)
        gid = key(root)
        group = groups.setdefault(gid, {'path': root, 'project': bool(project), 'files': 0, 'bytes': 0, 'eligible': 0, 'words': Counter()})
        group['files'] += 1
        group['bytes'] += size
        if not hidden and not loose:
            group['eligible'] += 1
            group['words'].update(tokens(ntpath.basename(path)))
        state = row['Status']
        protected = state in CONFIRMED and bool(digest(row)) and bool(row.get('Destination'))
        file = {'source': path, 'bytes': size, 'status': state, 'destination': row.get('Destination', ''),
                'planned': row.get('PlannedDestination', ''), 'sha256': digest(row), 'group': gid,
                'category': category(path), 'loose': loose, 'hidden': hidden, 'confirmed': protected}
        files.append(file)
        for parent in parents:
            node = tree.setdefault(key(parent), {'path': parent, 'parent': key(ntpath.dirname(parent)),
                'files': 0, 'bytes': 0, 'confirmed': 0, 'errors': 0, 'pending': 0})
            node['files'] += 1
            node['bytes'] += size
            node['confirmed'] += int(protected)
            node['errors'] += int(state == 'ERROR')
            node['pending'] += int(not protected and state != 'ERROR')

    inverted, hashes = defaultdict(set), defaultdict(set)
    for gid, group in groups.items():
        # Only directory identity + frequent names; never the whole user's path.
        words = tokens(ntpath.basename(group['path']))
        words.update(word for word, _ in group['words'].most_common(64))
        group['tokens'] = sorted(words)[:128]
        del group['words']
        if not group['eligible'] or ntpath.basename(group['path']).casefold() in LOOSE_FOLDERS:
            continue
        for word in group['tokens']:
            inverted[word].add(gid)
    for file in files:
        if file['sha256'] and not file['loose'] and not file['hidden']:
            hashes[file['sha256']].add(file['group'])
    suggestions, comparisons = [], 0
    for file in files:
        if not file['loose'] or file['hidden']:
            continue
        words = tokens(ntpath.splitext(ntpath.basename(file['source']))[0])
        hits = Counter()
        for word in sorted(words):
            # Common words must not cause unbounded all-pairs comparisons.
            targets = inverted.get(word, set())
            if len(targets) <= 96:
                hits.update(targets)
        exact = hashes.get(file['sha256'], set()) if file['sha256'] else set()
        candidates = sorted(exact)[:300]
        candidates += [gid for gid, _ in hits.most_common(300) if gid not in exact]
        ranked = []
        for gid in candidates[:300]:
            if gid == file['group']:
                continue
            comparisons += 1
            shared = words & set(groups[gid]['tokens'])
            identical = gid in exact
            if not identical and len(shared) < 2:
                continue
            score = 1.0 if identical else len(shared) / max(1, len(words | set(groups[gid]['tokens'])))
            ranked.append({'group': groups[gid]['path'], 'score': round(score, 4),
                'evidence': 'SHA256 observado igual' if identical else 'Termos em comum: ' + ', '.join(sorted(shared)),
                'identity_observed': identical,
                'folder_name_support': bool(words & tokens(ntpath.basename(groups[gid]['path'])))})
        ranked.sort(key=lambda item: (-item['score'], item['group'].casefold()))
        decision = 'SEM_EVIDENCIA'
        if ranked:
            ambiguous = len(ranked) > 1 and ranked[0]['score'] - ranked[1]['score'] < 0.05
            if ambiguous:
                decision = 'AMBIGUO'
            elif ranked[0]['identity_observed'] or ranked[0]['folder_name_support']:
                decision = 'REVISAR_SUGESTAO'
            else:
                decision = 'EVIDENCIA_FRACA'
        suggestions.append({'source': file['source'], 'destination': file['destination'],
            'status': file['status'], 'decision': decision, 'candidates': ranked[:3]})
    return {'scope': 'INVENTARIO_OBSERVADO', 'automatic_file_actions': False,
        'files': files, 'tree': tree, 'groups': list(groups.values()), 'suggestions': suggestions,
        'comparisons': comparisons, 'project_count': len(projects),
        'limits': 'Até 300 candidatos por arquivo solto; termos presentes em mais de 96 grupos ignorados. Top 3 sugestões, sem probabilidade calibrada.',
        'warning': 'A visão não comprova cobertura completa. Confirmações são as registradas no inventário, sem revalidar o HD. Agrupamentos não alteram o backup.'}


def csv_cell(value):
    """Keep exported path/name data from becoming spreadsheet formulas."""
    text = str(value)
    return "'" + text if text.lstrip().startswith(('=', '+', '-', '@')) else text


def write_suggestions(path, catalog):
    with path.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['Source', 'VerifiedDestinationFromInventory', 'Status', 'Decision', 'SuggestedContext', 'Evidence', 'ScoreNotProbability'])
        for item in catalog['suggestions']:
            for candidate in item['candidates'] or [{}]:
                writer.writerow([csv_cell(value) for value in [item['source'], item['destination'], item['status'],
                    item['decision'], candidate.get('group', ''), candidate.get('evidence', ''), candidate.get('score', '')]])


def render_dashboard(catalog, template, refresh=False):
    # JSON is inert data, and cannot terminate its script element even for hostile filenames.
    payload = json.dumps(catalog, ensure_ascii=False).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    return template.replace('<!--CATALOG_DATA-->', '<script type="application/json" id="catalog">' + payload + '</script>').replace('<!--REFRESH-->', '<meta http-equiv="refresh" content="30">' if refresh else '')
