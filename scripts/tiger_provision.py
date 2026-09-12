#!/usr/bin/env python3
"""Create or list Tiger Cloud PostgreSQL services for the Reva API through the public REST API.

Purpose: Provision the free shared Tiger Cloud service behind `REVA_STORAGE=postgres` and print its
    DATABASE_URL exactly once, with no paid default, no third-party dependency, and no credential on the
    command line.
Inputs: `create --name NAME [--region us-east-1] [--allow-paid --cpu-millis N --memory-gbs N]
    [--timeout-minutes 15] [--dry-run]` or `list [--dry-run]`; the environment variables
    TIGERDATA_ACCESS_KEY, TIGERDATA_SECRET_KEY and TIGERDATA_PROJECT_ID; HTTPS responses from
    https://console.cloud.tigerdata.com/public/api/v1.
Outputs: stdout carries one `DATABASE_URL=postgresql://tsdbadmin:<password>@<host>:<port>/tsdb?sslmode=require`
    line after a create, the planned request under --dry-run, or a password-free service table for list.
    stderr carries progress and errors with the access key, secret key and every known password masked.
Side effects: `create` calls the Tiger Cloud API and creates a database service in your project (free shared
    size unless --allow-paid). `list` and `--dry-run` change nothing. Nothing is written to disk.

Exit codes:
    0   success: the service reached READY, the dry run was printed, or the list was printed
    2   usage error, including a paid size or a region other than us-east-1 without --allow-paid
    3   TIGERDATA_ACCESS_KEY, TIGERDATA_SECRET_KEY or TIGERDATA_PROJECT_ID is missing or empty
    4   HTTP failure, non-2xx API response, or a response without the required fields
    5   the service was created but did not reach READY within --timeout-minutes; the DATABASE_URL line
        was still printed once when the endpoint was known, because the initial password is returned only
        by the create response
    130 interrupted with Ctrl-C; a create request may already have made a service, so run `list`
"""
import argparse
import base64
from dataclasses import dataclass
import json
import os
import re
import sys
import time
from typing import Callable, Iterator, Optional, TextIO
import urllib.error
import urllib.parse
import urllib.request

# --- API constants, free-tier defaults, and polling bounds ---
BASE_URL = 'https://console.cloud.tigerdata.com/public/api/v1'
ENVIRONMENT_NAMES = ('TIGERDATA_ACCESS_KEY', 'TIGERDATA_SECRET_KEY', 'TIGERDATA_PROJECT_ID')
FREE_SIZE = 'shared'
FREE_REGION = 'us-east-1'
DATABASE_USER = 'tsdbadmin'
DATABASE_NAME = 'tsdb'
READY = 'READY'
FAILED_STATUSES = frozenset({'DELETING', 'DELETED'})
POLL_SECONDS = 10.0
HTTP_TIMEOUT_SECONDS = 30
MAX_RESPONSE_BYTES = 1 << 20
MAX_ERROR_EXCERPT = 600
MASK = '***'

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_CREDENTIALS = 3
EXIT_API = 4
EXIT_TIMEOUT = 5
EXIT_INTERRUPTED = 130


# --- Errors that carry their process exit code ---
class ProvisionError(Exception):
    """Base error; `exit_code` is what main() returns after printing the masked message."""

    exit_code = EXIT_API


class UsageError(ProvisionError):
    exit_code = EXIT_USAGE


class CredentialError(ProvisionError):
    exit_code = EXIT_CREDENTIALS


class APIError(ProvisionError):
    exit_code = EXIT_API


class ReadinessTimeout(ProvisionError):
    exit_code = EXIT_TIMEOUT


# --- Secret masking applied to every stderr line and every error ---
# Known secrets are replaced literally; the patterns catch passwords the script has not learned yet
# (an error body that echoes an `initial_password` field, a connection URL, or a Basic header).
_PASSWORD_FIELD = re.compile(r'("(?:initial_)?password"\s*:\s*")(?:[^"\\]|\\.)*(")')
_URL_PASSWORD = re.compile(r'(://[^/\s:@]+:)[^@/\s]+@')
_BASIC_HEADER = re.compile(r'(Basic\s+)[A-Za-z0-9+/=]+')


