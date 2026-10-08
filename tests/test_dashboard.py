"""Execute real browser DOM interactions on the Windows CI runner's Chrome."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'tools'))
from context_catalog import build_catalog, render_dashboard

@unittest.skipUnless(sys.platform == 'win32', 'Chrome integration runs on Windows CI')
class DashboardTests(unittest.TestCase):
    def test_navigation_search_suggestions_and_untrusted_names(self):
        chrome = Path(os.environ.get('PROGRAMFILES', r'C:\Program Files')) / 'Google/Chrome/Application/chrome.exe'
        self.assertTrue(chrome.is_file(), 'Windows browser integration requires Chrome')
        rows = [dict(Source=r'C:\project\solar_islanding\pyproject.toml', Bytes='10', Status='NEEDS_COPY', SHA256='a'*64),
                dict(Source=r'C:\Downloads\solar_islanding.pdf', Bytes='20', Status='NEEDS_COPY', SHA256='b'*64),
                dict(Source=r'C:\Downloads\<img onerror=alert(1)>.txt', Bytes='0', Status='ERROR', SHA256='')]
        catalog = build_catalog(rows)
        catalog.update(generated_at='TEST', rejected_rows=0)
        template = (Path(__file__).parents[1] / 'tools/catalog_dashboard.html').read_text(encoding='utf-8')
        html = render_dashboard(catalog, template)
        assertions = '''<script>
try {
function check(ok,msg){if(!ok)throw Error(msg)}
check(document.querySelectorAll('#files tr').length===3,'initial rows');
document.querySelector('#tree button').click();
check(document.querySelectorAll('#tree button').length===2,'navigate root');
document.getElementById('query').value='solar_islanding.pdf';
document.getElementById('query').dispatchEvent(new Event('input'));
check(document.querySelectorAll('#files tr').length===1,'search');
check(document.querySelectorAll('#relations svg').length===1,'relations');
check(document.querySelectorAll('img').length===0,'unsafe name');
check(document.querySelector('#suggestions').textContent.includes('REVISAR_SUGESTAO'),'context');
document.body.setAttribute('data-test-result','PASS');
} catch(error) { document.body.setAttribute('data-test-result','FAIL:'+error.message); }
</script>'''
        html = html.replace('</body>', assertions + '</body>')
        with tempfile.TemporaryDirectory() as temp:
            page = Path(temp) / 'test.html'; page.write_text(html, encoding='utf-8')
            result = subprocess.run([str(chrome), '--headless', '--disable-gpu', '--no-sandbox', '--no-first-run',
                '--user-data-dir='+str(Path(temp)/'profile'), '--dump-dom', page.as_uri()],
                capture_output=True, timeout=60)
            output = result.stdout.decode('utf-8', errors='replace')
            self.assertIn('data-test-result="PASS"', output, result.stderr.decode('utf-8', errors='replace')[-1000:] + output[-1500:])

if __name__ == '__main__': unittest.main()
