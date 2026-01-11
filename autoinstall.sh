#!/bin/bash
# Znuny Auto-Installation Script
# Automatically installs Znuny based on environment variables

set -e

ZNUNY_HOME="${ZNUNY_HOME:-/opt/znuny}"
CONFIG_FILE="${ZNUNY_HOME}/Kernel/Config/Config.pm"
CONFIG_LINK="${ZNUNY_HOME}/Kernel/Config.pm"
INSTALLED_FLAG="${ZNUNY_HOME}/var/.znuny_installed"

# Logging function - outputs to stdout for docker logs
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTOINSTALL] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTOINSTALL] ERROR: $1" >&2
}

# Check if already installed
if [ -f "$INSTALLED_FLAG" ]; then
    log "Znuny already installed. Skipping auto-installation."
    exit 0
fi

log "=== Starting Znuny Auto-Installation ==="

# Validate required environment variables
if [ -z "$ZNUNY_DB_HOST" ] || [ -z "$ZNUNY_DB_NAME" ] || [ -z "$ZNUNY_DB_USER" ] || [ -z "$ZNUNY_DB_PASSWORD" ]; then
    log_error "Missing required database environment variables"
    log_error "Required: ZNUNY_DB_HOST, ZNUNY_DB_NAME, ZNUNY_DB_USER, ZNUNY_DB_PASSWORD"
    exit 1
fi

# Set defaults
DB_TYPE="${ZNUNY_DB_TYPE:-mysql}"
DB_HOST="${ZNUNY_DB_HOST}"
DB_NAME="${ZNUNY_DB_NAME}"
DB_USER="${ZNUNY_DB_USER}"
DB_PASSWORD="${ZNUNY_DB_PASSWORD}"
ZNUNY_ROOT_PASSWORD="${ZNUNY_ROOT_PASSWORD:-rot}"
SYSTEM_ID="${ZNUNY_SYSTEM_ID:-10}"
FQDN="${ZNUNY_FQDN:-localhost}"
ADMIN_EMAIL="${ZNUNY_ADMIN_EMAIL:-root@localhost}"
ORGANIZATION="${ZNUNY_ORGANIZATION:-Example Company}"

if [ "$DB_TYPE" = "postgresql" ]; then
    DB_PORT="${ZNUNY_DB_PORT:-5432}"
    DB_DSN="DBI:Pg:dbname=${DB_NAME};host=${DB_HOST};port=${DB_PORT};"
    DB_TYPE_NAME="postgresql"
else
    DB_PORT="${ZNUNY_DB_PORT:-3306}"
    DB_DSN="DBI:mysql:database=${DB_NAME};host=${DB_HOST};port=${DB_PORT};"
    DB_TYPE_NAME="mysql"
fi

log "Configuration:"
log "  Database Type: $DB_TYPE"
log "  Database Host: $DB_HOST:$DB_PORT"
log "  Database Name: $DB_NAME"
log "  Database User: $DB_USER"
log "  FQDN: $FQDN"
log "  System ID: $SYSTEM_ID"

# Wait for database to be ready
log "Waiting for database to be ready..."

# Initial delay for Docker Swarm - services start in parallel without depends_on
log "Initial delay (20s) to allow database service to start..."
sleep 20

# Wait for database connection to be ready
# Note: In Docker Swarm overlay networks, DNS works but getent/nslookup may fail
# We test actual connection instead of DNS resolution
MAX_RETRIES=120
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ "$DB_TYPE" = "postgresql" ]; then
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c '\q' 2>/dev/null; then
            log "PostgreSQL is ready"
            break
        fi
    else
        if mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --password="$DB_PASSWORD" --silent 2>/dev/null; then
            log "MySQL is ready"
            break
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        log_error "Database is not ready after $MAX_RETRIES attempts ($(($MAX_RETRIES * 3 / 60)) minutes)"
        log_error "Check: 1) Database service is running, 2) Network connectivity, 3) Credentials"
        exit 1
    fi
    log "Database not ready yet, waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 3
done

# Check if database already has Znuny schema
log "Checking if database schema exists..."
if [ "$DB_TYPE" = "postgresql" ]; then
    TABLE_COUNT=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='users';" 2>/dev/null | xargs)
else
    TABLE_COUNT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='users';" 2>/dev/null)
fi

if [ "$TABLE_COUNT" != "0" ]; then
    log "Database schema already exists (users table found)"
    SCHEMA_EXISTS=true
else
    log "Database is empty, will install schema"
    SCHEMA_EXISTS=false
fi

# Create Kernel/Config.pm
log "Creating Kernel/Config.pm..."

