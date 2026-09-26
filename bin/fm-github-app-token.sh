#!/usr/bin/env bash
# Mint and privately cache a GitHub App installation token for Firstmate-owned
# automation, or run one explicitly allowlisted GitHub CLI command with that
# token in its environment.
#
# Opt in by writing one absolute credential-JSON path to the local gitignored
# config/github-app-credentials file under the effective FM_HOME. The JSON must
# contain app_id, installation_id, and private_key_file. A relative
# private_key_file is resolved beside the credential JSON. The private key and
# token are never passed in argv. The short-lived cache lives at
# state/github-app-installation-token.json with mode 0600 and refreshes five
# minutes before GitHub's expiry.
#
# Usage:
#   fm-github-app-token.sh run-safe <gh|gh-axi> <pr|release> [args...]
#
# run-safe never prints the token. When the pointer is absent, it execs the
# requested command unchanged. When configured authentication cannot be
# prepared, or the App installation cannot resolve or reach the repository,
# it emits one generic diagnostic and runs the command once with the caller's
# existing GitHub login. Every other command failure surfaces unchanged.
#
# The allowlist deliberately excludes `gh project` and arbitrary `gh api`
# requests. GitHub App installations cannot access user-owned Projects v2, so
# those calls must continue to use the captain's own gh authentication.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
POINTER="$CONFIG/github-app-credentials"
CACHE="$STATE/github-app-installation-token.json"
REPO_UNREACHABLE='Could not resolve to a Repository|Resource not accessible by integration|HTTP 404|^code: REPO_NOT_FOUND$'

usage() {
  printf 'usage: fm-github-app-token.sh run-safe <gh|gh-axi> <pr|release> [args...]\n' >&2
}

