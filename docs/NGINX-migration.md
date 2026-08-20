# NGINX: Bitnami → nginx:alpine Migration Guide
**Project**: aspaDB-workbench | **Path**: docs/NGINX-migration.md
**Version**: v1.5.0 | **Last Updated**: 2026-08-19
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.5.0 (2026-08-19): Added **Certificate Management (Dev Only)** section, documenting
  the `greentech.consulting` wildcard cert renewal/sync process built out this session
  after finding `aspaDB-dev`'s cert had been expired ~8.5 months. Explicitly flagged as
  dev-only per the user: **production uses a separate, automated DNS renewal and
  key-sync mechanism** — nothing in this section (manual DNS-01, `gtc-portainer`,
  `sync-greentech-cert.sh`) applies to prod. Also updated `services/nginx/` layout
  references: cert paths flattened (see `aspa-443.conf`/`aspa-678.conf` v1.1.0), new
  `docker/iotstack/dev/nginx/scripts/` directory holding the sync script.
- v1.4.0 (2026-08-19): Corrected every actionable path in this guide (Pre-Migration
  Checklist, Migration Steps, Troubleshooting, Verification Checklist) from
  `/mnt/data/nginx/...` to `./volumes/nginx/...` — the v1.1.0 entry below asserted
  the opposite (that the committed config uses `/mnt/data/nginx`), which was wrong:
  the "New Configuration" YAML in this same doc, `nginx.yml`, and the live host all
  use `./volumes/nginx/...`. Confirmed on dev: `/root/IOTstack/volumes/nginx/` is the
  actual mount source (fresh, actively written); `/mnt/data/nginx/` still exists on
  disk but is stale leftover from the pre-migration Bitnami setup, last touched
  Sep 2025, and is not mounted into the container.

  Also marked this guide complete — verified live on dev (`aspaDB-dev`,
  container `nginx`, `nginx:alpine`, healthy) via SSH. Found and fixed a real
  gap this guide had missed: the migrated `nginx:` block was live in dev's
  `/root/IOTstack/docker-compose.yml` (Bitnami block present but commented
  "DEPRECATED"), but the repo's own `docker/iotstack/docker-compose.yml` still
  had the *old, active* Bitnami block — the migration was applied to the host
  directly and never merged back into git. Repo now matches dev byte-for-byte
  for this service block. Also hand-applied the `aspa-8081.conf` ACME-listener
  cleanup (dropped dead `listen 80;`) from the same session to dev's
  `services/nginx/sites-enabled/`, validated with `nginx -t`, and reloaded —
  confirmed via `curl`: `/` still 301s, `/.well-known/acme-challenge/` 404s
  without redirecting.
- v1.3.0 (2026-08-19): Fixed the post-fix "unhealthy" status — the healthcheck's
  `-L` flag was following the app's 301 out to its external hostname
  (`dev.greentech.consulting:678`) and hanging past the 10s timeout even though nginx
  itself was responding instantly. Removed `-L` from `nginx.yml`'s healthcheck;
  `curl -f` alone already passes on a 301. Confirmed IPv6 is not implicated: nginx
  has no `listen [::]` directives in any site config, so `DISABLE_IPV6` and the
  `[::]`-bound ports visible in `docker ps` are Docker's own default port-publishing
  behavior, not an nginx-level issue.
- v1.2.0 (2026-08-19): Fixed two latent bugs found while diagnosing the post-migration
  restart loop: `pid /var/run/nginx/nginx.pid;` referenced a subdirectory nginx never
  creates (changed to `pid /var/run/nginx.pid;`); each of the three site configs
  independently included `blockuseragents.rules`, which duplicates the `map` block
  once all three are loaded together via `conf.d/*.conf` (nginx refuses to start with
  "duplicate map variable" or `$blockedagent` already defined) — the include now lives
  once in `nginx.conf`'s `http {}` block instead. Also documented the actual reported
  crash (`mkdir() "/opt/bitnami/nginx/tmp/client_body" failed`) and its cause.
- v1.1.0 (2026-08-19): Aligned guide with the committed nginx:alpine config set
  (docker/iotstack/dev/nginx/, commit 23c5f85): volumes use /mnt/data/nginx
  (html/log/cache/run), not ./volumes/nginx; blockuseragents.rules stays in
  sites-enabled (included via /etc/nginx/conf.d/); site file renamed aspa-80.conf →
  aspa-8081.conf; added aspa-443.conf + aspa-678.conf coverage; bitnami baseline
  block corrected to match committed v1.0.0.
