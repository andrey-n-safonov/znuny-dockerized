# Znuny Docker Image

[![Docker Hub](https://img.shields.io/docker/v/andreynsafonov/znuny?sort=semver)](https://hub.docker.com/r/andreynsafonov/znuny)
[![Docker Pulls](https://img.shields.io/docker/pulls/andreynsafonov/znuny)](https://hub.docker.com/r/andreynsafonov/znuny)
[![Image Size](https://img.shields.io/docker/image-size/andreynsafonov/znuny/7.2.3)](https://hub.docker.com/r/andreynsafonov/znuny)

Lightweight Docker image for [Znuny](https://www.znuny.org/) - an open-source ticket management system.

## Features

- ✅ Based on Debian 12 Slim for minimal image size (~778MB)
- ✅ Support for PostgreSQL and MySQL databases
- ✅ All required Znuny dependencies included
- ✅ Apache2 with mod_perl2 for optimal performance
- ✅ Supervisor for process management
- ✅ Automatic database setup and initialization
- ✅ Production-ready with health checks
- ✅ Multi-stage build optimized for layer caching

## Quick Start

### With PostgreSQL (Recommended)

```bash
docker compose up -d
```

Znuny will be available at: <http://localhost:8080>

**Default credentials:**

- **Login:** `root@localhost`
- **Password:** `changeme`

### With MySQL

```bash
docker compose --profile mysql up -d znuny-mysql mysql
```

Znuny will be available at: <http://localhost:8081>

### Pull from Docker Hub

```bash
# Latest version
docker pull andreynsafonov/znuny:latest

# Specific version
docker pull andreynsafonov/znuny:7.2.3
```

## Configuration

### Environment Variables

| Variable | Description | Default |
| ---------- | ------------- | ---------- |
| `ZNUNY_DB_TYPE` | Database type: `postgresql` or `mysql` | `postgresql` |
| `ZNUNY_DB_HOST` | Database host | `postgres` |
| `ZNUNY_DB_PORT` | Database port | `5432` (PostgreSQL) / `3306` (MySQL) |
| `ZNUNY_DB_NAME` | Database name | `znuny` |
| `ZNUNY_DB_USER` | Database user | `znuny` |
| `ZNUNY_DB_PASSWORD` | Database password | `znuny_password` |
| `ZNUNY_AUTO_INSTALL` | Automatically install database schema | `true` |
| `ZNUNY_ROOT_PASSWORD` | Root user password | `changeme` |
| `ZNUNY_SYSTEM_ID` | System ID for ticket numbers (10-99) | `10` |
| `ZNUNY_FQDN` | Fully qualified domain name | `localhost` |
| `ZNUNY_ADMIN_EMAIL` | Admin email address | `admin@example.com` |
| `ZNUNY_ORGANIZATION` | Organization name | `Example Company` |

## Volumes

- `/opt/znuny` - Complete Znuny installation (application, data, configuration)

**Why Mount Entire Directory:**

Mounting `/opt/znuny` as a single volume ensures that:

- Installed extensions (OPM packages) persist across container restarts
- All configuration files remain intact
- Custom modules and themes are preserved
- Application updates can be managed consistently

**Configuration Management:**

- `/opt/znuny/Kernel/Config.pm` is automatically generated on first install from environment variables
- System settings (database, paths, security) persist in the volume
- Custom settings (SystemID, FQDN, Organization) are managed via SysConfig web interface and stored in database
- For custom code configurations, place `.pm` files in `/opt/znuny/Custom/Kernel/Config/Files/`

## Production Usage

### Production docker-compose.yml with PostgreSQL

```yaml
services:
  znuny:
    image: andreynsafonov/znuny:7.2.3
    ports:
      - "80:80"
    environment:
      - ZNUNY_DB_TYPE=postgresql
      - ZNUNY_DB_HOST=postgres
      - ZNUNY_DB_PORT=5432
      - ZNUNY_DB_NAME=znuny
      - ZNUNY_DB_USER=znuny
      - ZNUNY_DB_PASSWORD=changeme
      - ZNUNY_AUTO_INSTALL=true
      - ZNUNY_ROOT_PASSWORD=secure_password
      - ZNUNY_FQDN=support.example.com
    volumes:
      - znuny-data:/opt/znuny
    depends_on:
      postgres:
        condition: service_healthy
    restart: always

  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=znuny
      - POSTGRES_USER=znuny
      - POSTGRES_PASSWORD=changeme
    volumes:
      - postgres-data:/var/lib/postgresql/data
    restart: always
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U znuny"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  znuny-data:
  postgres-data:
```

### Production Example with MySQL

```yaml
services:
  znuny:
    image: andreynsafonov/znuny:7.2.3
    ports:
      - "80:80"
    environment:
      - ZNUNY_DB_TYPE=mysql
      - ZNUNY_DB_HOST=mysql
      - ZNUNY_DB_NAME=znuny
      - ZNUNY_DB_USER=znuny
      - ZNUNY_DB_PASSWORD=changeme
      - ZNUNY_AUTO_INSTALL=true
      - ZNUNY_ROOT_PASSWORD=secure_password
    volumes:
      - znuny-data:/opt/znuny
    depends_on:
      mysql:
        condition: service_healthy
    restart: always

  mysql:
    image: mysql:8.0
    environment:
      - MYSQL_DATABASE=znuny
      - MYSQL_USER=znuny
      - MYSQL_PASSWORD=changeme
      - MYSQL_ROOT_PASSWORD=root_changeme
    command: --default-authentication-plugin=mysql_native_password --max_allowed_packet=64M
    volumes:
      - mysql-data:/var/lib/mysql
    restart: always
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-proot_changeme"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  znuny-data:
  mysql-data:
```

## First Login

After starting the container, open your browser and navigate to <http://localhost> (or specified port).

**Default credentials:**

- **Login:** `root@localhost`
- **Password:** `changeme` (or value set in `ZNUNY_ROOT_PASSWORD`)

**IMPORTANT:** Change the password immediately after first login!

### Logs

```bash
# View Znuny logs
docker compose logs -f znuny-postgres

# View database logs
docker compose logs -f postgres

# View all logs
docker compose logs -f
```

## Architecture

The image includes:

- **Apache2** with mod_perl2 for web server
- **Supervisor** for process management
- **Znuny Daemon** for asynchronous operations
- **Cron** for scheduled tasks

### Process Management

Supervisor manages three main processes:

1. **Apache2** - Web server with mod_perl
2. **Cron** - Scheduled task execution
3. **Znuny Daemon** - Background job processing

## Troubleshooting

### Container Won't Start

```bash
# Check container logs
docker compose logs znuny-postgres

# Check database status
docker compose logs postgres

# Check autoinstall logs
docker compose logs znuny-postgres | grep AUTOINSTALL
```

## Available Tags

- `latest` - Latest stable version (currently 7.2.3)
- `7.2.3` - Specific version tag

## Performance

- Apache2 with mod_perl2 for fast Perl CGI execution
- Supervisor for reliable process management
- Health checks for container orchestration
- Optimized for production workloads

## Security

- Regular security updates from Debian base
- Minimal attack surface with slim base image
- No unnecessary packages installed
- Change default passwords before production use

## License

Znuny is distributed under the AGPL v3 license.

## Support

- [Official Znuny Website](https://www.znuny.org/)
- [Znuny Documentation](https://doc.znuny.org/)
- [Znuny GitHub Repository](https://github.com/znuny/Znuny)
- [Docker Hub Repository](https://hub.docker.com/r/andreynsafonov/znuny)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

Maintained by [andreynsafonov](https://hub.docker.com/u/andreynsafonov)

## Acknowledgments

- Znuny Team for the excellent ticketing system
- Debian Team for the stable base image
- Community contributors
