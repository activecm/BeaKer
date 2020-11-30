#!/usr/bin/env bash
#Performs installation of BeaKer software
#version = 1.0.0

#### Environment Set Up

# Set the working directory to the script directory
pushd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null

# Set exit on error
set -o errexit
set -o errtrace
set -o pipefail

# ERROR HANDLING
__err() {
    echo2 ""
    echo2 "Installation failed on line $1:$2."
    echo2 ""
	exit 1
}

__int() {
    echo2 ""
	echo2 "Installation cancelled."
    echo2 ""
	exit 1
}

trap '__err ${BASH_SOURCE##*/} $LINENO' ERR
trap '__int' INT

# Load the function library
. ./shell-lib/acmlib.sh
normalize_environment

BEAKER_CONFIG_DIR="${BEAKER_CONFIG_DIR:-/etc/BeaKer/}"

test_system () {
    status "Checking minimum requirements"
    require_supported_os
    require_free_space_MB "$HOME" "/var/lib" "/etc" "/usr" 5120
}

install_docker () {
    status "Installing Docker"
    $SUDO shell-lib/docker/install_docker.sh
    echo2 ''
    if $SUDO docker ps &>/dev/null ; then
		echo2 'Docker appears to be working, continuing.'
	else
        fail 'Docker does not appear to be working. Does the current user have sudo or docker privileges?'
	fi
}

ensure_env_file_exists () {
    $SUDO mkdir -p "$BEAKER_CONFIG_DIR"

    if [ ! -f "$BEAKER_CONFIG_DIR/env" ]; then
        status "Generating BeaKer configuration"
        echo "Please enter a password for the admin Elasticsearch user account."
        echo "Username: elastic"
        local elastic_password=""
        local pw_confirmation="foobar"
        while [ "$elastic_password" != "$pw_confirmation" ]; do
            read -es -p "Password: " elastic_password
            echo ""
            read -es -p "Password (Confirmation): " pw_confirmation
            echo ""
        done

        cat << EOF | $SUDO tee "$BEAKER_CONFIG_DIR/env" > /dev/null
###############################################################################
# By putting variables in this file, they will be made available to use in
# your Docker Compose files, including to pass to containers. This file must
# be named ".env" in order for Docker Compose to automatically load these
# variables into its working environment.
#
# https://docs.docker.com/compose/environment-variables/#the-env-file
###############################################################################

###############################################################################
# Changing the elastic password in the Kibana UI requires also changing it
# in this file.
#
# Once the password has been changed in both places, run "beaker down" followed
# by "beaker up -d" to restart the containers with the updated password.
###############################################################################

###############################################################################
# Elastic Search Settings
#
ELASTIC_PASSWORD=${elastic_password}
BEAKER_CONFIG_DIR=${BEAKER_CONFIG_DIR}
###############################################################################
EOF
    fi

    $SUDO chown root:docker "$BEAKER_CONFIG_DIR/env"
    $SUDO chmod 640 "$BEAKER_CONFIG_DIR/env"

    if ! can_write_or_create ".env"; then
        sudo ln -sf "$BEAKER_CONFIG_DIR/env" .env
    else
        ln -sf "$BEAKER_CONFIG_DIR/env" .env
    fi
}

require_aih_web_server_listening () {
	if nc -z -w 15 127.0.0.1 5601 >/dev/null 2>&1 ; then
		echo2 "Able to reach Kibana web server, good."
	else
		fail "Unable to reach Kibana web server"
	fi
}

ensure_certificates_exist () {

    local cert_files=(
        ca/ca.crt ca/ca.key
        Elasticsearch/Elasticsearch.crt Elasticsearch/Elasticsearch.key
        Kibana/Kibana.crt Kibana/Kibana.key
    )

    local certs_exist=true

    for cert_file in ${cert_files[@]}; do
        if [ ! -f "$BEAKER_CONFIG_DIR/certificates/$cert_file" ]; then
            certs_exist=false
            break
        fi
    done

    if [ "$certs_exist" != "true" ]; then
        $SUDO rm -rf "$BEAKER_CONFIG_DIR/certificates"
        $SUDO mkdir "$BEAKER_CONFIG_DIR/certificates"

        # Create Elasticsearch certificate and CA
        ./beaker run --rm elasticsearch /usr/share/elasticsearch/bin/elasticsearch-certutil cert ca --keep-ca-key \
            --name Elasticsearch --pem --days 10950 --out /usr/share/elasticsearch/config/certificates/certs.zip > /dev/null
        (cd /etc/BeaKer/certificates && $SUDO unzip certs.zip > /dev/null)
        $SUDO rm "$BEAKER_CONFIG_DIR/certificates/certs.zip"

        # Create Kibana certicate, reusing the CA
        ./beaker run --rm elasticsearch /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
            --ca-cert /usr/share/elasticsearch/config/certificates/ca/ca.crt \
            --ca-key /usr/share/elasticsearch/config/certificates/ca/ca.key \
            --name Kibana --pem --days 10950 --out /usr/share/elasticsearch/config/certificates/certs.zip > /dev/null
        (cd "$BEAKER_CONFIG_DIR/certificates" && $SUDO unzip certs.zip > /dev/null)
        $SUDO rm "$BEAKER_CONFIG_DIR/certificates/certs.zip"
    fi

}

