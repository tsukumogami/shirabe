"""fake-s3.py -- an in-memory S3 stand-in for /coordinate's engine suites.

Test-only. It serves one bucket, path-style (`/<bucket>/<key>`), on 127.0.0.1,
for koto's cloud session backend: GET, PUT, HEAD and DELETE of objects, and
ListObjectsV2 (`?list-type=2&prefix=..&delimiter=..`) in the XML koto's S3
client reads. Every object has an ETag, a hash of its content, in a listing, a
GET, a HEAD and a PUT's reply alike. A PUT honours `If-Match` and
`If-None-Match: *` as S3 does: when the stored object's ETag isn't the one
named, or an object is there for `If-None-Match: *`, it answers 412
PreconditionFailed and stores nothing (koto's supersede pushes its fence on
that condition). Authentication is ignored. A missing object or bucket answers 404
with an S3 error body (HEAD with no body). Every reply closes its connection.
Nothing is logged, so no request header, credential included, is ever written.

It follows koto's own test stand-in (koto's tests/support/fake_s3.rs).

Usage: python3 -I fake-s3.py <bucket> <port-file>
Binds an ephemeral port, writes it to <port-file> (through a temporary name and
a rename, so a reader never sees a partial number), and serves until killed.
"""

import os
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

OBJECTS = {}
LOCK = threading.Lock()
BUCKET = ""


def error_body(code, message):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<Error><Code>%s</Code><Message>%s</Message></Error>" % (code, escape(message))
    ).encode()


def etag(data):
    """An object's ETag, quoted as S3 sends it: 64-bit FNV-1a of its content and
    its length, as koto's fake_s3.rs computes it."""
    h = 0xCBF29CE484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return '"%016x-%d"' % (h, len(data))


def list_xml(prefix, delimiter):
    contents, common = [], []
    with LOCK:
        keys = sorted(k for k in OBJECTS if k.startswith(prefix))
        sizes = {k: len(OBJECTS[k]) for k in keys}
        tags = {k: etag(OBJECTS[k]) for k in keys}
    for key in keys:
        after = key[len(prefix):]
        i = after.find(delimiter) if delimiter else -1
        if i >= 0:
            rolled = prefix + after[: i + len(delimiter)]
            if not common or common[-1] != rolled:
                common.append(rolled)
        else:
            contents.append(key)
    parts = [
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">',
        "<Name>%s</Name><Prefix>%s</Prefix>" % (escape(BUCKET), escape(prefix)),
    ]
    if delimiter:
        parts.append("<Delimiter>%s</Delimiter>" % escape(delimiter))
    parts.append(
        "<KeyCount>%d</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>"
        % (len(contents) + len(common))
    )
    for key in contents:
        parts.append(
            "<Contents><Key>%s</Key><LastModified>2026-01-01T00:00:00.000Z</LastModified>"
            "<ETag>%s</ETag><Size>%d</Size><StorageClass>STANDARD</StorageClass></Contents>"
            % (escape(key), escape(tags[key]), sizes[key])
        )
    for p in common:
        parts.append("<CommonPrefixes><Prefix>%s</Prefix></CommonPrefixes>" % escape(p))
    parts.append("</ListBucketResult>")
    return "".join(parts).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, body=b"", headers=()):
        self.send_response(status)
        sent = b"" if self.command == "HEAD" else body
        self.send_header("Content-Length", str(len(sent)))
        self.send_header("Connection", "close")
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        if sent:
            self.wfile.write(sent)
        self.close_connection = True

    def target(self):
        parsed = urllib.parse.urlsplit(self.path)
        rest = urllib.parse.unquote(parsed.path).lstrip("/")
        bucket, _, key = rest.partition("/")
        query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
        return bucket, key, query

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        bucket, key, query = self.target()
        if bucket != BUCKET:
            self.reply(404, error_body("NoSuchBucket", "The specified bucket does not exist"),
                       [("Content-Type", "application/xml")])
            return
        if self.command == "GET" and query.get("list-type") == "2":
            self.reply(200, list_xml(query.get("prefix", ""), query.get("delimiter") or ""),
                       [("Content-Type", "application/xml")])
            return
        if self.command in ("GET", "HEAD"):
            with LOCK:
                data = OBJECTS.get(key)
            if data is None:
                self.reply(404, error_body("NoSuchKey", "The specified key does not exist."),
                           [("Content-Type", "application/xml")])
            else:
                self.reply(200, data, [("ETag", etag(data))])
        elif self.command == "PUT":
            want = self.headers.get("If-Match")
            none = self.headers.get("If-None-Match")
            with LOCK:
                current = OBJECTS.get(key)
                if want is not None:
                    failed = current is None or etag(current).strip('"') != want.strip().strip('"')
                else:
                    failed = none is not None and none.strip() == "*" and current is not None
                if not failed:
                    OBJECTS[key] = body
            if failed:
                self.reply(412, error_body("PreconditionFailed",
                                           "At least one of the pre-conditions you specified did not hold"),
                           [("Content-Type", "application/xml")])
            else:
                self.reply(200, headers=[("ETag", etag(body))])
        elif self.command == "DELETE":
            with LOCK:
                OBJECTS.pop(key, None)
            self.reply(204)
        else:
            self.reply(405, error_body("MethodNotAllowed", "method not allowed"),
                       [("Content-Type", "application/xml")])

    do_GET = do_PUT = do_HEAD = do_DELETE = do_POST = handle_any


def main():
    global BUCKET
    if len(sys.argv) != 3:
        sys.stderr.write("usage: fake-s3.py <bucket> <port-file>\n")
        return 64
    BUCKET, port_file = sys.argv[1], sys.argv[2]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    tmp = port_file + ".tmp"
    with open(tmp, "w") as f:
        f.write("%d\n" % server.server_address[1])
    os.rename(tmp, port_file)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
