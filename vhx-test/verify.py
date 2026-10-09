#!/usr/bin/env python3
"""Run the compiled macOS binary against a loopback HTTP server."""
import http.server
import pathlib
import subprocess
import sys
import threading
import time


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        routes = {
            '/ok/vhx': (200, b'ok'),
            '/trim/vhx': (200, b' \r\nOK\t '),
            '/empty/vhx': (200, b''),
            '/wrong/vhx': (200, b'okay'),
            '/invalid/vhx': (200, b'\xff'),
            '/status/vhx': (201, b'ok'),
            '/slow/vhx': (200, b'ok'),
        }
        status, body = routes.get(self.path, (404, b'not found'))
        if self.path == '/slow/vhx':
            time.sleep(1)
        try:
            self.send_response(status)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 verify.py /path/to/compiled/vhx-test')
    binary = str(pathlib.Path(sys.argv[1]).resolve(strict=True))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f'http://127.0.0.1:{server.server_port}'
    cases = [
        ('ok', ['5', '0'], 0),
        ('trim', ['5', '1'], 0),
        ('empty', ['5', '0'], 1),
        ('wrong', ['5', '0'], 1),
        ('invalid', ['5', '0'], 1),
        ('status', ['5', '0'], 1),
        ('status', ['5', '1', '201'], 0),
        ('slow', ['0.1', '0'], 1),
        ('ok', ['nan', '0'], 2),
        ('ok', ['5', '2'], 2),
        ('ok', ['5', '0', '600'], 2),
    ]
    try:
        for route, args, expected in cases:
            result = subprocess.run([binary, base + '/' + route, *args],
                                    capture_output=True, timeout=10)
            assert result.returncode == expected, (route, args, result.returncode, result.stderr)
            if expected != 2:
                marker = b'RESULT=true' if expected == 0 else b'RESULT=false'
                assert marker in result.stdout, (route, result.stdout)
            print('PASS', route, *args)
        print(f'{len(cases)} cases passed')
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == '__main__':
    main()
