#!/usr/bin/env bash

set -e

# Store the absolute path of the script's dir and switch to the top dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pushd "$SCRIPT_DIR/../" > /dev/null

# Read in the versions that will be distributed with this release
readarray elk_versions < ./ELK_VERSIONS
# These images are exported in the deployment after running pulls/builds
DOCKER_EXPORT_IMAGES="taskrabbit/elasticsearch-dump:v6.28.0\n"
DOCKER_EXPORT_IMAGES="${DOCKER_EXPORT_IMAGES}activecm-beaker/check_kibana:latest\n"

# Create elasticsearch & kibana images for each version defined in ELK_VERSIONS
for version in "${elk_versions[@]}"; do
  DOCKER_EXPORT_IMAGES="${DOCKER_EXPORT_IMAGES}activecm-beaker/elasticsearch:$version"
  DOCKER_EXPORT_IMAGES="${DOCKER_EXPORT_IMAGES}activecm-beaker/kibana:$version"
done 
DOCKER_EXPORT_IMAGES=$(echo -e "$DOCKER_EXPORT_IMAGES")
echo "###### EXPORTING THE FOLLOWING IMAGES: ######"
echo "$DOCKER_EXPORT_IMAGES"

# These services are always built unless --no-build is passed in
DOCKER_BUILD_SERVICES="elasticsearch kibana check_kibana"
# These services are always pulled unless --no-pull is passsed in
DOCKER_PULL_SERVICES="es-dump"

__help() {
  cat <<HEREDOC
This script generates an installer for BeaKer.
The resulting file is not intended to be installed directly by customers.
Usage:
  ${_NAME} [<arguments>]
Options:
  -h|--help     Show this help message.
  --use-cache   Builds Docker images using the local cache.
  --no-pull     Do not pull the latest base images from the container
                repository during the build process.
  --no-build    Do not build Docker images from scratch. This requires
                you to have the images already built on your system. (Implies --no-pull)
HEREDOC
}

NO_CACHE="--no-cache"

# Parse through command args
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      # Display help and exit
      __help
      exit 0
      ;;
    --use-cache)
      NO_CACHE=""
      ;;
    --no-build)
      NO_BUILD="--no-build"
      ;;
    --no-pull)
      NO_PULL="--no-pull"
      ;;
    *)
    ;;
  esac
  shift
done

# File/ Directory Names
DOCKER_IMAGE_OUT=images-latest
BEAKER_ARCHIVE=BeaKer

STAGE_DIR="$SCRIPT_DIR/stage/$BEAKER_ARCHIVE"

# Make sure we can use docker-compose
shell-lib/docker/check_docker.sh || {
	echo -e "\e[93mWARNING\e[0m: The generator did not detect a supported version of Docker."
	echo "         A supported version of Docker can be installed by running"
	echo "         the install_docker.sh script in the scripts directory."
}
shell-lib/docker/check_docker-compose.sh || {
	echo -e "\e[93mWARNING\e[0m: The generator did not detect a supported version of Docker-Compose."
	echo "         A supported version of Docker-Compose can be installed by running"
	echo "         the install_docker.sh script in the scripts directory."
}

export COMPOSE_FILE="docker-compose.yml"

# If the current user doesn't have docker permissions run with sudo
SUDO=
if [ ! -w "/var/run/docker.sock" ]; then
	SUDO="sudo"
fi

if [ ! "$NO_BUILD" ]; then
  if [ "$NO_PULL" ]; then
    echo "The latest images will *not* be pulled from DockerHub for this build."
    $SUDO docker-compose build $NO_CACHE $DOCKER_BUILD_SERVICES
  else
    # Ensure we have the latest images
    echo "The latest images will be pulled from DockerHub for this build."
    $SUDO docker-compose pull $DOCKER_PULL_SERVICES
    for version in "${elk_versions[@]}"; do
      v=$(echo $version|tr -d '\n')
      #export ELK_STACK_VERSION="$v"
      $SUDO -E docker-compose build --build-arg ELK_STACK_VERSION="$v" --pull $NO_CACHE $DOCKER_BUILD_SERVICES
    done
  fi
fi

echo "Exporting docker images... This may take a few minutes."
$SUDO docker save $DOCKER_EXPORT_IMAGES | gzip -c - > "$STAGE_DIR/${DOCKER_IMAGE_OUT}.tar.gz"

echo "Creating BeaKer installer archive..."
# This has the result of only including the files we want
# but putting them in a single directory so they extract nicely
tar -C "$STAGE_DIR/.."  --exclude '.*' -chf "$SCRIPT_DIR/${BEAKER_ARCHIVE}.tar" $BEAKER_ARCHIVE

popd > /dev/null
