# Staging Deploy: Single REG.RU VPS

Target:

- Ubuntu 24.04 LTS
- FastAPI backend on port `8010`
- PostgreSQL 16 in Docker
- Static catalog card images at `/assets/cards/*.png`
- OpenRouter configured only through backend environment variables
- Nginx and HTTPS added after a domain is connected

Server IP used for temporary HTTP staging: `185.46.11.61`.

## A. Prepare Server

```bash
apt update && apt upgrade -y
apt install -y curl git ufw nginx certbot python3-certbot-nginx
curl -fsSL https://get.docker.com | sh
apt install -y docker-compose-plugin
```

Firewall baseline:

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8010/tcp
ufw enable
```

Port `8010` is temporary for direct staging checks. Close it after HTTPS reverse proxy is live if public direct access is no longer needed.

## B. Create App Directory

```bash
mkdir -p /opt/luma
cd /opt/luma
```

## C. Upload Project

Option 1: git clone.

```bash
git clone <your-repo-url> .
```

Option 2: rsync from your Mac.

```bash
rsync -av --delete \
  --exclude '.env' \
  --exclude 'backend/.env' \
  --exclude '.git' \
  --exclude '.data' \
  --exclude 'backend/.data' \
  --exclude 'DerivedData' \
  "/Users/dmitrijlitinskij/Downloads/DEMOLOGIST/золотое яблоко /beauty-concierge-production/" \
  root@185.46.11.61:/opt/luma/
```

Option 3: archive and scp.

```bash
tar --exclude='.env' --exclude='backend/.env' --exclude='.git' --exclude='.data' --exclude='backend/.data' -czf luma-staging.tar.gz .
scp luma-staging.tar.gz root@185.46.11.61:/opt/luma/
ssh root@185.46.11.61
cd /opt/luma
tar -xzf luma-staging.tar.gz
```

## D. Create Environment File

```bash
cp .env.staging.example .env
nano .env
```

## E. Required `.env` Values

Set:

```env
APP_ENV=staging
POSTGRES_DB=luma_staging
POSTGRES_USER=luma_user
POSTGRES_PASSWORD=<strong-password>
DATABASE_URL=postgresql://luma_user:<strong-password>@postgres:5432/luma_staging

ADVISOR_PROVIDER=openrouter
OPENROUTER_API_KEY=<rotated-openrouter-key>
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=openai/gpt-4o-mini
OPENROUTER_TIMEOUT_SECONDS=30
OPENROUTER_MAX_RETRIES=2
OPENROUTER_RESPONSE_FORMAT=json_schema

API_PUBLIC_BASE_URL=http://185.46.11.61:8010
PUBLIC_API_BASE_URL=http://185.46.11.61:8010
ALLOW_DEV_AUTH=false
```

Do not commit `.env`. The previous local OpenRouter key must be treated as exposed and rotated before staging.

## F. Start Staging

```bash
docker compose -f docker-compose.staging.yml up -d --build
```

## G. Check From Server

```bash
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs -f backend

curl http://127.0.0.1:8010/health
curl http://127.0.0.1:8010/ready
curl http://127.0.0.1:8010/v1/catalog/products
curl -I http://127.0.0.1:8010/assets/cards/001_FD-BUD-01.png
```

Or run the bundled check:

```bash
BASE_URL=http://127.0.0.1:8010 ./scripts/deploy_check.sh
```

## H. External Check

From your Mac:

```bash
curl http://185.46.11.61:8010/health
curl http://185.46.11.61:8010/ready
curl -I http://185.46.11.61:8010/assets/cards/001_FD-BUD-01.png
BASE_URL=http://185.46.11.61:8010 ./scripts/deploy_check.sh
```

Expected sample image URL:

```text
http://185.46.11.61:8010/assets/cards/001_FD-BUD-01.png
```

## I. Nginx Reverse Proxy For Future Domain

Create:

```bash
nano /etc/nginx/sites-available/luma-api-staging
```

Config:

```nginx
server {
    listen 80;
    server_name api-staging.your-domain.ru;

    client_max_body_size 15M;

    location / {
        proxy_pass http://127.0.0.1:8010;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable:

```bash
ln -s /etc/nginx/sites-available/luma-api-staging /etc/nginx/sites-enabled/luma-api-staging
nginx -t
systemctl reload nginx
```

## J. HTTPS Through Certbot

After DNS points `api-staging.your-domain.ru` to `185.46.11.61`:

```bash
certbot --nginx -d api-staging.your-domain.ru
```

Then verify:

```bash
curl https://api-staging.your-domain.ru/health
curl -I https://api-staging.your-domain.ru/assets/cards/001_FD-BUD-01.png
```

## K. iOS Release URL After HTTPS

Set iOS Release `API_BASE_URL` to:

```text
https://api-staging.your-domain.ru
```

Release/TestFlight must not use localhost, loopback, placeholder domains, empty URLs, or plain HTTP.

## L. Backup

From `/opt/luma`:

```bash
./scripts/backup_postgres.sh
```

Backups are written to:

```text
./backups/luma_staging_YYYYMMDD_HHMMSS.sql.gz
```

Restore example:

```bash
gunzip -c backups/luma_staging_YYYYMMDD_HHMMSS.sql.gz | docker compose -f docker-compose.staging.yml exec -T postgres psql -U luma_user -d luma_staging
```

## M. Update Deploy

Git flow:

```bash
cd /opt/luma
git pull
docker compose -f docker-compose.staging.yml up -d --build
BASE_URL=http://127.0.0.1:8010 ./scripts/deploy_check.sh
```

Rsync flow:

```bash
rsync -av --delete --exclude '.env' --exclude 'backend/.env' --exclude '.data' --exclude 'backend/.data' ./ root@185.46.11.61:/opt/luma/
ssh root@185.46.11.61
cd /opt/luma
docker compose -f docker-compose.staging.yml up -d --build
BASE_URL=http://127.0.0.1:8010 ./scripts/deploy_check.sh
```

## Useful Operations

```bash
docker compose -f docker-compose.staging.yml logs -f backend
docker compose -f docker-compose.staging.yml logs -f postgres
docker compose -f docker-compose.staging.yml restart backend
docker compose -f docker-compose.staging.yml down
```

Do not run `down -v` unless you intentionally want to delete PostgreSQL data.
