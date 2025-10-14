#!/usr/bin/env bash
set -e

# Generates the BeaKer installer by creating a temporary folder in the current directory
# and copies files that must be in the installer into the temporary folder.
# Once all directories are placed in stage, it is compressed and the temporary folder is deleted

# get BeaKer version from git
VERSION=$(git describe --always --abbrev=0 --tags)
echo "Generating installer for BeaKer $VERSION..."

# change working directory to directory of this script
pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" > /dev/null

BASE_DIR="./beaker-$VERSION-installer"

# remove old staging folder if it exists
rm -rf "$BASE_DIR"

# create ansible subfolders
#SCRIPTS="$BASE_DIR/scripts"
ANSIBLE_FILES="$BASE_DIR/files"

mkdir "$BASE_DIR"
mkdir -p "$ANSIBLE_FILES"
#mkdir -p "$SCRIPTS"

# create subfolders (for files that installed BeaKer will contain)
INSTALL_OPT="$ANSIBLE_FILES"/opt
INSTALL_ETC="$ANSIBLE_FILES"/etc
INSTALL_VAR="$ANSIBLE_FILES"/var

mkdir "$INSTALL_OPT"
mkdir "$INSTALL_ETC"
mkdir "$INSTALL_VAR"

# copy files in base dir
cp ./install_beaker.yml "$BASE_DIR"
cp ./install_pre.yml "$BASE_DIR"
cp ./install_post.yml "$BASE_DIR"
cp ./install_beaker.sh "$BASE_DIR" # entrypoint

# copy files to helper script folder
cp ./ansible-installer.sh "$BASE_DIR"
cp ./helper.sh "$BASE_DIR"

# copy over configuration files to /files/etc
mkdir "$INSTALL_ETC"/elasticsearch
mkdir "$INSTALL_ETC"/kibana
cp -R ../elasticsearch/templates "$INSTALL_ETC"/elasticsearch
cp -R ../elasticsearch/elasticsearch.yml "$INSTALL_ETC"/elasticsearch
cp ../kibana/kibana_dashboards-*.ndjson "$INSTALL_ETC"/kibana
cp ../kibana/kibana.yml "$INSTALL_ETC"/kibana

# copy over install files to /opt
mkdir "$INSTALL_OPT"/elasticsearch
mkdir "$INSTALL_OPT"/kibana
cp ../beaker.sh "$INSTALL_OPT"
cp ../docker-compose.yml "$INSTALL_OPT"
cp ../LICENSE "$INSTALL_OPT"
cp ../elasticsearch/*.sh "$INSTALL_OPT"/elasticsearch
cp ../kibana/*.sh "$INSTALL_OPT"/kibana
cp ../.env.production "$INSTALL_OPT"/.env

# update version variables for files that need them
if [ "$(uname)" == "Darwin" ]; then
    sed -i'.bak' "s/REPLACE_ME/${VERSION}/g" "$BASE_DIR/install_beaker.yml" 
    sed -i'.bak' "s/REPLACE_ME/${VERSION}/g" "$BASE_DIR/install_beaker.sh"
    # sed -i'.bak' "s#ghcr.io/activecm/rita:latest#ghcr.io/activecm/rita:${VERSION}#g" "$INSTALL_OPT/docker-compose.yml"
    
    rm "$BASE_DIR/install_beaker.yml.bak"
    rm "$BASE_DIR/install_beaker.sh.bak"
    # rm "$INSTALL_OPT/docker-compose.yml.bak"
else 
    sed -i  "s/REPLACE_ME/${VERSION}/g" "$BASE_DIR/install_beaker.yml" 
    sed -i  "s/REPLACE_ME/${VERSION}/g" "$BASE_DIR/install_beaker.sh"
    # sed -i  "s#ghcr.io/activecm/rita:latest#ghcr.io/activecm/rita:${VERSION}#g" "$INSTALL_OPT/docker-compose.yml"
fi

# create installer archive
if [ "$(uname)" == "Darwin" ]; then
    tar --no-xattrs --disable-copyfile -czf "beaker-$VERSION.tar.gz" "$BASE_DIR"
else
    tar -czf "beaker-$VERSION.tar.gz" "$BASE_DIR"
fi
# tar -czf "beaker-$VERSION.tar.gz" "$BASE_DIR"

# delete staging folder
rm -rf "$BASE_DIR"

# switch back to original working directory
popd > /dev/null

echo "Finished generating installer."