- v1.0.0 (2026-08-19): Initial migration guide - Bitnami nginx → official nginx:alpine

**Status**: Complete — live on dev (`aspaDB-dev`, container `nginx`, healthy)  
**Target**: Replace Bitnami nginx with official nginx:alpine  
**Scope**: Docker Compose service definition, configuration files, and health checks  
**Duration**: ~15 minutes  
**Risk**: Low (tested, easy rollback)

---

## Why Migrate from Bitnami?

| Issue | Impact | Resolution |
|-------|--------|-----------|
| **Bitnami deprecation** | "Limited free images after Aug 28, 2025" | Official nginx:alpine always free, actively maintained |
| **Custom config mount failure** | nginx.conf mount to `/opt/bitnami/nginx/conf/` ignored | Official nginx respects `/etc/nginx/nginx.conf` mounts |
| **Missing vhosts directory** | Init script error: `realpath: /bitnami/nginx/conf/vhosts: No such file` | No Bitnami-specific init scripts in alpine |
| **Health check 301 redirects** | Container marked "unhealthy" despite working HTTPS | `curl -f` alone treats a 301 as a pass — no `-L` needed (see note below) |
| **Larger image size** | ~140MB Bitnami vs ~50MB alpine | 3x smaller, faster startup |

---

## Current Configuration (Bitnami)

```yaml
nginx:
  container_name: nginx
  image: 'bitnami/nginx:latest'
  user: "root"
  restart: unless-stopped
  environment:
    DISABLE_IPV6: 'true'
  env_file:
    - ./services/nginx/nginx.env
  ports:
    - '80:8081'      # host:container
    - '678:678'
    - '443:443'
  volumes:
    - ./services/nginx/letsencrypt:/etc/letsencrypt
    - ./services/nginx/nginx.conf:/opt/bitnami/nginx/conf/nginx.conf:ro
    - ./services/nginx/sites-enabled:/opt/bitnami/nginx/conf/server_blocks
    - /mnt/data/nginx/html:/app
    - /mnt/data/nginx/log:/opt/bitnami/nginx/logs
  healthcheck:
    test: ["CMD", "curl", "-f", "-L", "http://localhost/"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s
```

---

## New Configuration (nginx:alpine)

The complete config set is committed at `docker/iotstack/dev/nginx/` (`nginx.yml`,
`nginx.conf`, `aspa-8081.conf`, `aspa-443.conf`, `aspa-678.conf` — commit `23c5f85`).
Replace the entire `nginx:` service block in `docker-compose.yml`:

```yaml
  nginx:
    # aspa-Frontend Manager / Balancer
    container_name: nginx
    image: 'nginx:alpine'
    user: "root"
    restart: unless-stopped
    environment:
      DISABLE_IPV6: 'true'
    env_file:
      - ./services/nginx/nginx.env
    ports:
      - '80:8081'      # Keep: host 80 → container 8081
      - '678:678'      # Keep: custom HTTPS port
      - '443:443'      # Keep: standard HTTPS
    volumes:
      # SSL configuration
      - ./services/nginx/letsencrypt:/etc/letsencrypt
      # NGINX shared configuration (read-only)
      - ./services/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./services/nginx/blockuseragents.rules:/etc/nginx/blockuseragents.rules:ro
      # Site configurations (read-only)
      - ./services/nginx/sites-enabled:/etc/nginx/conf.d:ro
      # HTML pages (persistent)
      - ./volumes/nginx/html:/app
      # Logs (persistent, for debugging/analysis)
      - ./volumes/nginx/log:/var/log/nginx
      # Cache and run stay ephemeral (no host mount)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s```

**No `-L` on the health check.** `aspa-8081.conf`'s `/` location returns a 301 to an
*external* absolute URL (`https://dev.greentech.consulting:678$request_uri`), not a
local path. `curl -f` alone already counts a 301 as a healthy response (`-f` only
fails on 4xx/5xx) — adding `-L` makes curl leave the container and chase that
redirect out to the public hostname, which routinely hangs or is slow enough to blow
past the healthcheck's `timeout: 10s`, flagging the container "unhealthy" even though
nginx answered the original request instantly. See **Troubleshooting** below if you
hit this.

### Key Changes:

