#!/usr/bin/env python3
"""Local fake server only. Never contacts an installed VPN or writes Keychain."""
import http.server
import json
import pathlib
import subprocess
import threading

root = pathlib.Path(__file__).resolve().parents[1]
calls = []
class Server(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_DELETE(self):
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        method = body['method']
        if method == 'initialize':
            result = {'protocolVersion': '2025-03-26', 'capabilities': {'tools': {}}, 'serverInfo': {'name': 'fake', 'version': '1'}}
        elif method == 'notifications/initialized':
            self.send_response(202); self.send_header('Content-Length', '0'); self.end_headers(); return
        elif method == 'tools/list':
            result = {'tools': [{'name': name, 'inputSchema': {'type': 'object', 'properties': props}} for name, props in [
                ('expressvpn_ping', {}), ('expressvpn_status', {}), ('expressvpn_connect', {'region': {'type': 'string'}}), ('expressvpn_disconnect', {})]]}
        elif method == 'tools/call':
            assert self.headers['Mcp-Session-Id'] == 'test-session'
            assert self.headers['MCP-Protocol-Version'] == '2025-03-26'
            name = body['params']['name']; calls.append(body['params'])
            text = {'expressvpn_ping': 'pong', 'expressvpn_status': 'Connected', 'expressvpn_connect': 'accepted', 'expressvpn_disconnect': 'SECRET' }[name]
            result = {'content': [{'type': 'text', 'text': text}], 'isError': name == 'expressvpn_disconnect'}
        else: raise AssertionError(method)
        payload = json.dumps({'jsonrpc': '2.0', 'id': body['id'], 'result': result})
        streamed = method == 'tools/call'
        data = (('event: message\ndata: ' + payload + '\n\n') if streamed else payload).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream' if streamed else 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Mcp-Session-Id', 'test-session')
        self.end_headers(); self.wfile.write(data)

build = root / '.build/background-mcp-tests'
build.mkdir(parents=True, exist_ok=True)
xcode = pathlib.Path('/Applications/Xcode.app/Contents/Developer')
compiler = xcode / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk = xcode / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
subprocess.run([str(compiler), '-warnings-as-errors', '-sdk', str(sdk), '-target', 'arm64-apple-macosx13.0', '-module-cache-path', str(build/'ModuleCache'),
    str(root/'Housekeeping/Sources/Routes/ExpressVPNMCP.swift'), str(root/'Housekeeping/Sources/Network/BackgroundItemAudit.swift'),
    str(root/'Housekeeping/Sources/Network/BackgroundReview.swift'), str(root/'Housekeeping/Sources/Network/BackgroundWidgetControl.swift'), str(root/'Housekeeping/Sources/Network/BackgroundActivity.swift'), str(root/'Housekeeping/Sources/Update/ProcessRunner.swift'), str(root/'HousekeepingTests/BackgroundAndMCPTests.swift'), '-o', str(build/'tests')], check=True)
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Server)
thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
try:
    subprocess.run([str(build/'tests'), f'http://127.0.0.1:{server.server_port}/mcp?token=fake'], check=True, timeout=60)
    assert [c['name'] for c in calls] == ['expressvpn_ping', 'expressvpn_status', 'expressvpn_connect', 'expressvpn_disconnect']
    assert calls[2]['arguments'] == {'region': 'test-only-region'}
    print('Fake server verified exact call sequence and connect arguments; no live VPN was used.')
finally: server.shutdown(); server.server_close()
