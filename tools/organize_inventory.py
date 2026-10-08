"""Build an offline visual catalogue from CSV, optionally following a running audit."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import time
import webbrowser
from context_catalog import build_catalog, read_snapshot, render_dashboard, write_suggestions


def publish(output, catalog, template, watch):
    # Only generated files in a newly allocated output directory are replaced.
    for name, content in [('catalogo.json', json.dumps(catalog, ensure_ascii=False)),
                          ('painel.html', render_dashboard(catalog, template, watch))]:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=output, delete=False) as stream:
            stream.write(content)
            temporary = stream.name
        os.replace(temporary, output / name)
    with tempfile.NamedTemporaryFile(dir=output, delete=False) as stream:
        temporary = Path(stream.name)
    write_suggestions(temporary, catalog)
    os.replace(temporary, output / 'sugestoes.csv')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory', type=Path)
    parser.add_argument('--output', type=Path, help='New directory only. Default: unique local temporary directory.')
    parser.add_argument('--watch', action='store_true', help='Refresh changed CSV every 30 seconds until Ctrl+C')
    parser.add_argument('--open', action='store_true', help='Open the local dashboard in the default browser')
    args = parser.parse_args()
    if not args.inventory.is_file():
        parser.error('Inventário não encontrado; selecione inventario.csv da execução.')
    if args.output:
        args.output.mkdir(parents=True, exist_ok=False)
        output = args.output.resolve()
    else:
        output = Path(tempfile.mkdtemp(prefix='backup-catalogo-')).resolve()
    template = Path(__file__).with_name('catalog_dashboard.html').read_text(encoding='utf-8')
    previous, opened = None, False
    print('Painel local: ' + str(output / 'painel.html'), flush=True)
    try:
        while True:
            stat = args.inventory.stat()
            signature = (stat.st_size, stat.st_mtime_ns)
            if signature != previous:
                print('Lendo o inventário; não abrindo os arquivos originais...', flush=True)
                rows, rejected = read_snapshot(args.inventory)
                catalog = build_catalog(rows)
                catalog.update(generated_at=datetime.now(timezone.utc).isoformat(), rejected_rows=rejected)
                publish(output, catalog, template, args.watch)
                previous = signature
                print(f"{len(rows)} arquivos observados; {catalog['project_count']} projetos; {len(catalog['suggestions'])} arquivos soltos; {rejected} linhas rejeitadas.", flush=True)
                if args.open and not opened:
                    webbrowser.open((output / 'painel.html').as_uri())
                    opened = True
            if not args.watch:
                break
            print('Acompanhando alterações no CSV. Ctrl+C encerra somente o painel.', flush=True)
            time.sleep(30)
    except KeyboardInterrupt:
        print('\nAcompanhamento encerrado; painel preservado em ' + str(output), flush=True)


if __name__ == '__main__':
    main()