| Aspect | Bitnami | Alpine | Note |
|--------|---------|--------|------|
| Image | `bitnami/nginx:latest` | `nginx:alpine` | Official, no deprecation |
| Config path | `/opt/bitnami/nginx/conf/nginx.conf` | `/etc/nginx/nginx.conf` | Standard Linux path |
| Sites path | `/opt/bitnami/nginx/conf/server_blocks` | `/etc/nginx/conf.d` | Standard convention |
| Log path | `/opt/bitnami/nginx/logs` | `/var/log/nginx` | Standard location |
| Health check | `http://localhost/` | `http://localhost:8081/`, no `-L` | Must match container listen port; don't follow the 301 |
| Init scripts | Bitnami-specific | None | Alpine = pure nginx binary |

---

## Configuration Files

### 1. Update `./services/nginx/nginx.conf`

Replace entire file:

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    # Compression
    gzip on;
    gzip_vary on;
    gzip_comp_level 2;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Body size
    client_max_body_size 80M;
    
    # WebSocket support
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    # Shared user-agent blocklist (declared once here, not per-site — each
    # aspa-*.conf including it independently would duplicate the map block
    # once conf.d/*.conf loads all of them into this same http context)
    include /etc/nginx/blockuseragents.rules;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
```

**What changed:**
- All `/opt/bitnami/nginx/` paths → standard `/var/log/nginx`, `/var/run`
- Added `user nginx;` (alpine runs as this user)
- Removed Bitnami-specific temp path overrides — `client_body_temp_path`,
  `proxy_temp_path`, etc. are intentionally **not** set; nginx falls back to its
  compiled-in defaults (`/var/cache/nginx/client_temp`, `/proxy_temp`, ...), which
  already exist and are writable in the official image. Leaving an old Bitnami
  `nginx.conf` in place — one that still hardcodes these under `/opt/bitnami/nginx/tmp/`
  — is exactly what causes the crash in **Troubleshooting** below.
- `pid /var/run/nginx.pid;` (no `nginx/` subdirectory — nginx does not create the
  pid file's parent directory itself, unlike the temp-path directories above, so a
  path like `/var/run/nginx/nginx.pid` fails at startup since that subdir never exists)
- `include /etc/nginx/blockuseragents.rules;` lives here, once, instead of being
  repeated in every site config (see item 2 below)
- Kept all your gzip, SSL, and tuning settings

### 2. Shared rules file (blockuseragents.rules)

`blockuseragents.rules` **moved to  `./services/nginx/`** and mounted read-only as:
./services/nginx/blockuseragents.rules:/etc/nginx/blockuseragents.rules:ro
The `sites-enabled` directory is mounted to `/etc/nginx/conf.d`. No move needed.

It is included **once**, from `nginx.conf`'s `http {}` block (see section 1). Do
**not** also `include /etc/nginx/blockuseragents.rules;` inside the individual
`aspa-*.conf` site files — `conf.d/*.conf` loads all site files into the same `http`
context, so including it in more than one place redeclares the `map $http_user_agent
$blockedagent {...}` block and nginx refuses to start ("duplicate map variable" /
`$blockedagent` already defined).

### 3. Update `./services/nginx/sites-enabled/aspa-8081.conf`

The HTTP listener is committed as **`aspa-8081.conf`** (renamed from `aspa-80.conf`),
`listen` changed from **80** to **8081** to match the docker-compose.yml `80:8081` mapping:

```nginx
server {
    if ($blockedagent) { return 403; }
    if ($request_method !~ ^(GET|HEAD|POST)$) { return 444; }

    listen 8081;  # matches container port (host 80 → container 8081)
    server_name _;
    server_tokens off;

    # Error pages
    location = /40x.html { root /usr/share/nginx/html; }
    location = /50x.html { root /usr/share/nginx/html; }

    # Main redirect to HTTPS
    location / {
        access_log /var/log/nginx/aspa-8081-access.log;
        error_log /var/log/nginx/aspa-8081-error.log warn;
        return 301 https://dev.greentech.consulting:678$request_uri;
    }

    # Let's Encrypt ACME challenge (do NOT redirect this)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Specific aspasales redirect
    location /aspasales {
        return 301 https://dev.greentech.consulting:678/aspasales;
    }
}
```

**What changed:**
- `listen 80;` → `listen 8081;` (matches docker-compose.yml `80:8081` mapping)
- Log paths: `/opt/bitnami/nginx/logs/` → `/var/log/nginx/` (standard)
- Log filenames: `aspa-80-*.log` → `aspa-8081-*.log` (matches the file rename)
- `include /etc/nginx/blockuseragents.rules;` **removed** from this file — it's
  declared once in `nginx.conf` now (see section 1); leaving it here too would
  duplicate the `map` block and break `nginx -t`

### 4. HTTPS site configs — `aspa-443.conf` and `aspa-678.conf`

The two HTTPS listeners are committed as **`aspa-443.conf`** (port 443) and
**`aspa-678.conf`** (port 678, main app proxy). Both were updated similarly:
- `include /etc/nginx/blockuseragents.rules;` **removed** from both files for the
  same duplicate-`map` reason as above (it's now only in `nginx.conf`)
- Replace all `/opt/bitnami/nginx/logs/` → `/var/log/nginx/`
- Replace all `/opt/bitnami/nginx/conf/` → `/etc/nginx/conf.d/`
- `listen 443 ssl;` / `listen 678 ssl;` with `http2 on;` (unchanged)
- Let's Encrypt certs: `greentech.consulting` (fullchain/privkey/chain) + `options-ssl-nginx.conf` + `ssl-dhparams.pem`
- `aspa-678.conf` keeps the Vouch auth (`/vouch-validate`, `@error401`) and all app proxies
  (`aspa_APP`, `aspaFLOWS_API`, `aspaAUTH`, `aspa-login`, `aspaSTOCK`, `aspaSALES`, CRM, cams, kkr)

---

## Certificate Management (Dev Only)

> **This section describes `aspaDB-dev`'s certificate process specifically.
> Production uses a separate, automated DNS renewal and key-sync mechanism — do
> not assume anything below applies there.**

### What happened (2026-08-19)

`aspaDB-dev`'s nginx (ports 443 and 678) was found serving a `*.greentech.consulting`
wildcard cert that had been **expired for about 8.5 months** (issued 2025-09-06,
expired 2025-12-05) — not close to expiry, already long past it, silently, because
nothing ever alerted on it. Root cause: the actual certbot renewal only ever runs on
a different host (`gtc-portainer`), and the resulting cert was never re-synced to
`aspaDB-dev` after the last successful renewal back in September 2025.

### Why renewal is manual, not automated

Domain `greentech.consulting` is registered through **Domains Made Easy**, a GoDaddy
reseller storefront (login redirects to `secureserver.net`). DNS is genuinely hosted
on GoDaddy's infrastructure (`ns65.domaincontrol.com` / `ns66.domaincontrol.com`).
GoDaddy relaxed its DNS/Domain Management API eligibility in April 2026 (previously
50+ domains required, now just 1+), which looked like it might unlock automated
DNS-01 renewal — but this reseller-registered domain was checked directly and
**confirmed not to have API key access** for DNS automation, so a plugin like
`certbot-dns-godaddy` isn't usable as-is.

**Future option**: transferring the domain to a direct GoDaddy account at the next
renewal window (~2026-10) may unlock API-based DNS-01 automation. Not decided — just
worth revisiting then.

### Where renewal actually happens: `gtc-portainer`

Host: `gtc-portainer` (45.86.163.71, SSH port 1986, user `root`) — reachable at
`https://gtc-portainer.greentech.consulting:9443/` (its own Portainer instance).
**This host is shared** — it also runs a PBX and other unrelated services, so any
work here should stay confined to `~/IOTstack`.

- certbot is installed via snap (`/snap/bin/certbot`)
- Renewal config: `/etc/letsencrypt/renewal/greentech.consulting.conf` —
  `authenticator = manual`, `pref_challs = dns-01`
- A `certbot.renew.timer` systemd timer runs twice daily but **always fails
  harmlessly**: `An authentication script must be provided with --manual-auth-hook
  when using the manual plugin non-interactively.` This is expected, not a bug — with
  no DNS API hook configured, only an interactive human-run renewal can succeed.

**Renewal command** (run interactively — someone needs to be present to add the DNS
record):

```bash
/snap/bin/certbot certonly --manual --preferred-challenges dns -d '*.greentech.consulting'
```

This pauses with a `_acme-challenge.greentech.consulting` TXT record value to add via
the GoDaddy/Domains Made Easy DNS panel. Verify propagation before continuing, e.g.:

```bash
curl -s "https://dns.google/resolve?name=_acme-challenge.greentech.consulting&type=TXT"
```

The resulting cert is valid for about 90 days.

### Syncing the renewed cert to `aspaDB-dev`

`aspaDB-dev` never runs certbot itself — it only ever serves whatever cert was last
synced in from `gtc-portainer`. As of `aspa-443.conf`/`aspa-678.conf` v1.1.0, the site
configs read the cert from a flat path rather than certbot's own `archive/liveN.pem`
generation-numbered layout (that bookkeeping was pure overhead on a host that never
runs certbot itself):

```text
/etc/letsencrypt/greentech.consulting/{fullchain.pem, privkey.pem, chain.pem}
```

(host-side: `services/nginx/letsencrypt/greentech.consulting/`, under the existing
`./services/nginx/letsencrypt:/etc/letsencrypt` volume mount — no compose change
needed.)

Run [`docker/iotstack/dev/nginx/scripts/sync-greentech-cert.sh`](../docker/iotstack/dev/nginx/scripts/sync-greentech-cert.sh)
from a workstation with SSH key access to both hosts. It streams the four PEM files
directly host-to-host over SSH — no intermediate copy on the machine running it, no
key material ever staged in this repo (not even `.gitignore`d — a git working tree is
too broad a blast radius for a private key) — sets `privkey.pem` to `600`, then
validates and reloads nginx.

**Full renewal cycle:**

1. Run the interactive `certbot certonly --manual ...` command on `gtc-portainer` (above)
2. Run `sync-greentech-cert.sh` from your workstation
3. Confirm:

   ```bash
   echo | openssl s_client -connect 192.168.100.32:443 -servername aspa.dev.greentech.consulting 2>/dev/null | openssl x509 -noout -dates
   ```

Cert issued 2026-08-19 is valid through **2026-11-17** — next renewal needed before then.

### Legacy `live/` / `archive/` directories

`services/nginx/letsencrypt/live/greentech.consulting/` and
`archive/greentech.consulting/` still hold certbot's old generation-numbered layout
(generations 1–9, the last dated 2025-09-06 — the one that had expired). Nothing
references them anymore post-flattening; they're safe to leave alone or clean up at
your discretion.

---

## Pre-Migration Checklist

- [x] Backup current `docker-compose.yml`
- [x] Backup `./services/nginx/` directory
- [x] Backup `./volumes/nginx/` directory (logs, HTML, cache, run)
- [x] Verify all `.conf` files in `./services/nginx/sites-enabled/` listed and reviewed
- [X] Confirm `./services/nginx/nginx.env` file exists and is readable
- [X] Verify Let's Encrypt certs in `./services/nginx/letsencrypt/` are present

---

## Migration Steps

### Step 1: Prepare

```bash
# Create persistent directories (logs, HTML)
mkdir -p ./volumes/nginx/{log,html}

# Verify files exist
ls -la ./services/nginx/nginx.conf
ls -la ./services/nginx/sites-enabled/
ls -la ./volumes/nginx/
```

### Step 2: Update Configuration Files

1. **Update `./services/nginx/nginx.conf`** — use content from section above
2. **Update `./services/nginx/sites-enabled/aspa-8081.conf`** — `listen 8081;` (matches `80:8081` mapping)
3. **Review `aspa-443.conf` / `aspa-678.conf`** — log paths already standard (`/var/log/nginx`); keep / update `include /etc/nginx/blockuseragents.rules;`

### Step 3: Update docker-compose.yml

Replace the entire `nginx:` service block (lines ~493–530) with the new configuration from the **New Configuration** section above.

### Step 4: Stop and Remove Current Container

```bash
# Stop the container
docker compose stop nginx

# Remove the Bitnami container (image stays for rollback)
docker compose rm -f nginx

# Verify it's gone
docker ps | grep nginx  # Should return nothing
```

### Step 5: Start New nginx:alpine Container

```bash
# Pull the alpine image (small, ~50MB)
docker pull nginx:alpine

# Start the new container
docker compose up -d nginx

# Wait 5 seconds for startup
sleep 5

# Verify it's healthy
docker ps --filter name=nginx
# Should show: STATUS "Up X seconds (healthy)"
```

### Step 6: Verify Health Check

```bash
# Test health check from host
curl -v http://localhost/

# Expected: should redirect to HTTPS (301 response)
# Or if behind a reverse proxy: 200 OK

# Check container logs
docker logs nginx

# Verify health status
docker inspect nginx --format='{{.State.Health.Status}}'
# Should return: "healthy"
```

### Step 7: Test Functionality

```bash
# Test each endpoint that nginx redirects
curl -L http://localhost/             # Should redirect to HTTPS
curl -L http://localhost/aspasales    # Should redirect to HTTPS aspasales

# Test logs are being written (now in standard path)
tail -f ./volumes/nginx/log/access.log

# Test app mount (if any app files in ./volumes/nginx/html)
curl http://localhost:8081/healthz    # or your app health endpoint
```

### Step 8: Cleanup (after 24–48 hours of stable operation)

Once you're confident the new container is stable:

```bash
# Remove old Bitnami image to free disk space (~140MB)
docker rmi bitnami/nginx:latest

# Verify disk reclaimed
docker images | grep nginx
# Should only show "nginx alpine"

# ./volumes/nginx is the persistent data location (html/log/cache/run) — keep it.
# Verify logs are being written
ls -lh ./volumes/nginx/log/
```

---

## Rollback Plan (if needed)

If anything goes wrong:

### Quick Rollback (within 24 hours)

```bash
# Stop the new container
docker compose stop nginx

# Remove it
docker compose rm -f nginx

# Restore docker-compose.yml from backup
git checkout docker-compose.yml
# OR manually restore the Bitnami nginx section

# Restore config files
git checkout ./services/nginx/
# OR manually restore from backup

# Start old Bitnami container
docker compose up -d nginx

# Verify
docker ps | grep nginx
```

### If Image Was Deleted

If you deleted the `bitnami/nginx:latest` image:

```bash
# Pull it again
docker pull bitnami/nginx:latest

# Restore docker-compose.yml to Bitnami version
# Restore ./services/nginx/ configs
# Start container
docker compose up -d nginx
```

---

## Troubleshooting

### Container exits immediately

```bash
docker logs nginx
# Look for config syntax errors

# Test nginx config directly
docker run --rm -v ./services/nginx/nginx.conf:/etc/nginx/nginx.conf:ro nginx:alpine nginx -t
```

### Restart loop: `mkdir() "/opt/bitnami/nginx/tmp/client_body" failed (2: No such file or directory)`

This means the file actually mounted at `/etc/nginx/nginx.conf` is still (fully or
partially) the **old Bitnami `nginx.conf`**, not the new one from this guide. Bitnami's
default config hardcodes `client_body_temp_path` (and usually `proxy_temp_path`,
`fastcgi_temp_path`, etc.) under `/opt/bitnami/nginx/tmp/...`. That directory tree
doesn't exist in the official `nginx:alpine` image — there is no `/opt/bitnami` at
all — so nginx tries to create it at startup and dies before it can bind any port,
producing exactly this restart loop. Swapping the image and the volume's *mount path*
(`/opt/bitnami/nginx/conf/nginx.conf` → `/etc/nginx/nginx.conf`) is not enough if the
*content* of the file on the host was never replaced.

```bash
# Confirm: look for leftover Bitnami temp-path directives in the deployed file
grep -n "temp_path\|bitnami" ./services/nginx/nginx.conf

# Fix: replace it with the file from docker/iotstack/dev/nginx/nginx.conf, which
# intentionally omits *_temp_path directives — nginx then uses its compiled-in
# defaults (/var/cache/nginx/client_temp, /proxy_temp, ...), which already exist
# and are writable in the official image, so nothing needs to be created at startup.
cp docker/iotstack/dev/nginx/nginx.conf ./services/nginx/nginx.conf
docker compose restart nginx
```

### Restart loop / `nginx -t` fails: duplicate `map` variable / `$blockedagent` already defined

Happens if `include /etc/nginx/blockuseragents.rules;` appears in more than one file
that ends up in the same `http` context — e.g. once in `nginx.conf` **and** again in
one or more `aspa-*.conf` site files. Since `nginx.conf` globs all of
`conf.d/*.conf` into its `http {}` block, every `include` of `blockuseragents.rules`
re-declares the same `map $http_user_agent $blockedagent {...}` block. Fix: include
it exactly once, in `nginx.conf`'s `http {}` block (as shown in this guide), and make
sure none of `aspa-8081.conf` / `aspa-443.conf` / `aspa-678.conf` include it too.

```bash
grep -rn "include.*blockuseragents" ./services/nginx/ ./services/nginx/sites-enabled/
# Should show exactly ONE match, in nginx.conf
```

### Health check failing (stays "unhealthy") — `docker inspect` shows "Health check exceeded timeout (10s)"

If `docker logs nginx` shows no errors, nginx is running, and a manual `curl -v
http://localhost/` from the host returns a fast 301 — but `docker inspect nginx
--format='{{json .State.Health}}'` still shows repeated `"Health check exceeded
timeout (10s)"` entries — the healthcheck command itself is hanging, not nginx.
This happens if the compose healthcheck still has `-L`:
`curl -f -L http://localhost:8081/`. `aspa-8081.conf`'s `/` location 301s to an
**external** absolute URL (`https://dev.greentech.consulting:678...`), so `-L` makes
curl leave the container and try to reach that public hostname on port 678 from
inside the container network — which can hang well past the 10s timeout even though
the initial local response was instant. Fix: drop `-L` — `curl -f` alone already
treats a 301 as healthy.

```bash
grep -n "healthcheck" -A3 docker-compose.yml
# If you see "-L" in the test line, remove it, then:
docker compose up -d nginx   # recreates the container with the new healthcheck
```

### Health check failing for other reasons

```bash
# Check container is listening on 8081
docker exec nginx netstat -tlnp | grep nginx
# Should show: tcp 0 0 0.0.0.0:8081 0.0.0.0:*

# Test health check manually
docker exec nginx curl -v http://localhost:8081/
# Should return 301 redirect (expected)

# Check logs
docker logs nginx | tail -20
```

### Logs not appearing in `./volumes/nginx/log/`

```bash
# Verify mount is active
docker inspect nginx --format='{{json .Mounts}}' | jq '.'
# Should show: "./volumes/nginx/log" mounted to "/var/log/nginx"

# Check permissions on host directory
ls -ld ./volumes/nginx/log
# Should be writable by root (or uid 101 if running as nginx user)

# Check inside container
docker exec nginx ls -la /var/log/nginx/
# Should show access.log, error.log, etc.
```

### Sites not loading (404 or connection refused)

```bash
# Verify sites config is mounted
docker exec nginx ls -la /etc/nginx/conf.d/
# Should show: aspa-8081.conf, aspa-443.conf, aspa-678.conf, blockuseragents.rules, etc.

# Test nginx config includes
docker exec nginx nginx -T
# Should show all includes resolved without errors

# Reload config without restart
docker exec nginx nginx -s reload
```

---

## Verification Checklist (Post-Migration)

Run these after successful startup:

```bash
# ✅ Container is healthy
docker ps --filter name=nginx
# STATUS should show "(healthy)"

# ✅ Port mappings correct
docker port nginx
# Should show: 8081/tcp, 678/tcp, 443/tcp

# ✅ Configuration is valid
docker exec nginx nginx -T 2>&1 | grep -i "successful"

# ✅ Health check works (no -L: the 301 target is an external host, not local)
docker exec nginx curl -f http://localhost:8081/

# ✅ Logs are being written to standard path
ls -lh ./volumes/nginx/log/access.log ./volumes/nginx/log/error.log
# Both should have recent timestamps

# ✅ HTTPS redirects work
curl -v http://localhost/ 2>&1 | grep "301 Moved Permanently"

# ✅ Let's Encrypt certs still mounted
docker exec nginx ls -la /etc/letsencrypt/

# ✅ HTML app mount works
docker exec nginx ls -la /app
```

---

## Summary of Benefits

| Benefit | Before | After |
|---------|--------|-------|
| **Deprecation risk** | ⚠️ Sunsetting Aug 28, 2025 | ✅ Actively maintained |
| **Config mount** | ❌ `/opt/bitnami/nginx/conf/` ignored | ✅ `/etc/nginx/nginx.conf` works |
| **Image size** | ~140MB | ~50MB |
| **Startup time** | ~5s | ~1s |
| **Health check** | ❌ Fails on 301 redirect | ✅ `curl -f` treats 301 as healthy (no `-L`) |
| **Customization** | Limited by Bitnami init | ✅ Full control |
| **Support** | Limited (vendor-specific) | ✅ Wide community |

---

## References

- [Official nginx Docker image](https://hub.docker.com/_/nginx)
- [nginx Configuration Documentation](https://nginx.org/en/docs/)
- [Alpine Linux (official base image)](https://www.alpinelinux.org/)

---

**Document Version**: v1.4.0  
**Last Updated**: 2026-08-19  
**Status**: Complete — live on dev  
**Author**: Manfred Koroschetz/AI
