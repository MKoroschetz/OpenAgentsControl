# NGINX: Bitnami → nginx:alpine Migration Guide
**Project**: aspaDB-workbench | **Path**: docs/NGINX-migration.md
**Version**: v1.1.0 | **Last Updated**: 2026-08-19
**Author**: Manfred Koroschetz/AI
**License**: SPDX-License-Identifier: MIT

## Changelog
- v1.1.0 (2026-08-19): Aligned guide with the committed nginx:alpine config set
  (docker/iotstack/dev/nginx/, commit 23c5f85): volumes use /mnt/data/nginx
  (html/log/cache/run), not ./volumes/nginx; blockuseragents.rules stays in
  sites-enabled (included via /etc/nginx/conf.d/); site file renamed aspa-80.conf →
  aspa-8081.conf; added aspa-443.conf + aspa-678.conf coverage; bitnami baseline
  block corrected to match committed v1.0.0.
- v1.0.0 (2026-08-19): Initial migration guide - Bitnami nginx → official nginx:alpine

**Status**: Ready to execute  
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
| **Health check 301 redirects** | Container marked "unhealthy" despite working HTTPS | Fixed with `-L` flag (follows redirects) |
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
      # NGINX configuration (standard path - will now work!)
      - ./services/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      # Site configurations (standard path) - incl. blockuseragents.rules
      - ./services/nginx/sites-enabled:/etc/nginx/conf.d:ro
      # HTML pages for local sites
      - /mnt/data/nginx/html:/app
      # LOG configuration (keep existing path)
      - /mnt/data/nginx/log:/var/log/nginx
      # Cache and run directories for nginx
      - /mnt/data/nginx/cache:/var/cache/nginx
      - /mnt/data/nginx/run:/var/run/nginx
    healthcheck:
      test: ["CMD", "curl", "-f", "-L", "http://localhost:8081/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### Key Changes:

| Aspect | Bitnami | Alpine | Note |
|--------|---------|--------|------|
| Image | `bitnami/nginx:latest` | `nginx:alpine` | Official, no deprecation |
| Config path | `/opt/bitnami/nginx/conf/nginx.conf` | `/etc/nginx/nginx.conf` | Standard Linux path |
| Sites path | `/opt/bitnami/nginx/conf/server_blocks` | `/etc/nginx/conf.d` | Standard convention |
| Log path | `/opt/bitnami/nginx/logs` | `/var/log/nginx` | Standard location |
| Health check | `http://localhost/` | `http://localhost:8081/` | Must match container listen port |
| Init scripts | Bitnami-specific | None | Alpine = pure nginx binary |

---

## Configuration Files

### 1. Update `./services/nginx/nginx.conf`

Replace entire file:

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx/nginx.pid;

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
    
    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
```

**What changed:**
- All `/opt/bitnami/nginx/` paths → standard `/var/log/nginx`, `/var/run/nginx`
- Added `user nginx;` (alpine runs as this user)
- Removed Bitnami-specific temp path overrides
- Kept all your gzip, SSL, and tuning settings

### 2. Shared rules file (blockuseragents.rules)

`blockuseragents.rules` **stays in `./services/nginx/sites-enabled/`** — the whole
directory is mounted to `/etc/nginx/conf.d`, so all three site configs include it as
`/etc/nginx/conf.d/blockuseragents.rules`. No move needed.

### 3. Update `./services/nginx/sites-enabled/aspa-8081.conf`

The HTTP listener is committed as **`aspa-8081.conf`** (renamed from `aspa-80.conf`),
`listen` changed from **80** to **8081** to match the docker-compose.yml `80:8081` mapping:

```nginx
include /etc/nginx/conf.d/blockuseragents.rules;

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
        access_log /var/log/nginx/aspa-80-access.log;
        error_log /var/log/nginx/aspa-80-error.log warn;
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
- `include` path: `/etc/nginx/conf.d/blockuseragents.rules` (file stays in sites-enabled)

### 4. HTTPS site configs — `aspa-443.conf` and `aspa-678.conf`

The two HTTPS listeners are committed as **`aspa-443.conf`** (port 443) and
**`aspa-678.conf`** (port 678, main app proxy). Both were updated similarly:
- `include /etc/nginx/conf.d/blockuseragents.rules;` (unchanged — file stays in sites-enabled)
- Replace all `/opt/bitnami/nginx/logs/` → `/var/log/nginx/`
- Replace all `/opt/bitnami/nginx/conf/` → `/etc/nginx/conf.d/`
- `listen 443 ssl;` / `listen 678 ssl;` with `http2 on;` (unchanged)
- Let's Encrypt certs: `greentech.consulting` (fullchain/privkey/chain) + `options-ssl-nginx.conf` + `ssl-dhparams.pem`
- `aspa-678.conf` keeps the Vouch auth (`/vouch-validate`, `@error401`) and all app proxies
  (`aspa_APP`, `aspaFLOWS_API`, `aspaAUTH`, `aspa-login`, `aspaSTOCK`, `aspaSALES`, CRM, cams, kkr)

---

## Pre-Migration Checklist

- [ ] Backup current `docker-compose.yml`
- [ ] Backup `./services/nginx/` directory
- [ ] Backup `/mnt/data/nginx/` directory (logs, HTML, cache, run)
- [ ] Verify all `.conf` files in `./services/nginx/sites-enabled/` listed and reviewed
- [ ] Confirm `./services/nginx/nginx.env` file exists and is readable
- [ ] Verify Let's Encrypt certs in `./services/nginx/letsencrypt/` are present

---

## Migration Steps

### Step 1: Prepare

```bash
# Create persistent directories (logs, HTML, cache, run)
mkdir -p /mnt/data/nginx/{log,html,cache,run}

# Verify files exist
ls -la ./services/nginx/nginx.conf
ls -la ./services/nginx/sites-enabled/
ls -la /mnt/data/nginx/
```

### Step 2: Update Configuration Files

1. **Update `./services/nginx/nginx.conf`** — use content from section above
2. **Update `./services/nginx/sites-enabled/aspa-8081.conf`** — `listen 8081;` (matches `80:8081` mapping)
3. **Review `aspa-443.conf` / `aspa-678.conf`** — log paths already standard (`/var/log/nginx`); keep `include /etc/nginx/conf.d/blockuseragents.rules;`

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
tail -f /mnt/data/nginx/log/access.log

# Test app mount (if any app files in /mnt/data/nginx/html)
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

# /mnt/data/nginx is the persistent data location (html/log/cache/run) — keep it.
# Verify logs are being written
ls -lh /mnt/data/nginx/log/
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

### Health check failing (stays "unhealthy")

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

### Logs not appearing in `/mnt/data/nginx/log/`

```bash
# Verify mount is active
docker inspect nginx --format='{{json .Mounts}}' | jq '.'
# Should show: "/mnt/data/nginx/log" mounted to "/var/log/nginx"

# Check permissions on host directory
ls -ld /mnt/data/nginx/log
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

# ✅ Health check works
docker exec nginx curl -f -L http://localhost:8081/

# ✅ Logs are being written to standard path
ls -lh /mnt/data/nginx/log/access.log /mnt/data/nginx/log/error.log
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
| **Health check** | ❌ Fails on 301 redirect | ✅ Follows redirects |
| **Customization** | Limited by Bitnami init | ✅ Full control |
| **Support** | Limited (vendor-specific) | ✅ Wide community |

---

## References

- [Official nginx Docker image](https://hub.docker.com/_/nginx)
- [nginx Configuration Documentation](https://nginx.org/en/docs/)
- [Alpine Linux (official base image)](https://www.alpinelinux.org/)

---

**Document Version**: v1.1.0  
**Last Updated**: 2026-08-19  
**Status**: Ready to execute  
**Author**: Manfred Koroschetz/AI
