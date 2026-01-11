#!/bin/bash
set -e

# Redirect all output to stderr to avoid buffering issues in Docker logs
exec 2>&1

ZNUNY_HOME="${ZNUNY_HOME:-/opt/znuny}"

# Set permissions (ignore errors with /dev/stdout symlinks)
echo "Setting permissions..."
chown -R znuny:www-data ${ZNUNY_HOME}
chmod -R g+w ${ZNUNY_HOME}
${ZNUNY_HOME}/bin/otrs.SetPermissions.pl 2>&1 | grep -v "is encountered a second time" || true

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