cat > "$CONFIG_FILE" <<EOF
# OTRS config file (automatically created by auto-installer)
# VERSION:2.0
package Kernel::Config;

use strict;
use warnings;
use utf8;

sub Load {
    my \$Self = shift;

    # ---------------------------------------------------- #
    # database settings                                     #
    # ---------------------------------------------------- #

    # The database host
    \$Self->{DatabaseHost} = '$DB_HOST';

    # The database name
    \$Self->{Database} = '$DB_NAME';

    # The database user
    \$Self->{DatabaseUser} = '$DB_USER';

    # The password of database user
    \$Self->{DatabasePw} = '$DB_PASSWORD';

    # The database DSN
    \$Self->{DatabaseDSN} = '$DB_DSN';

    # ---------------------------------------------------- #
    # fs root directory
    # ---------------------------------------------------- #
    \$Self->{Home} = '$ZNUNY_HOME';

    # ---------------------------------------------------- #
    # system data                                           #
    # ---------------------------------------------------- #
    \$Self->{SystemID} = '$SYSTEM_ID';
    \$Self->{FQDN} = '$FQDN';
    \$Self->{AdminEmail} = '$ADMIN_EMAIL';
    \$Self->{Organization} = '$ORGANIZATION';

    # ---------------------------------------------------- #
    # SecureMode                                            #
    # ---------------------------------------------------- #
    \$Self->{SecureMode} = 1;

    # ---------------------------------------------------- #
    # default language
    # ---------------------------------------------------- #
    \$Self->{DefaultLanguage} = 'en';

    # ---------------------------------------------------- #
    # default charset
    # ---------------------------------------------------- #
    \$Self->{DefaultCharset} = 'utf-8';

    # ---------------------------------------------------- #
    # LogModule
    # ---------------------------------------------------- #
    \$Self->{LogModule} = 'Kernel::System::Log::File';

    # ---------------------------------------------------- #
    # SessionModule
    # ---------------------------------------------------- #
    \$Self->{'SessionModule'} = 'Kernel::System::AuthSession::DB';

    # ---------------------------------------------------- #
    # CustomerUser
    # ---------------------------------------------------- #
    \$Self->{CustomerUser} = {
        Name   => 'Database Backend',
        Module => 'Kernel::System::CustomerUser::DB',
        Params => {
            Table => 'customer_user',
            CaseSensitive => 0,
            SearchCaseSensitive => 0,
        },
        # customer unique id
        CustomerKey => 'login',
        # customer #
        CustomerID    => 'customer_id',
        CustomerValid => 'valid_id',
        CustomerUserListFields => [ 'first_name', 'last_name', 'email' ],
        CustomerUserSearchFields           => [ 'login', 'first_name', 'last_name', 'customer_id' ],
        CustomerUserPostMasterSearchFields => ['email'],
        CustomerUserNameFields             => [ 'title', 'first_name', 'last_name' ],
        CustomerUserEmailUniqCheck         => 1,
        CustomerCompanySupport => 1,
        CacheTTL => 60 * 60 * 24,
        Map => [
            [ 'UserTitle',      'Title or salutation', 'title',       1, 0, 'var', '', 0 ],
            [ 'UserFirstname',  'Firstname',           'first_name',  1, 1, 'var', '', 0 ],
            [ 'UserLastname',   'Lastname',            'last_name',   1, 1, 'var', '', 0 ],
            [ 'UserLogin',      'Username',            'login',       1, 1, 'var', '', 0 ],
            [ 'UserPassword',   'Password',            'pw',          0, 0, 'var', '', 0 ],
            [ 'UserEmail',      'Email',               'email',       1, 1, 'var', '', 0 ],
            [ 'UserCustomerID', 'CustomerID',          'customer_id', 0, 1, 'var', '', 0 ],
            [ 'UserPhone',      'Phone',               'phone',       1, 0, 'var', '', 0 ],
            [ 'UserMobile',     'Mobile',              'mobile',      1, 0, 'var', '', 0 ],
            [ 'UserStreet',     'Street',              'street',      1, 0, 'var', '', 0 ],
            [ 'UserZip',        'Zip',                 'zip',         1, 0, 'var', '', 0 ],
            [ 'UserCity',       'City',                'city',        1, 0, 'var', '', 0 ],
            [ 'UserCountry',    'Country',             'country',     1, 0, 'var', '', 0 ],
            [ 'UserComment',    'Comment',             'comments',    1, 0, 'var', '', 0 ],
            [ 'ValidID',        'Valid',               'valid_id',    0, 1, 'int', '', 0 ],
        ],
    };

    # ---------------------------------------------------- #
    # CheckMXRecord
    # ---------------------------------------------------- #
    \$Self->{CheckMXRecord} = 0;

    # ---------------------------------------------------- #
    # CheckEmailAddresses
    # ---------------------------------------------------- #
    \$Self->{CheckEmailAddresses} = 1;

    return 1;
}

