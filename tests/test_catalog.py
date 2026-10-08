import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'tools'))
import context_catalog as catalog

ROOT = Path(__file__).parents[1]

def row(path, digest='a' * 64, status='NEEDS_COPY', destination=''):
    return dict(Source=path, Bytes='10', SHA256=digest, Status=status, Destination=destination)

class CatalogTests(unittest.TestCase):
    def test_project_boundary_and_loose_context_evidence(self):
        data = catalog.build_catalog([row(r'C:\research\solar_islanding\pyproject.toml'),
            row(r'C:\research\solar_islanding\src\study.py'),
            row(r'C:\Users\User\Downloads\solar_islanding_review.pdf', 'b' * 64)])
        self.assertEqual(data['project_count'], 1)
        self.assertEqual(data['files'][1]['group'], catalog.key(r'C:\research\solar_islanding'))
        suggestion = data['suggestions'][0]
        self.assertEqual(suggestion['decision'], 'REVISAR_SUGESTAO')
        self.assertIn('Termos', suggestion['candidates'][0]['evidence'])
        self.assertFalse(data['automatic_file_actions'])

    def test_person_name_overlap_alone_is_weak_context(self):
        data = catalog.build_catalog([row(r'C:\courses\certificado_Ana_Silva.pdf'),
            row(r'C:\Downloads\CV_Ana_Silva.pdf', 'b' * 64)])
        self.assertEqual(data['suggestions'][0]['decision'], 'EVIDENCIA_FRACA')

    def test_same_names_not_duplicate_and_missing_hash_no_identity(self):
        data = catalog.build_catalog([row(r'C:\project\tese_solar.pdf', 'b' * 64),
            row(r'C:\Users\User\Downloads\tese_solar.pdf', '')])
        self.assertFalse(data['suggestions'][0]['candidates'][0]['identity_observed'])
        self.assertFalse(any(f['confirmed'] for f in data['files']))

    def test_ambiguity_and_error_hash_never_identity(self):
        data = catalog.build_catalog([row(r'C:\A\a.txt'), row(r'C:\B\b.txt'),
            row(r'C:\Desktop\file.txt'), row(r'C:\Desktop\locked.txt', status='ERROR')])
        self.assertEqual(data['suggestions'][0]['decision'], 'AMBIGUO')
        self.assertEqual(data['suggestions'][1]['decision'], 'SEM_EVIDENCIA')

    def test_hierarchy_counts_and_confirmed_needs_destination(self):
        data = catalog.build_catalog([row(r'C:\docs\sub\a.txt', status='VERIFIED', destination=r'D:\copy\a.txt'),
            row(r'C:\docs\b.txt', status='VERIFIED'), row(r'C:\docs\c.txt', status='ERROR')])
        node = data['tree'][catalog.key(r'C:\docs')]
        self.assertEqual((node['files'], node['bytes'], node['confirmed'], node['errors'], node['pending']), (3, 30, 1, 1, 1))

    def test_dependency_names_not_context_evidence(self):
        data = catalog.build_catalog([row(r'C:\project\node_modules\solar\islanding.txt'),
            row(r'C:\Downloads\solar_islanding.pdf', 'b' * 64)])
        self.assertEqual(data['suggestions'][0]['decision'], 'SEM_EVIDENCIA')

    def test_library_manifests_do_not_create_projects(self):
        data = catalog.build_catalog([row(r'C:\project\node_modules\pkg\package.json'),
            row(r'C:\env\Lib\site-packages\pkg\pyproject.toml')])
        self.assertEqual(data['project_count'], 1)

    def test_bounded_candidate_comparisons_and_common_tokens(self):
        rows = [row(f'C:\\g{i}\\solar_islanding.pdf', f'{i:064x}') for i in range(400)]
        data = catalog.build_catalog(rows + [row(r'C:\Downloads\solar_islanding.pdf', '')])
        self.assertLessEqual(data['comparisons'], 300)
        self.assertEqual(data['suggestions'][0]['decision'], 'SEM_EVIDENCIA')

    def test_html_injection_and_csv_formula_escaped(self):
        data = catalog.build_catalog([row('C:\\Downloads\\</script><img onerror=alert(1)>.txt')])
        html = catalog.render_dashboard(data, '<!--CATALOG_DATA--><!--REFRESH-->')
        self.assertNotIn('<img', html)
        payload = html.split('>', 1)[1].rsplit('</script>', 1)[0]
        self.assertEqual(json.loads(payload)['files'][0]['source'], data['files'][0]['source'])
        self.assertEqual(catalog.csv_cell(' =SUM(A1)'), "' =SUM(A1)")

    def test_snapshot_rejects_partial_rows_and_bad_schema(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / 'in.csv'
            file.write_text('Source,Bytes,Status,SHA256\nC:\\a,10,NEEDS_COPY,abc\nC:\\b,', encoding='utf-8')
            rows, rejected = catalog.read_snapshot(file)
            self.assertEqual((len(rows), rejected), (1, 1))
            file.write_text('nonsense\nvalue', encoding='utf-8')
            with self.assertRaises(ValueError): catalog.read_snapshot(file)

    def test_cli_reads_only_inventory_refuses_existing_output(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            source = temp / 'inventario.csv'
            with source.open('w', newline='') as stream:
                writer = csv.DictWriter(stream, fieldnames=list(row('x')))
                writer.writeheader(); writer.writerow(row(r'Z:\nonexistent\Downloads\a.txt'))
            original = source.read_bytes()
            output = temp / 'result'
            cmd = [sys.executable, str(ROOT / 'tools' / 'organize_inventory.py'), str(source), '--output', str(output)]
            run = subprocess.run(cmd, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(source.read_bytes(), original)
            self.assertTrue((output / 'painel.html').is_file())
            self.assertTrue((output / 'sugestoes.csv').is_file())
            self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)

if __name__ == '__main__':
    unittest.main()