install_beaker () {
    status "Installing Elasticsearch and Kibana"

    # Determine if the current user has permission to run docker
    local docker_sudo=""
    if [ ! -w "/var/run/docker.sock" ]; then
        docker_sudo="sudo"
    fi

    # Load the docker images
    gzip -d -c images-latest.tar.gz | $docker_sudo docker load >&2

    ensure_certificates_exist

    # Start Elasticsearch and Kibana with the new images
    ./beaker up -d --force-recreate >&2

    status "Waiting for initialization"
    sleep 15

    status "Loading Kibana dashboards"

    # Load password for kibana_import.sh.
    # Use docker_sudo since the env file ownership is root:docker.
    local es_pass=`$docker_sudo grep '^ELASTIC_PASSWORD' "$BEAKER_CONFIG_DIR/env" | sed -e 's/^[^=][^=]*=//'`

    local connection_attempts=0
    local data_uploaded="false"
    while [ $connection_attempts -lt 8 -a "$data_uploaded" != "true" ]; do
        if echo "$es_pass" | kibana/import_dashboards.sh "kibana/kibana_dashboards.ndjson" >&2 ; then
            echo2 "The installer successfully uploaded dashboards to Kibana."
            data_uploaded="true"
            break
        fi
        echo2 "The installer encountered an error while uploading dashboards to Kibana."
        echo2 "Retrying..."
        sleep 15
        connection_attempts=$((connection_attempts + 1))
    done
    if [ "$data_uploaded" != "true" ]; then
        fail "The installer failed to load the Kibana dashboards"
    fi
}


configure_ingest_account () {
    # Determine if the current user has permission to run docker/ read the env file
    local docker_sudo=""
    if [ ! -w "/var/run/docker.sock" ]; then
        docker_sudo="sudo"
    fi
    local es_pass=`$docker_sudo grep ELASTIC_PASSWORD "$BEAKER_CONFIG_DIR/env" | cut -d= -f2`

    # Don't configure the ingest account if it already exists
    if curl -s -u "elastic:$es_pass" -X GET -k "https://localhost:9200/_security/user/sysmon-ingest" | grep -q "\"username\":\"sysmon-ingest\""; then
        return
    fi

    status "Configuring Elasticsearch ingest account"

    echo "Please enter a password for the Elasticsearch Sysmon-ingest user account."
    echo "Use this account when connecting the BeaKer agent."
    echo "Username: sysmon-ingest"
    local ingest_password=""
    local pw_confirmation="foobar"
    while [ "$ingest_password" != "$pw_confirmation" ]; do
        read -es -p "Password: " ingest_password
        echo ""
        read -es -p "Password (Confirmation): " pw_confirmation
        echo ""
    done

    if ! curl -s -u "elastic:$es_pass" -X POST -k "https://localhost:9200/_security/role/sysmon-ingest" -H 'Content-Type: application/json' -d'
    {
        "run_as": [],
        "cluster": [ "monitor", "manage_index_templates" ],
        "indices": [
            {
                "names": [ "sysmon-*" ],
                "privileges": [ "create_doc", "create_index" ]
            }
        ]
    }
    ' > /dev/null ; then
        fail "Unable to create Elasticsearch ingest role."
    fi

    if ! curl -s -u "elastic:$es_pass" -X POST -k "https://localhost:9200/_security/user/sysmon-ingest" -H 'Content-Type: application/json' -d"
    {
        \"password\" : \"$ingest_password\",
        \"roles\" : [ \"sysmon-ingest\" ]
    }
    " > /dev/null ; then
        fail "Unable to create Elasticsearch ingest user."
    fi
}

move_files () {
    local installation_dir="/opt/$(basename "$(pwd)")"
    if [[ `pwd` -ef "$installation_dir" ]]; then
        return 0
    fi

    status "Moving files to $installation_dir"
    $SUDO rm -rf "$installation_dir"
    move_working_directory `dirname "$installation_dir"`
}

link_executables () {
    local executables=(
        "./beaker"
    )

    for executable in "${executables[@]}"; do
        local executable_name=`basename "$executable"`
        local link_name="/usr/local/bin/$executable_name"
        $SUDO rm -f "$link_name"
        $SUDO ln -sf `realpath "$executable"` "$link_name"
    done
}

main () {
    status "Checking for administrator priviledges"
    require_sudo

    test_system

    move_files
    link_executables

    status "Installing supporting software"
    ensure_common_tools_installed

    install_docker

    ensure_env_file_exists
    install_beaker
    configure_ingest_account

    status "Congratulations, BeaKer is installed"
}

main "$@"

#### Clean Up
# Change back to the initial working directory
# If the script was launched from the script directory, popd will fail since it moved
popd &> /dev/null || true
