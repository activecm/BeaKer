#!/usr/bin/env bash

# Change dir to script dir
pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" > /dev/null

DOCKER_CONFIG="$HOME/.docker/config.json"
DOCKER_DAEMON="$HOME/.docker/daemon.json"
DOCKER_SOCKET="/var/run/docker.sock"

require_sudo () {
     if [ "$EUID" -eq 0 ]; then
        SUDO=""
        SUDO_E=""
        return 0
    fi

    # check if user can read at least one docker config file, use sudo if user cannot read them
    if [ -f "$DOCKER_CONFIG" ]; then 
        if [[ ! -r "$DOCKER_CONFIG" ]]; then 
            SUDO="sudo"
            SUDO_E="sudo -E"
        fi
        return 0
    elif [ -f "$DOCKER_DAEMON" ]; then
        if [[ ! -r "$DOCKER_DAEMON" ]]; then
            SUDO="sudo"
            SUDO_E="sudo -E"
        fi
        return 0
    elif [ -S "$DOCKER_SOCKET" ]; then
        if [[ ! -r "$DOCKER_SOCKET" ]]; then
            SUDO="sudo"
            SUDO_E="sudo -E"
        fi
        return 0
    fi

    echo 'Missing administrator privileges. Please run with an account with sudo priviliges.'
    exit 1
}

require_sudo

ENV_FILE=".env"
# Get config file locations, first from env variable and fall back to .env file
if [ ! -f "$ENV_FILE" ]; then
    ENV_FILE="/opt/BeaKer/.env"
fi

# Ensure that necessary config files exist
#CONFIG_FILE="${CONFIG_FILE:-$($SUDO grep BEAKER_CONFIG_FILE "$ENV_FILE" | cut -d= -f2)}"
#[ -f "$CONFIG_FILE" ] || { echo "BeaKer config file not found at '$CONFIG_FILE'"; exit 1; }

# Change back to original directory
popd > /dev/null

COMPOSE_FILE="$(dirname "$ENV_FILE")/docker-compose.yml"

# Ensure that the docker-compose file exists
[ -f "$COMPOSE_FILE" ] || { echo "Docker compose file not found at '$COMPOSE_FILE'"; exit 1; }

# Change dir to install dir. The install dir is where the env file resides.
# Specifically wait to do this until after "realpath" is called so the user 
# can specify a relative path to their current working directory for their logs.
pushd "$(dirname "$ENV_FILE")" > /dev/null

# TMPDIR is erased even if -E is passed to sudo. https://serverfault.com/questions/478741/sudo-does-not-preserve-tmpdir
# Need to explicitly pass tmpdir in if it exists.
if [ -n "$TMPDIR" ]; then
	$SUDO env "TMPDIR=$TMPDIR" docker compose -f "docker-compose.yml" "$@"
else
	$SUDO docker compose -f "docker-compose.yml" "$@"
fi

# Store the exit code from docker-compose to use later
result=$?

# Change back to original directory
popd > /dev/null

# Pass docker-compose's exit code through
exit $result
