"""Loopback-only PostgREST fixture. No real credentials or production data.

Run separately from the production app, with test/validation_app.dart.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import threading
from urllib.parse import urlparse, parse_qs

TABLES = {name: {} for name in ("tasks", "projects", "project_sections", "purged_entities", "sync_operations")}
LOCK = threading.RLock()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, data, status=200):
        encoded = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        origin = self.headers.get("Origin", "")
        if urlparse(origin).hostname in ("localhost", "127.0.0.1"):
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Headers", "authorization,apikey,content-type,prefer,x-client-info,range,range-unit,accept-profile,content-profile,x-supabase-api-version")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_OPTIONS(self):
        self.reply({})

    def do_GET(self):
        url = urlparse(self.path)
        table = url.path.rsplit("/", 1)[-1]
        with LOCK:
            if table == "fixture-status":
                return self.reply({name: len(rows) for name, rows in TABLES.items()})
            if table not in TABLES:
                return self.reply({"message": "fixture endpoint missing", "code": "PGRST205"}, 404)
            query = parse_qs(url.query)
            rows = sorted(TABLES[table].values(), key=lambda row: row.get("id", row.get("operation_id")))
            for key, expression in ((key, value) for key, values in query.items() for value in values):
                if expression.startswith("eq."):
                    rows = [row for row in rows if str(row.get(key)) == expression[3:]]
                elif expression.startswith("gte."):
                    rows = [row for row in rows if str(row.get(key)) >= expression[4:]]
                elif expression.startswith("lt."):
                    rows = [row for row in rows if str(row.get(key)) < expression[3:]]
                elif expression.startswith("gt."):
                    rows = [row for row in rows if str(row.get(key)) > expression[3:]]
            self.reply(rows[:min(int(query.get("limit", [200])[0]), 200)])

    def do_POST(self):
        if urlparse(self.path).path.endswith('/rpc/todo_task_fingerprints_v1'):
            with LOCK:
                signatures = {}
                for row in sorted(TABLES['tasks'].values(), key=lambda r: r['id']):
                    bucket = row['id'][:2]
                    signatures[bucket] = signatures.get(bucket, '') + f"{row['id']}:{row['logical_version']}:{row['device_id']};"
                return self.reply([{'bucket': key, 'fingerprint': hashlib.sha256(value.encode()).hexdigest()} for key, value in signatures.items()])
        self.write_rows()

    def do_PATCH(self):
        self.write_rows()

    def write_rows(self):
        url = urlparse(self.path)
        table = url.path.rsplit("/", 1)[-1]
        if table not in TABLES:
            return self.reply({"message": "fixture endpoint missing", "code": "PGRST205"}, 404)
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        rows = body if isinstance(body, list) else [body]
        with LOCK:
            accepted = []
            for row in rows:
                key = row.get("id", row.get("operation_id"))
                old = TABLES[table].get(key)
                query = parse_qs(url.query)
                if self.command == "PATCH":
                    if old is None or query.get("logical_version") != [f"eq.{old['logical_version']}"] or query.get("device_id") != [f"eq.{old['device_id']}"]:
                        continue
                elif old is not None:
                    if table == "sync_operations":
                        continue
                    return self.reply({"message": "duplicate synthetic UUID", "code": "23505"}, 409)
                TABLES[table][key] = row
                accepted.append(row)
            self.reply(accepted)

if __name__ == "__main__":
    print("Synthetic sync server listening on loopback port 8877", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8877), Handler).serve_forever()