class Redactor:
    def __init__(self) -> None:
        self._secrets: set[str] = set()

    def add(self, secret: Optional[str]) -> None:
        if secret:
            self._secrets.add(secret)

    def __call__(self, text: str) -> str:
        for secret in sorted(self._secrets, key=len, reverse=True):
            text = text.replace(secret, MASK)
        text = _PASSWORD_FIELD.sub(r'\g<1>' + MASK + r'\g<2>', text)
        text = _URL_PASSWORD.sub(r'\g<1>' + MASK + '@', text)
        return _BASIC_HEADER.sub(r'\g<1>' + MASK, text)


# --- Credentials come from the environment only ---
@dataclass(frozen=True)
class Credentials:
    access_key: str
    secret_key: str
    project_id: str

    @classmethod
    def from_environment(cls, environment) -> 'Credentials':
        values = {name: (environment.get(name) or '').strip() for name in ENVIRONMENT_NAMES}
        missing = [name for name in ENVIRONMENT_NAMES if not values[name]]
        if missing:
            raise CredentialError(
                'Export ' + ', '.join(missing) + ' in the environment; credentials are never accepted as arguments.')
        return cls(values['TIGERDATA_ACCESS_KEY'], values['TIGERDATA_SECRET_KEY'], values['TIGERDATA_PROJECT_ID'])

    def authorization(self) -> str:
        pair = f'{self.access_key}:{self.secret_key}'.encode('utf-8')
        return 'Basic ' + base64.b64encode(pair).decode('ascii')


# --- Service specification and the paid-size guard ---
@dataclass(frozen=True)
class ServiceSpec:
    name: str
    region: str = FREE_REGION
    cpu_millis: str = FREE_SIZE
    memory_gbs: str = FREE_SIZE

    @property
    def is_free(self) -> bool:
        return self.cpu_millis == FREE_SIZE and self.memory_gbs == FREE_SIZE and self.region == FREE_REGION

    def body(self) -> dict:
        # No `addons`: plain PostgreSQL. Sizes are strings in the Tiger API ("shared" or a number).
        return {'name': self.name, 'cpu_millis': self.cpu_millis, 'memory_gbs': self.memory_gbs,
                'region_code': self.region}


def plan_service(name: str, region: str, cpu_millis: Optional[int], memory_gbs: Optional[int],
                 allow_paid: bool) -> ServiceSpec:
    """Validate the requested service and refuse anything billable unless --allow-paid was given."""
    name = name.strip()
    if not 1 <= len(name) <= 128 or not name.isprintable():
        raise UsageError('--name must be 1-128 printable characters.')
    region = region.strip()
    if not re.fullmatch(r'[a-z]{2}-[a-z]+-\d', region):
        raise UsageError(f'--region {region!r} does not look like a cloud region code such as us-east-1.')
    if (cpu_millis is None) != (memory_gbs is None):
        raise UsageError('Pass --cpu-millis and --memory-gbs together, or neither for the free shared size.')
    spec = ServiceSpec(
        name=name, region=region,
        cpu_millis=FREE_SIZE if cpu_millis is None else str(cpu_millis),
        memory_gbs=FREE_SIZE if memory_gbs is None else str(memory_gbs))
    if spec.is_free or allow_paid:
        return spec
    if spec.cpu_millis != FREE_SIZE or spec.memory_gbs != FREE_SIZE:
        raise UsageError(
            f'cpu_millis={spec.cpu_millis} memory_gbs={spec.memory_gbs} is a paid size. Re-run with --allow-paid '
            'to create a billable service, or omit both flags for the free shared service.')
    raise UsageError(
        f'Free shared services exist only in {FREE_REGION}; region {spec.region} creates a billable service. '
        f'Re-run with --allow-paid or use --region {FREE_REGION}.')


# --- HTTPS transport: bounded body, no redirects, credentials only in the header ---
class _RefuseRedirects(urllib.request.HTTPRedirectHandler):
    # A redirect would replay the Basic header to another host; treat 3xx as an error instead.
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D401 - urllib hook
        return None


