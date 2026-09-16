"""The HTTP fixture must preserve PostgREST's requested ordering."""
import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import urlopen

import synthetic_sync_server as fixture


class SyntheticPagingTest(unittest.TestCase):
    def test_order_and_cursor_are_independent(self):
        with fixture.LOCK:
            fixture.TABLES['tasks'] = {str(i): {'id': str(i)} for i in range(5)}
        server = ThreadingHTTPServer(('127.0.0.1', 0), fixture.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = f'http://127.0.0.1:{server.server_port}/rest/v1/tasks'
            for order, expected in [('asc', ['2', '3']), ('desc', ['4', '3'])]:
                with urlopen(f'{base}?order=id.{order}.nullslast&id=gt.1&limit=2') as response:
                    self.assertEqual([r['id'] for r in json.load(response)], expected)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            with fixture.LOCK:
                fixture.TABLES['tasks'].clear()
