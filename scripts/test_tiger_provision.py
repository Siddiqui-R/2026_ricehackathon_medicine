#!/usr/bin/env python3
"""Unit tests for scripts/tiger_provision.py with a fake transport; no network, no real credentials.

Purpose: Prove the provisioning CLI builds the documented Tiger Cloud requests, refuses paid sizes without
    --allow-paid, polls until READY, stops at its timeout, and never leaks the password or API keys.
Inputs: Synthetic environment values and scripted HTTP responses; the real process environment is not read.
Outputs: unittest results. Run from the repository root:
    python3 -m unittest scripts.test_tiger_provision -v
Side effects: None. The fake transport records requests in memory; no socket is opened and no file is written.
"""
import base64
import contextlib
import io
import json
from pathlib import Path
import sys
import unittest

# --- Import the module under test whether run as scripts.test_tiger_provision or as a plain file ---
sys.path.insert(0, str(Path(__file__).resolve().parent))
import tiger_provision as provision  # noqa: E402

# --- Synthetic fixtures (clearly fake; never valid Tiger credentials) ---
ACCESS = 'ak_synthetic_access_key'
SECRET = 'sk_synthetic_secret_value_0000'
PROJECT = 'proj12345'
PASSWORD = 'pw-Synthetic-Initial-9zQ'
HOST = 'svc123.proj12345.tsdb.cloud.timescale.com'
PORT = 34567
ENVIRONMENT = {'TIGERDATA_ACCESS_KEY': ACCESS, 'TIGERDATA_SECRET_KEY': SECRET, 'TIGERDATA_PROJECT_ID': PROJECT}
SERVICES_URL = f'{provision.BASE_URL}/projects/{PROJECT}/services'
SERVICE_URL = f'{SERVICES_URL}/svc123'
EXPECTED_URL_LINE = f'DATABASE_URL=postgresql://tsdbadmin:{PASSWORD}@{HOST}:{PORT}/tsdb?sslmode=require\n'


def service(status, with_endpoint=True, with_password=True):
    body = {'service_id': 'svc123', 'name': 'reva-demo', 'status': status, 'service_type': 'POSTGRES',
            'region_code': 'us-east-1', 'created': '2026-09-12T00:00:00Z'}
    if with_endpoint:
        body['endpoint'] = {'host': HOST, 'port': PORT}
    if with_password:
        body['initial_password'] = PASSWORD
    return body


class Recorded:
    def __init__(self, method, url, headers, body):
        self.method, self.url, self.headers, self.body = method, url, dict(headers), body


class FakeTransport:
    """Return scripted (status, payload) pairs in order; payload is a JSON-able object or raw bytes."""

    def __init__(self, *responses, repeat_last=False):
        self.responses = list(responses)
        self.repeat_last = repeat_last
        self.requests = []

    def send(self, method, url, headers, body):
        self.requests.append(Recorded(method, url, headers, body))
        if not self.responses:
            raise AssertionError(f'unexpected request {method} {url}')
        status, payload = self.responses[0] if self.repeat_last and len(self.responses) == 1 else self.responses.pop(0)
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode('utf-8')
        return status, raw


class RaisingTransport:
    def __init__(self, error):
        self.error = error
        self.requests = []

    def send(self, method, url, headers, body):
        self.requests.append(Recorded(method, url, headers, body))
        raise self.error


class FakeClock:
    """Monotonic clock advanced only by the script's own sleep calls."""

    def __init__(self):
        self.now = 1000.0
        self.sleeps = []

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


def run(argv, transport=None, environment=ENVIRONMENT):
    out, err, clock = io.StringIO(), io.StringIO(), FakeClock()
    transport = FakeTransport() if transport is None else transport
    code = provision.main(argv, environment=environment, transport=transport, out=out, err=err,
                          sleep=clock.sleep, clock=clock)
    return code, out.getvalue(), err.getvalue(), clock


