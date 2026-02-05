#!/bin/bash

# Exit values
# 0 correct version installed
# 3 not installed
# 4 older than required minimum version
# 5 newer than required maximum version
# 6 conflicting installs, both compose @v1 and @v2 are installed

# verify that docker-compose is executable
if [ ! -x "$(command -v docker-compose)" ]; then
	exit 3
fi

# verify that the alias works if it exists (will succeed for v1 installs)
if ! docker-compose version > /dev/null 2>&1 ; then
	exit 3
fi

# verify that docker compose (v2) is callable
if ! docker compose version > /dev/null 2>&1 ; then
	exit 4
fi

# verify that docker compose & docker-compose aren't both installed
if docker-compose version | grep -q '^docker-compose .* [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' ; then
	exit 6
fi

MIN_VERSION_MAJOR=2
MIN_VERSION_MINOR=0
MAX_VERSION_MAJOR=2
MAX_VERSION_MINOR=17

pushd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null
source ../acmlib.sh
popd > /dev/null
require_executable_tmp_dir # docker-compose requires TMPDIR to be mounted without noexec

VERSION="$(docker compose version | sed 's/^.* v\?\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\).*$/\1 \2 \3/')"
VERSION_MAJOR="$(echo $VERSION | cut -d' ' -f1)"
VERSION_MINOR="$(echo $VERSION | cut -d' ' -f2)"

# check if major version is an integer
if [[ ! "$VERSION_MAJOR" =~ ^[0-9]+$ ]]; then
	exit 4
fi

if [ "$VERSION_MAJOR" -lt "$MIN_VERSION_MAJOR" ] ||
	[ "$VERSION_MAJOR" -eq "$MIN_VERSION_MAJOR" -a "$VERSION_MINOR" -lt "$MIN_VERSION_MINOR" ]; then
	exit 4
elif [ "$VERSION_MAJOR" -gt "$MAX_VERSION_MAJOR" ] ||
	[ "$VERSION_MAJOR" -eq "$MAX_VERSION_MAJOR" -a "$VERSION_MINOR" -gt "$MAX_VERSION_MINOR" ]; then
	exit 5
else
	exit 0
fi