class URLLibTransport:
    def __init__(self, timeout_seconds: float = HTTP_TIMEOUT_SECONDS) -> None:
        self._timeout = timeout_seconds
        self._opener = urllib.request.build_opener(_RefuseRedirects)

    def send(self, method: str, url: str, headers: dict, body: Optional[bytes]) -> tuple[int, bytes]:
        if not url.startswith('https://'):
            raise APIError('Refusing a non-HTTPS request.')
        request = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with self._opener.open(request, timeout=self._timeout) as response:
                return response.status, response.read(MAX_RESPONSE_BYTES)
        except urllib.error.HTTPError as error:
            return error.code, error.read(MAX_RESPONSE_BYTES)


# --- Tiger Cloud REST client ---
class TigerClient:
    def __init__(self, credentials: Credentials, transport) -> None:
        self._credentials = credentials
        self._transport = transport
        project = urllib.parse.quote(credentials.project_id, safe='')
        self.services_url = f'{BASE_URL}/projects/{project}/services'

    def service_url(self, service_id: str) -> str:
        return f'{self.services_url}/{urllib.parse.quote(service_id, safe="")}'

    def headers(self, body: Optional[dict]) -> dict:
        headers = {'Authorization': self._credentials.authorization(), 'Accept': 'application/json',
                   'User-Agent': 'reva-tiger-provision/1'}
        if body is not None:
            headers['Content-Type'] = 'application/json'
        return headers

    def request(self, method: str, url: str, body: Optional[dict] = None):
        payload = None if body is None else json.dumps(body).encode('utf-8')
        try:
            status, raw = self._transport.send(method, url, self.headers(body), payload)
        except (OSError, ValueError) as error:  # URLError, timeouts, TLS failures
            raise APIError(f'{method} {url} failed before a response arrived: {error}') from None
        text = raw.decode('utf-8', 'replace')
        if not 200 <= status < 300:
            excerpt = ' '.join(text.split())[:MAX_ERROR_EXCERPT] or '<empty body>'
            raise APIError(f'{method} {url} returned HTTP {status}: {excerpt}')
        if not text.strip():
            return {}
        try:
            return json.loads(text)
        except ValueError:
            raise APIError(f'{method} {url} returned a body that is not JSON.') from None

    def create_service(self, spec: ServiceSpec) -> dict:
        service = self.request('POST', self.services_url, spec.body())
        if not isinstance(service, dict):
            raise APIError('The create response was not a JSON object.')
        return service

    def get_service(self, service_id: str) -> dict:
        service = self.request('GET', self.service_url(service_id))
        if not isinstance(service, dict):
            raise APIError('The service response was not a JSON object.')
        return service

    def list_services(self) -> list:
        data = self.request('GET', self.services_url)
        if isinstance(data, dict):
            data = data.get('services', data.get('data'))
        if not isinstance(data, list):
            raise APIError('The list response did not contain a service array.')
        return data


# --- Response field extraction and the connection URL ---
def required_string(service: dict, key: str) -> str:
    value = service.get(key)
    if not isinstance(value, str) or not value.strip():
        raise APIError(f'The API response did not include a non-empty "{key}".')
    return value.strip()


def endpoint_of(service: dict) -> Optional[tuple[str, int]]:
    endpoint = service.get('endpoint')
    if not isinstance(endpoint, dict):
        return None
    host, port = endpoint.get('host'), endpoint.get('port')
    if isinstance(port, str) and port.isdigit():
        port = int(port)
    if isinstance(host, str) and host.strip() and isinstance(port, int) and 1 <= port <= 65535:
        return host.strip(), port
    return None


def database_url(host: str, port: int, password: str) -> str:
    # Reserved characters are percent-encoded so the server's URL parser reads the exact password.
    return (f'postgresql://{DATABASE_USER}:{urllib.parse.quote(password, safe="")}@{host}:{port}/'
            f'{DATABASE_NAME}?sslmode=require')