# --- Request construction: auth header, free body, paid body, dry run, credentials ---
class CreateRequestTests(unittest.TestCase):
    def test_free_create_sends_basic_auth_and_shared_body_without_addons(self):
        transport = FakeTransport((200, service('READY')))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_OK, err)
        self.assertEqual(len(transport.requests), 1)
        request = transport.requests[0]
        self.assertEqual((request.method, request.url), ('POST', SERVICES_URL))
        expected = 'Basic ' + base64.b64encode(f'{ACCESS}:{SECRET}'.encode()).decode('ascii')
        self.assertEqual(request.headers['Authorization'], expected)
        self.assertEqual(request.headers['Content-Type'], 'application/json')
        self.assertEqual(json.loads(request.body), {
            'name': 'reva-demo', 'cpu_millis': 'shared', 'memory_gbs': 'shared', 'region_code': 'us-east-1'})
        self.assertNotIn('addons', json.loads(request.body))
        self.assertEqual(out, EXPECTED_URL_LINE)
        self.assertIn('free shared', err)

    def test_paid_create_with_flag_sends_numeric_string_sizes(self):
        transport = FakeTransport((200, service('READY')))
        code, out, err, _ = run(
            ['create', '--name', 'reva-paid', '--allow-paid', '--cpu-millis', '1000', '--memory-gbs', '4',
             '--region', 'eu-west-1'], transport)
        self.assertEqual(code, provision.EXIT_OK, err)
        self.assertEqual(json.loads(transport.requests[0].body), {
            'name': 'reva-paid', 'cpu_millis': '1000', 'memory_gbs': '4', 'region_code': 'eu-west-1'})
        self.assertIn('PAID', err)
        self.assertEqual(out, EXPECTED_URL_LINE)

    def test_paid_size_refused_without_allow_paid_and_nothing_sent(self):
        transport = FakeTransport()
        code, out, err, _ = run(
            ['create', '--name', 'reva-demo', '--cpu-millis', '1000', '--memory-gbs', '4'], transport)
        self.assertEqual(code, provision.EXIT_USAGE)
        self.assertEqual(transport.requests, [])
        self.assertEqual(out, '')
        self.assertIn('--allow-paid', err)
        self.assertIn('paid size', err)

    def test_non_free_region_refused_without_allow_paid(self):
        transport = FakeTransport()
        code, out, err, _ = run(['create', '--name', 'reva-demo', '--region', 'eu-west-1'], transport)
        self.assertEqual(code, provision.EXIT_USAGE)
        self.assertEqual(transport.requests, [])
        self.assertIn('us-east-1', err)
        self.assertIn('--allow-paid', err)

    def test_cpu_without_memory_is_a_usage_error(self):
        transport = FakeTransport()
        code, _, err, _ = run(['create', '--name', 'reva-demo', '--allow-paid', '--cpu-millis', '1000'], transport)
        self.assertEqual(code, provision.EXIT_USAGE)
        self.assertEqual(transport.requests, [])
        self.assertIn('together', err)

    def test_dry_run_prints_masked_request_and_sends_nothing(self):
        transport = FakeTransport()
        code, out, err, _ = run(['create', '--name', 'reva-demo', '--dry-run'], transport)
        self.assertEqual(code, provision.EXIT_OK, err)
        self.assertEqual(transport.requests, [])
        self.assertIn('DRY RUN', out)
        self.assertIn(f'POST {SERVICES_URL}', out)
        self.assertIn('Authorization: ***', out)
        self.assertIn('"cpu_millis": "shared"', out)
        self.assertNotIn(SECRET, out)
        self.assertNotIn(base64.b64encode(f'{ACCESS}:{SECRET}'.encode()).decode('ascii'), out)

    def test_missing_credentials_exit_3_without_any_request(self):
        transport = FakeTransport()
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport,
                                environment={'TIGERDATA_PROJECT_ID': PROJECT})
        self.assertEqual(code, provision.EXIT_CREDENTIALS)
        self.assertEqual(transport.requests, [])
        self.assertEqual(out, '')
        self.assertIn('TIGERDATA_ACCESS_KEY', err)
        self.assertIn('TIGERDATA_SECRET_KEY', err)
        self.assertNotIn('TIGERDATA_PROJECT_ID', err.split('Export')[1].split(' in the')[0])

    def test_argparse_rejects_missing_name_and_zero_sizes(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as missing:
                provision.main(['create'], environment=ENVIRONMENT, transport=FakeTransport())
            with self.assertRaises(SystemExit) as zero:
                provision.main(['create', '--name', 'x', '--allow-paid', '--cpu-millis', '0', '--memory-gbs', '1'],
                               environment=ENVIRONMENT, transport=FakeTransport())
        self.assertEqual((missing.exception.code, zero.exception.code), (2, 2))

    def test_help_exits_zero_and_documents_exit_codes(self):
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured), self.assertRaises(SystemExit) as exit_info:
            provision.main(['--help'])
        self.assertEqual(exit_info.exception.code, 0)
        self.assertIn('--allow-paid', captured.getvalue())
        self.assertIn('Exit codes', captured.getvalue())