# ---------------------------------------------------- #
# needed system stuff (don't edit this)               #
# ---------------------------------------------------- #

use Kernel::Config::Defaults; # import Translatable()
use parent qw(Kernel::Config::Defaults);

# -----------------------------------------------------#

1;
EOF

chown znuny:www-data "$CONFIG_FILE"
chmod 660 "$CONFIG_FILE"

# Create symlink from Kernel/Config.pm to Config/Config.pm
if [ ! -L "$CONFIG_LINK" ]; then
    ln -sf "$CONFIG_FILE" "$CONFIG_LINK"
    log "Created symlink: $CONFIG_LINK -> $CONFIG_FILE"
fi

log "Kernel/Config.pm created successfully"

# Install database schema if needed
if [ "$SCHEMA_EXISTS" = false ]; then
    log "Installing database schema..."
    
    if [ "$DB_TYPE" = "postgresql" ]; then
        log "Installing PostgreSQL schema..."
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema.postgresql.sql" 2>&1; then
            log "PostgreSQL schema installed successfully"
        else
            log_error "Failed to install PostgreSQL schema"
            exit 1
        fi
        
        log "Inserting initial data..."
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/initial_insert.postgresql.sql" 2>&1; then
            log "Initial data inserted successfully"
        else
            log_error "Failed to insert initial data"
            exit 1
        fi
        
        log "Applying schema post-processing (FK constraints)..."
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema-post.postgresql.sql" 2>&1; then
            log "Schema post-processing completed"
        else
            log_error "Failed to apply schema post-processing"
            exit 1
        fi
    else
        log "Installing MySQL schema..."
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema.mysql.sql" 2>&1; then
            log "MySQL schema installed successfully"
        else
            log_error "Failed to install MySQL schema"
            exit 1
        fi
        
        log "Inserting initial data..."
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/initial_insert.mysql.sql" 2>&1; then
            log "Initial data inserted successfully"
        else
            log_error "Failed to insert initial data"
            exit 1
        fi
        
        log "Applying schema post-processing (FK constraints)..."
        if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "${ZNUNY_HOME}/scripts/database/schema-post.mysql.sql" 2>&1; then
            log "Schema post-processing completed"
        else
            log_error "Failed to apply schema post-processing"
            exit 1
        fi
    fi
else
    log "Skipping schema installation (already exists)"
fi

# Set root@localhost password using SQL
log "Setting root@localhost password to: $ZNUNY_ROOT_PASSWORD..."

# Generate Znuny-compatible password hash using Perl
PASSWORD_HASH=$(su - znuny -c "perl -e 'use Digest::SHA; print Digest::SHA::sha256_hex(\"$ZNUNY_ROOT_PASSWORD\");'" 2>/dev/null)

if [ -z "$PASSWORD_HASH" ]; then
    log_error "Failed to generate password hash"
    PASSWORD_HASH="roK20XGbWEsSM"  # fallback to 'root' password
    log "Warning: Using default password hash (root)"
fi

log "Generated password hash: $PASSWORD_HASH"

# Update password in database
if [ "$DB_TYPE" = "postgresql" ]; then
    if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "UPDATE users SET pw = '$PASSWORD_HASH' WHERE login = 'root@localhost';" 2>&1; then
        log "root@localhost password updated successfully"
    else
        log "Warning: Failed to update root@localhost password"
    fi
else
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "UPDATE users SET pw = '$PASSWORD_HASH' WHERE login = 'root@localhost';" 2>&1; then
        log "root@localhost password updated successfully"
    else
        log "Warning: Failed to update root@localhost password"
    fi
fi

# Rebuild config
log "Rebuilding configuration..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Config::Rebuild" 2>&1; then
    log "Configuration rebuilt successfully"
else
    log "Warning: Failed to rebuild configuration"
fi

# Delete cache
log "Deleting cache..."
if su - znuny -c "${ZNUNY_HOME}/bin/otrs.Console.pl Maint::Cache::Delete" 2>&1; then
    log "Cache deleted successfully"
else
    log "Warning: Failed to delete cache"
fi

# Create installed flag
touch "$INSTALLED_FLAG"
chown znuny:www-data "$INSTALLED_FLAG"

log "=== Znuny Auto-Installation Completed Successfully ==="
log "You can now access Znuny at http://${FQDN}/"
log "Default credentials: root@localhost / ${ZNUNY_ROOT_PASSWORD}"
log ""

exit 0
