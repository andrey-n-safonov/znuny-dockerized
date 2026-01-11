#!/bin/bash
set -e

ZNUNY_HOME="${ZNUNY_HOME:-/opt/znuny}"
CONFIG_DIR="${ZNUNY_HOME}/Kernel/Config"
CONFIG_FILE="${CONFIG_DIR}/Config.pm"
CONFIG_ORIG="${ZNUNY_HOME}/Kernel/Config.pm"

# Set permissions (ignore errors with /dev/stdout symlinks)
echo "Setting permissions..."
${ZNUNY_HOME}/bin/otrs.SetPermissions.pl 2>&1 | grep -v "is encountered a second time" || true

# Create symlink if Config.pm is not a symlink
if [ ! -L "$CONFIG_ORIG" ] && [ -f "$CONFIG_ORIG" ]; then
    echo "Moving Config.pm to persistent storage and creating symlink..."
    mv "$CONFIG_ORIG" "$CONFIG_FILE"
    ln -sf "$CONFIG_FILE" "$CONFIG_ORIG"
elif [ ! -e "$CONFIG_ORIG" ]; then
    echo "Creating symlink for Config.pm..."
    ln -sf "$CONFIG_FILE" "$CONFIG_ORIG"
fi

# Create Config.pm if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config.pm not found, creating from environment variables..."
    SYSTEM_ID="${ZNUNY_SYSTEM_ID:-10}"
    FQDN="${ZNUNY_FQDN:-localhost}"
    ORGANIZATION="${ZNUNY_ORGANIZATION:-Example Company}"
    
    cat > "$CONFIG_FILE" << EOF
# OTRS config file (automatically generated)
package Kernel::Config;

sub Load {
    my \$Self = shift;
    
    \$Self->{SecureMode} = 1;
    \$Self->{SystemID} = '${SYSTEM_ID}';
    \$Self->{FQDN} = '${FQDN}';
    \$Self->{Organization} = '${ORGANIZATION}';
    \$Self->{DefaultLanguage} = 'en';
    \$Self->{DefaultCharset} = 'utf-8';
    \$Self->{LogModule} = 'Kernel::System::Log::File';
    \$Self->{'SessionModule'} = 'Kernel::System::AuthSession::DB';
    
    return;
}

1;
EOF
    chown znuny:www-data "$CONFIG_FILE"
    chmod 660 "$CONFIG_FILE"
    echo "Config.pm created in persistent storage"
fi

# Run auto-installation if enabled
if [ "${ZNUNY_AUTO_INSTALL:-true}" = "true" ] && [ -n "$ZNUNY_DB_HOST" ]; then
    echo "Running Znuny auto-installation..."
    /usr/local/bin/autoinstall.sh
fi

# Setup cron jobs for znuny user
echo "Setting up Znuny cron jobs..."
su - znuny -c "${ZNUNY_HOME}/bin/Cron.sh start" || echo "Warning: Could not setup cron jobs"

# Execute the command
exec "$@"