# --- Readiness polling bounded by a monotonic deadline ---
def poll_service(client: TigerClient, service_id: str, timeout_seconds: float, sleep: Callable[[float], None],
                 clock: Callable[[], float], interval: float = POLL_SECONDS) -> Iterator[dict]:
    """Yield each service response until READY; raise ReadinessTimeout after the deadline."""
    deadline = clock() + timeout_seconds
    while True:
        service = client.get_service(service_id)
        yield service
        status = service.get('status')
        if status == READY:
            return
        if status in FAILED_STATUSES:
            raise APIError(f'Service {service_id} entered status {status} instead of READY.')
        remaining = deadline - clock()
        if remaining <= 0:
            raise ReadinessTimeout(
                f'Service {service_id} is still {status or "unknown"} after {timeout_seconds / 60:g} minutes. '
                'It keeps provisioning in Tiger Cloud; check `list` or the Console before retrying.')
        sleep(min(interval, remaining))


# --- Output helpers ---
def print_dry_run(out: TextIO, method: str, url: str, headers: dict, body: Optional[dict]) -> None:
    out.write('DRY RUN: nothing was sent.\n')
    out.write(f'{method} {url}\n')
    for name, value in headers.items():
        out.write(f'{name}: {MASK if name == "Authorization" else value}\n')
    if body is not None:
        out.write(json.dumps(body, indent=2) + '\n')


def format_service_table(services: list) -> str:
    """Render name, id, status, region, type and host:port; the password field is never read."""
    header = ('NAME', 'SERVICE_ID', 'STATUS', 'REGION', 'TYPE', 'ENDPOINT')
    rows = []
    for service in services:
        if not isinstance(service, dict):
            continue
        endpoint = endpoint_of(service)
        rows.append((
            str(service.get('name', '')), str(service.get('service_id', '')), str(service.get('status', '')),
            str(service.get('region_code', '')), str(service.get('service_type', '')),
            f'{endpoint[0]}:{endpoint[1]}' if endpoint else ''))
    widths = [max(len(row[index]) for row in [header, *rows]) for index in range(len(header))]
    lines = ['  '.join(cell.ljust(widths[index]) for index, cell in enumerate(row)).rstrip()
             for row in [header, *rows]]
    return '\n'.join(lines) + '\n'


# --- Command implementations ---
def run_create(args: argparse.Namespace, client: TigerClient, out: TextIO, log: Callable[[str], None],
               redact: Redactor, sleep: Callable[[float], None], clock: Callable[[], float]) -> int:
    spec = plan_service(args.name, args.region, args.cpu_millis, args.memory_gbs, args.allow_paid)
    body = spec.body()
    if args.dry_run:
        print_dry_run(out, 'POST', client.services_url, client.headers(body), body)
        return EXIT_OK
    kind = 'free shared' if spec.is_free else 'PAID'
    log(f'Creating {kind} service {spec.name!r} in {spec.region} (project {client.services_url.split("/")[-2]}).')
    service = client.create_service(spec)
    service_id = required_string(service, 'service_id')
    password = required_string(service, 'initial_password')
    redact.add(password)
    status = service.get('status')
    log(f'Service {service_id} created: status={status} service_type={service.get("service_type")}. '
        f'Waiting up to {args.timeout_minutes:g} minutes for {READY}.')

    printed = False

    def print_url_once(candidate: dict) -> None:
        nonlocal printed
        endpoint = endpoint_of(candidate)
        if printed or endpoint is None:
            return
        out.write('DATABASE_URL=' + database_url(endpoint[0], endpoint[1], password) + '\n')
        out.flush()
        printed = True

    print_url_once(service)
    try:
        if status != READY:
            for polled in poll_service(client, service_id, args.timeout_minutes * 60, sleep, clock):
                print_url_once(polled)
                if polled.get('status') != status:
                    status = polled.get('status')
                    log(f'Service {service_id}: status={status}.')
    except ReadinessTimeout as error:
        log(str(error))
        if not printed:
            log('No endpoint host/port was returned, so the connection URL could not be printed. Use '
                f'`tiger db connection-string {service_id} --with-password` or reset the password in the Console.')
        return EXIT_TIMEOUT
    if not printed:
        raise APIError(
            f'Service {service_id} is {READY} but the API never returned endpoint.host/port. Use '
            f'`tiger db connection-string {service_id} --with-password` or reset the password in the Console.')
    log(f'Service {service_id} is {READY}. Set REVA_STORAGE=postgres and the DATABASE_URL line above on the API host.')
    return EXIT_OK