# --- Readiness polling: until READY, endpoint arriving late, timeout, failed status ---
class PollingTests(unittest.TestCase):
    def test_polls_get_until_ready_and_prints_url_exactly_once(self):
        transport = FakeTransport((200, service('QUEUED')), (200, service('CONFIGURING')), (200, service('READY')))
        code, out, err, clock = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_OK, err)
        self.assertEqual([request.method for request in transport.requests], ['POST', 'GET', 'GET'])
        self.assertEqual(transport.requests[1].url, SERVICE_URL)
        self.assertIsNone(transport.requests[1].body)
        self.assertNotIn('Content-Type', transport.requests[1].headers)
        self.assertEqual(clock.sleeps, [provision.POLL_SECONDS])
        self.assertEqual(out, EXPECTED_URL_LINE)
        self.assertEqual(out.count('DATABASE_URL='), 1)
        self.assertIn('status=CONFIGURING', err)
        self.assertIn('is READY', err)
        self.assertNotIn(PASSWORD, err)

    def test_ready_in_create_response_skips_polling(self):
        transport = FakeTransport((200, service('READY')))
        code, out, _, clock = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_OK)
        self.assertEqual(len(transport.requests), 1)
        self.assertEqual(clock.sleeps, [])
        self.assertEqual(out.count('DATABASE_URL='), 1)

    def test_endpoint_arriving_during_polling_is_printed_once(self):
        transport = FakeTransport(
            (200, service('QUEUED', with_endpoint=False)),
            (200, service('CONFIGURING', with_endpoint=False, with_password=False)),
            (200, service('CONFIGURING', with_password=False)),
            (200, service('READY', with_password=False)))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_OK, err)
        self.assertEqual(out, EXPECTED_URL_LINE)

    def test_timeout_exits_5_after_deadline_and_still_prints_url_once(self):
        transport = FakeTransport((200, service('QUEUED')), (200, service('CONFIGURING')), repeat_last=True)
        code, out, err, clock = run(['create', '--name', 'reva-demo', '--timeout-minutes', '1'], transport)
        self.assertEqual(code, provision.EXIT_TIMEOUT)
        self.assertEqual(out, EXPECTED_URL_LINE)
        gets = [request for request in transport.requests if request.method == 'GET']
        self.assertEqual(len(gets), 7)  # polls at t=0,10,...,60 seconds, then the deadline stops it
        self.assertGreaterEqual(clock.now - 1000.0, 60.0)
        self.assertIn('svc123', err)
        self.assertIn('still CONFIGURING after 1 minutes', err)
        self.assertNotIn(PASSWORD, err)

    def test_timeout_without_endpoint_prints_nothing_secret_and_points_to_cli(self):
        transport = FakeTransport((200, service('QUEUED', with_endpoint=False)),
                                  (200, service('QUEUED', with_endpoint=False, with_password=False)), repeat_last=True)
        code, out, err, _ = run(['create', '--name', 'reva-demo', '--timeout-minutes', '0.5'], transport)
        self.assertEqual(code, provision.EXIT_TIMEOUT)
        self.assertEqual(out, '')
        self.assertIn('connection-string svc123 --with-password', err)
        self.assertNotIn(PASSWORD, err)

    def test_deleting_status_is_an_api_error(self):
        transport = FakeTransport((200, service('QUEUED')), (200, service('DELETING')))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_API)
        self.assertEqual(out, EXPECTED_URL_LINE)
        self.assertIn('DELETING', err)

    def test_create_without_initial_password_is_an_api_error(self):
        transport = FakeTransport((200, service('QUEUED', with_password=False)))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_API)
        self.assertEqual(out, '')
        self.assertIn('initial_password', err)