pointer_path() {
  local line extra
  [ -f "$POINTER" ] && [ ! -L "$POINTER" ] || return 3
  IFS= read -r line < "$POINTER" || return 1
  [ -n "$line" ] || return 1
  case "$line" in /*) ;; *) return 1 ;; esac
  extra=$(sed -n '2,$p' "$POINTER" 2>/dev/null | sed '/^[[:space:]]*$/d' | head -1)
  [ -z "$extra" ] || return 1
  printf '%s\n' "$line"
}

mint_or_read_token() {
  local credentials
  credentials=$(pointer_path) || return $?
  FM_GITHUB_APP_CREDENTIALS="$credentials" FM_GITHUB_APP_CACHE="$CACHE" node <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const path = require('path');

const credentialsPath = process.env.FM_GITHUB_APP_CREDENTIALS;
const cachePath = process.env.FM_GITHUB_APP_CACHE;
const refreshSkewMs = 5 * 60 * 1000;
const lockPath = `${cachePath}.lock`;

function fail() {
  process.exitCode = 1;
}

function privateRegularFile(file, requiredMode) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) return false;
  if (requiredMode !== undefined && (stat.mode & 0o777) !== requiredMode) return false;
  return true;
}

function validToken(value) {
  return typeof value === 'string' && value.length >= 20 && value.length <= 512 && !/\s/.test(value);
}

function readCache() {
  try {
    if (!privateRegularFile(cachePath, 0o600)) return null;
    const value = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    const expires = Date.parse(value.expires_at);
    if (!validToken(value.token) || !Number.isFinite(expires) || expires <= Date.now() + refreshSkewMs) return null;
    return value.token;
  } catch {
    return null;
  }
}

function ensureCacheParent() {
  const parent = path.dirname(cachePath);
  if (!fs.existsSync(parent)) fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
  const stat = fs.lstatSync(parent);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('unsafe cache directory');
}

function base64url(value) {
  return Buffer.from(value).toString('base64url');
}

function writeCache(token, expiresAt) {
  const parent = path.dirname(cachePath);
  ensureCacheParent();
  const temporary = `${cachePath}.tmp.${process.pid}.${crypto.randomBytes(6).toString('hex')}`;
  const fd = fs.openSync(temporary, 'wx', 0o600);
  try {
    fs.writeFileSync(fd, `${JSON.stringify({ token, expires_at: expiresAt })}\n`, { encoding: 'utf8' });
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.chmodSync(temporary, 0o600);
  fs.renameSync(temporary, cachePath);
}

function acquireLock() {
  try {
    fs.mkdirSync(lockPath, { mode: 0o700 });
    return true;
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
  }
  try {
    const stat = fs.lstatSync(lockPath);
    if (stat.isDirectory() && !stat.isSymbolicLink() && Date.now() - stat.mtimeMs > 120000) {
      fs.rmdirSync(lockPath);
      fs.mkdirSync(lockPath, { mode: 0o700 });
      return true;
    }
  } catch {
    return false;
  }
  return false;
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function mint(credentials, key) {
  return new Promise((resolve, reject) => {
    const now = Math.floor(Date.now() / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const payload = base64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(credentials.app_id) }));
    const signingInput = `${header}.${payload}`;
    const signature = crypto.sign('RSA-SHA256', Buffer.from(signingInput), key).toString('base64url');
    const jwt = `${signingInput}.${signature}`;
    const request = https.request({
      hostname: 'api.github.com',
      path: `/app/installations/${credentials.installation_id}/access_tokens`,
      method: 'POST',
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${jwt}`,
        'User-Agent': 'wonder-media-firstmate',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      timeout: 15000,
    }, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;
        if (body.length > 1024 * 1024) request.destroy(new Error('response too large'));
      });
      response.on('end', () => {
        if (response.statusCode !== 201) return reject(new Error('token request failed'));
        try {
          const value = JSON.parse(body);
          if (!validToken(value.token) || !Number.isFinite(Date.parse(value.expires_at))) {
            return reject(new Error('invalid token response'));
          }
          resolve({ token: value.token, expires_at: value.expires_at });
        } catch (error) {
          reject(error);
        }
      });
    });
    request.on('timeout', () => request.destroy(new Error('token request timed out')));
    request.on('error', reject);
    request.end();
  });
}

async function main() {
  const cached = readCache();
  if (cached) {
    process.stdout.write(`${cached}\n`);
    return;
  }

  ensureCacheParent();
  let locked = acquireLock();
  if (!locked) {
    for (let attempt = 0; attempt < 50; attempt += 1) {
      await wait(100);
      const concurrent = readCache();
      if (concurrent) {
        process.stdout.write(`${concurrent}\n`);
        return;
      }
    }
    throw new Error('token cache lock unavailable');
  }

  try {
    const afterLock = readCache();
    if (afterLock) {
      process.stdout.write(`${afterLock}\n`);
      return;
    }
    if (!privateRegularFile(credentialsPath)) throw new Error('unsafe credentials file');
    const credentials = JSON.parse(fs.readFileSync(credentialsPath, 'utf8'));
    if (!/^\d+$/.test(String(credentials.app_id)) || !/^\d+$/.test(String(credentials.installation_id))) {
      throw new Error('invalid app identity');
    }
    if (typeof credentials.private_key_file !== 'string' || credentials.private_key_file.length === 0) {
      throw new Error('invalid private key path');
    }
    const keyPath = path.isAbsolute(credentials.private_key_file)
      ? credentials.private_key_file
      : path.resolve(path.dirname(credentialsPath), credentials.private_key_file);
    if (!privateRegularFile(keyPath)) throw new Error('unsafe private key file');
    const key = fs.readFileSync(keyPath);
    const result = await mint(credentials, key);
    writeCache(result.token, result.expires_at);
    process.stdout.write(`${result.token}\n`);
  } finally {
    try { fs.rmdirSync(lockPath); } catch {}
  }
}

main().catch(fail);
NODE
}

run_safe() {
  local executable operation token rc out err
  [ "$#" -ge 2 ] || { usage; return 2; }
  executable=${1##*/}
  operation=$2
  case "$executable:$operation" in
    gh:pr|gh:release|gh-axi:pr|gh-axi:release) ;;
    *)
      echo "error: GitHub App authentication is not approved for this command" >&2
      return 2
      ;;
  esac

  if [ ! -e "$POINTER" ] && [ ! -L "$POINTER" ]; then
    exec "$@"
  fi

  token=$(mint_or_read_token 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$token" ]; then
    out=$(mktemp "${TMPDIR:-/tmp}/fm-gh-app-out.XXXXXX") || out=
    err=$(mktemp "${TMPDIR:-/tmp}/fm-gh-app-err.XXXXXX") || err=
    if [ -n "$out" ] && [ -n "$err" ]; then
      GH_TOKEN=$token GITHUB_TOKEN=$token "$@" > "$out" 2> "$err"
      rc=$?
      if [ "$rc" -ne 0 ] && cat "$out" "$err" | grep -qE "$REPO_UNREACHABLE"; then
        rm -f "$out" "$err"
        echo "warning: GitHub App installation cannot reach this repository; retrying with captain GitHub login" >&2
        exec "$@"
      fi
      cat "$out"
      cat "$err" >&2
      rm -f "$out" "$err"
      return "$rc"
    fi
    rm -f "$out" "$err"
  fi
  echo "warning: GitHub App authentication unavailable; using captain GitHub login" >&2
  exec "$@"
}

case "${1:-}" in
  run-safe)
    shift
    run_safe "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