def run_list(args: argparse.Namespace, client: TigerClient, out: TextIO, redact: Redactor) -> int:
    if args.dry_run:
        print_dry_run(out, 'GET', client.services_url, client.headers(None), None)
        return EXIT_OK
    services = client.list_services()
    if not services:
        out.write('No services in this project.\n')
        return EXIT_OK
    out.write(redact(format_service_table(services)))
    return EXIT_OK


# --- Argument parsing ---
def positive_int(text: str) -> int:
    try:
        value = int(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f'{text!r} is not an integer.') from None
    if value <= 0:
        raise argparse.ArgumentTypeError('must be a positive integer.')
    return value


def positive_minutes(text: str) -> float:
    try:
        value = float(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f'{text!r} is not a number of minutes.') from None
    if not 0 < value <= 24 * 60:
        raise argparse.ArgumentTypeError('must be between 0 and 1440 minutes.')
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='tiger_provision.py', formatter_class=argparse.RawDescriptionHelpFormatter,
        description='Create or list Tiger Cloud PostgreSQL services for Reva (standard library only).',
        epilog=('Credentials come only from TIGERDATA_ACCESS_KEY, TIGERDATA_SECRET_KEY and TIGERDATA_PROJECT_ID.\n'
                'The default create request is the free shared service in us-east-1; paid sizes need --allow-paid.\n'
                'Exit codes: 0 ok, 2 usage, 3 credentials, 4 API/HTTP, 5 not READY in time, 130 interrupted.'))
    commands = parser.add_subparsers(dest='command', metavar='{create,list}', required=True)
    create = commands.add_parser('create', help='create a service and print its DATABASE_URL once')
    create.add_argument('--name', required=True, help='service name, 1-128 characters')
    create.add_argument('--region', default=FREE_REGION,
                        help=f'region code (default {FREE_REGION}; free shared services exist only there)')
    create.add_argument('--allow-paid', action='store_true',
                        help='permit a billable size or region; never implied')
    create.add_argument('--cpu-millis', type=positive_int, metavar='N', help='paid CPU in millicores')
    create.add_argument('--memory-gbs', type=positive_int, metavar='N', help='paid memory in GB')
    create.add_argument('--timeout-minutes', type=positive_minutes, default=15.0, metavar='MIN',
                        help='how long to wait for READY (default 15)')
    create.add_argument('--dry-run', action='store_true', help='print the request without sending it')
    listing = commands.add_parser('list', help='list services: name, id, status, host; no passwords')
    listing.add_argument('--dry-run', action='store_true', help='print the request without sending it')
    return parser


# --- Entry point with masked error reporting ---
def main(argv: Optional[list] = None, environment=None, transport=None, out: Optional[TextIO] = None,
         err: Optional[TextIO] = None, sleep: Callable[[float], None] = time.sleep,
         clock: Callable[[], float] = time.monotonic) -> int:
    args = build_parser().parse_args(argv)
    environment = os.environ if environment is None else environment
    out = sys.stdout if out is None else out
    err = sys.stderr if err is None else err
    redact = Redactor()

    def log(message: str) -> None:
        err.write(redact(message) + '\n')
        err.flush()

    try:
        credentials = Credentials.from_environment(environment)
        redact.add(credentials.access_key)
        redact.add(credentials.secret_key)
        client = TigerClient(credentials, URLLibTransport() if transport is None else transport)
        if args.command == 'create':
            return run_create(args, client, out, log, redact, sleep, clock)
        return run_list(args, client, out, redact)
    except ProvisionError as error:
        log(f'tiger_provision: {error}')
        return error.exit_code
    except KeyboardInterrupt:
        log('tiger_provision: interrupted. A create request may already have made a service; run `list` to check.')
        return EXIT_INTERRUPTED
    except Exception as error:  # noqa: BLE001 - every unexpected failure must still be masked
        log(f'tiger_provision: unexpected {type(error).__name__}: {error}')
        return EXIT_API


if __name__ == '__main__':
    sys.exit(main())