# --- Masking: error bodies, later errors, unexpected exceptions, and the redactor patterns ---
class MaskingTests(unittest.TestCase):
    def test_http_error_body_masks_password_field_and_both_keys(self):
        body = json.dumps({'message': 'rejected', 'initial_password': 'leaked-pw-value',
                           'echo': f'{ACCESS}:{SECRET}'}).encode('utf-8')
        transport = FakeTransport((500, body))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_API)
        self.assertEqual(out, '')
        self.assertIn('HTTP 500', err)
        self.assertIn('rejected', err)
        self.assertNotIn('leaked-pw-value', err)
        self.assertNotIn(SECRET, err)
        self.assertNotIn(ACCESS, err)
        self.assertIn('***', err)

    def test_known_password_is_masked_in_later_polling_errors(self):
        transport = FakeTransport((200, service('QUEUED')),
                                  (502, f'gateway echoed {PASSWORD} and {SECRET}'.encode('utf-8')))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], transport)
        self.assertEqual(code, provision.EXIT_API)
        self.assertEqual(out, EXPECTED_URL_LINE)
        self.assertIn('HTTP 502', err)
        self.assertNotIn(PASSWORD, err)
        self.assertNotIn(SECRET, err)
        self.assertGreaterEqual(err.count('***'), 2)

    def test_unexpected_exception_and_oserror_are_masked(self):
        crash = RaisingTransport(RuntimeError(f'boom {SECRET}'))
        code, out, err, _ = run(['create', '--name', 'reva-demo'], crash)
        self.assertEqual((code, out), (provision.EXIT_API, ''))
        self.assertIn('unexpected RuntimeError', err)
        self.assertNotIn(SECRET, err)
        network = RaisingTransport(OSError(f'tls failure for {ACCESS}'))
        code, _, err, _ = run(['create', '--name', 'reva-demo'], network)
        self.assertEqual(code, provision.EXIT_API)
        self.assertIn('failed before a response arrived', err)
        self.assertNotIn(ACCESS, err)

    def test_redactor_patterns(self):
        redact = provision.Redactor()
        redact.add('s3cret-value')
        redact.add('')
        self.assertEqual(redact('token s3cret-value here'), 'token *** here')
        self.assertEqual(redact('postgresql://tsdbadmin:pw123@host:5432/tsdb'), 'postgresql://tsdbadmin:***@host:5432/tsdb')
        self.assertEqual(redact('Authorization: Basic QUJDOmRlZg=='), 'Authorization: Basic ***')
        self.assertEqual(redact('{"initial_password": "x\\"y"}'), '{"initial_password": "***"}')
        self.assertEqual(redact('{"password":"abc"}'), '{"password":"***"}')

    def test_database_url_percent_encodes_reserved_password_characters(self):
        url = provision.database_url('h.example', 5432, 'a b/c@d:e?f#g')
        self.assertEqual(url, 'postgresql://tsdbadmin:a%20b%2Fc%40d%3Ae%3Ff%23g@h.example:5432/tsdb?sslmode=require')


# --- Listing: password-free table, wrapped arrays, empty projects, dry run ---
class ListTests(unittest.TestCase):
    def test_list_prints_name_status_host_and_never_a_password(self):
        other = {'service_id': 'svc9', 'name': 'other', 'status': 'PAUSED', 'region_code': 'us-east-1',
                 'service_type': 'TIMESCALEDB'}
        transport = FakeTransport((200, [dict(service('READY'), initial_password='should-not-print'), other]))
        code, out, err, _ = run(['list'], transport)
        self.assertEqual(code, provision.EXIT_OK, err)
        request = transport.requests[0]
        self.assertEqual((request.method, request.url, request.body), ('GET', SERVICES_URL, None))
        self.assertTrue(out.startswith('NAME'))
        for expected in ('reva-demo', 'svc123', 'READY', f'{HOST}:{PORT}', 'other', 'PAUSED', 'TIMESCALEDB'):
            self.assertIn(expected, out)
        self.assertNotIn('should-not-print', out)
        self.assertNotIn('initial_password', out)

    def test_list_accepts_wrapped_array_and_reports_empty_project(self):
        code, out, _, _ = run(['list'], FakeTransport((200, {'services': [service('READY')]})))
        self.assertEqual(code, provision.EXIT_OK)
        self.assertIn('svc123', out)
        code, out, _, _ = run(['list'], FakeTransport((200, [])))
        self.assertEqual(code, provision.EXIT_OK)
        self.assertIn('No services', out)

    def test_list_dry_run_sends_nothing(self):
        transport = FakeTransport()
        code, out, _, _ = run(['list', '--dry-run'], transport)
        self.assertEqual(code, provision.EXIT_OK)
        self.assertEqual(transport.requests, [])
        self.assertIn(f'GET {SERVICES_URL}', out)
        self.assertIn('Authorization: ***', out)


if __name__ == '__main__':
    unittest.main()
