#!/usr/bin/env bash
#Performs installation of BeaKer software
#version = 1.0.1

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

# Constants for output color formatting
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


# Load the function library
. ./shell-lib/acmlib.sh
normalize_environment

BEAKER_CONFIG_DIR="${BEAKER_CONFIG_DIR:-/etc/BeaKer/}"
UPGRADE_INSTALL=false
CURRENT_ELASTIC_VERSION=""
INSTALL_ELASTIC_VERSION=""

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

    # Determine if the current user has permission to run docker
    local docker_sudo=""
    if [ ! -w "/var/run/docker.sock" ]; then
        docker_sudo="sudo"
    fi

    CURRENT_ELASTIC_VERSION=$({ "$docker_sudo" grep "^ELK_STACK_VERSION" "$BEAKER_CONFIG_DIR/env" || true; })
    CURRENT_ELASTIC_VERSION=${CURRENT_ELASTIC_VERSION##*=}

    local savedObjectsEncryptionKey=$(openssl rand -hex 16)
    local reportingEncryptionKey=$(openssl rand -hex 16)
    local securityEncryptionKey=$(openssl rand -hex 16)

    if [ "$acm_no_interactive" = 'yes' ] && [ ! -f "$BEAKER_CONFIG_DIR/env" ]; then
        echo2 "We are in non-interactive mode but there is no $BEAKER_CONFIG_DIR/env file, exiting."
        exit 1
    elif [ ! -f "$BEAKER_CONFIG_DIR/env" ]; then
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
        elastic_version=$( tail -n 1 ELK_VERSIONS )
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

###############################################################################
# Kibana Settings
#
KIBANA_SERVICE_TOKEN=KIBANA_TOKEN_PLACEHOLDER
SAVED_OBJECTS_ENCRYPTION_KEY=${savedObjectsEncryptionKey}
REPORTING_ENCRYPTION_KEY=${reportingEncryptionKey}
SECURITY_ENCRYPTION_KEY=${securityEncryptionKey}
###############################################################################

###############################################################################
# ELK Stack Settings
ELK_STACK_VERSION=${elastic_version}
###############################################################################

EOF
    else
        UPGRADE_INSTALL=true
        
        if ! $("$docker_sudo" grep -q "^KIBANA_SERVICE_TOKEN" "$BEAKER_CONFIG_DIR/env" ); then
            cat << EOF | $SUDO tee -a "$BEAKER_CONFIG_DIR/env" > /dev/null


###############################################################################
# Kibana Settings
#
KIBANA_SERVICE_TOKEN=KIBANA_TOKEN_PLACEHOLDER
SAVED_OBJECTS_ENCRYPTION_KEY=${savedObjectsEncryptionKey}
REPORTING_ENCRYPTION_KEY=${reportingEncryptionKey}
SECURITY_ENCRYPTION_KEY=${securityEncryptionKey}
###############################################################################

###############################################################################
# ELK Stack Settings
ELK_STACK_VERSION=7.0.0
###############################################################################
EOF
        fi
    fi


    $SUDO chown root:docker "$BEAKER_CONFIG_DIR/env"
    $SUDO chmod 640 "$BEAKER_CONFIG_DIR/env"

    if ! can_write_or_create ".env"; then
        sudo ln -sf "$BEAKER_CONFIG_DIR/env" .env
    else
        ln -sf "$BEAKER_CONFIG_DIR/env" .env
    fi
}

ensure_snapshot_repo_exists() {
    # Create snapshot folder if it doesn't exist
    if [ ! -d "/opt/BeaKer/snapshots" ]; then 
        $SUDO mkdir "/opt/BeaKer/snapshots"
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

        # Create CA
        ./beaker run --rm --user root elasticsearch /usr/share/elasticsearch/bin/elasticsearch-certutil ca --pem \
        --days 10950 --out /usr/share/elasticsearch/config/certificates/ca.zip > /dev/null
        (cd /etc/BeaKer/certificates && $SUDO unzip ca.zip > /dev/null)
        $SUDO rm "$BEAKER_CONFIG_DIR/certificates/ca.zip"

        # Create Elasticsearch certificate using CA
        ./beaker run --rm --user root elasticsearch /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
            --ca-cert /usr/share/elasticsearch/config/certificates/ca/ca.crt \
            --ca-key /usr/share/elasticsearch/config/certificates/ca/ca.key \
            --name Elasticsearch --pem --days 10950 --out /usr/share/elasticsearch/config/certificates/certs.zip > /dev/null
        (cd /etc/BeaKer/certificates && $SUDO unzip certs.zip > /dev/null)
        $SUDO rm "$BEAKER_CONFIG_DIR/certificates/certs.zip"
        
        # Create Kibana certicate, reusing the CA
        ./beaker run --rm --user root elasticsearch /usr/share/elasticsearch/bin/elasticsearch-certutil cert \
            --ca-cert /usr/share/elasticsearch/config/certificates/ca/ca.crt \
            --ca-key /usr/share/elasticsearch/config/certificates/ca/ca.key \
            --name Kibana --pem --days 10950 --out /usr/share/elasticsearch/config/certificates/certs.zip > /dev/null
        (cd "$BEAKER_CONFIG_DIR/certificates" && $SUDO unzip certs.zip > /dev/null)
        $SUDO rm "$BEAKER_CONFIG_DIR/certificates/certs.zip"

	$SUDO chmod 755 /etc/BeaKer/ /etc/BeaKer/certificates/ /etc/BeaKer/certificates/ca/ \
		/etc/BeaKer/certificates/Elasticsearch/ /etc/BeaKer/certificates/Kibana/
	$SUDO chmod 644 /etc/BeaKer/certificates/Kibana/Kibana.* /etc/BeaKer/certificates/Elasticsearch/Elasticsearch.* \
		/etc/BeaKer/certificates/ca/ca.*
    fi

}

require_elasticsearch_api_up() {
    local es_pass="$1"

    local connection_attempts=0
    local elastic_api_up="false"
    while [ $connection_attempts -lt 8 -a "$elastic_api_up" != "true" ]; do
        if curl --fail -s -u "elastic:$es_pass" -XGET -k "https://localhost:9200" > /dev/null ; then
            echo2 "The Elasticsearch API is up and running."
            elastic_api_up="true"
            break
        fi
        echo2 "Waiting for Elasticsearch API to start..."
        sleep 15
        connection_attempts=$((connection_attempts + 1))
    done
    if [ "$elastic_api_up" != "true" ]; then
        fail "The installer failed to authenticate to the Elasticsearch API"
    fi
}

require_kibana_available() {
    local es_pass="$1"

    local minutes_to_wait=15
    local attempts=$(( ( $minutes_to_wait * 60 ) / 15 ))

    local connection_attempts=0
    local kibana_available="false"
    while [ $connection_attempts -lt $attempts -a "$kibana_available" != "true" ]; do
        if curl --fail -s -u "elastic:$es_pass" -XGET -k "https://localhost:5601/api/status" | python3 ./kibana/check_kibana.py ; then
            echo2 "Kibana is up and running."
            kibana_available="true"
            break
        fi
        echo2 "Waiting for Kibana to finish migrations and become available..."
        sleep 15
        connection_attempts=$((connection_attempts + 1))
    done
    if [ "$kibana_available" != "true" ]; then
        fail "Kibana failed to upgrade/start within $minutes_to_wait minutes"
    fi
}

create_snapshot() {
    local es_pass="$1"
    require_elasticsearch_api_up "$es_pass"
    local repository_ok=true

    # Check if snapshot repository already exists
    if ! curl --fail -s u "elastic:$es_pass" -k "https://localhost:9200/_snapshot/beaker" > /dev/null ; then
        # Create snapshot repository if it doesn't exist
        if ! curl --fail -s -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_snapshot/beaker" -H 'Content-Type: application/json' -d'{
        "type": "fs",
        "settings": {
            "location": "/usr/share/elasticsearch/snapshots"
        }
        }
        ' > /dev/null ; then
            fail "Failed to create snapshot repository"
            repository_ok=false
        fi
    fi

    if "$repository_ok" ; then 
        local output=$(curl -s -u "elastic:$es_pass" -XGET -k "https://localhost:9200/_snapshot/beaker/beaker_snapshot*")
        snapshot_iteration=1
        existing_snapshot=$(echo "$output" | { grep -o '"snapshot":"beaker_snapshot-[[:digit:]]*.[[:digit:]]*.[[:digit:]]*-[[:digit:]]*' || true; })
        if [ -n "$existing_snapshot" ]; then
            iteration=${existing_snapshot##*-}
            snapshot_iteration=$(( $iteration + 1 ))
        fi
        if ! curl --fail -s -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_snapshot/beaker/%3Cbeaker_snapshot-%7Bnow%2Fd%7D-$snapshot_iteration%3E?wait_for_completion=true" > /dev/null ; then
            printf "${YELLOW}[!!!] Couldn't create snapshot... If you continue the installation without a snapshot and are unable to recover your data, you will NOT be able to downgrade.${NC}\n"
            echo "Would you like to stop the installation and manually create a snapshot? (Y/N, recommended: Y)"
            if askYN ; then
                echo "The instructions for manually creating a snapshot are listed here: https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshots-take-snapshot.html#manually-create-snapshot"
                echo "The snapshot repository for BeaKer is a 'Shared file system' repository named 'beaker', located at /usr/share/elasticsearch/snapshots within the Elasticsearch container."
                echo "Stopping installation due to failure to create snapshot"
                exit
            else
                printf "${YELLOW}[!!!] Continuing the installation WITHOUT a snapshot. PROCEED AT YOUR OWN RISK [!!!]${NC}\n"
            fi
        else
            printf "${GREEN}\u2714${NC} Successfully created snapshot\n"
        fi
    fi
}

create_service_account_token() {
    local es_pass="$1"
    require_elasticsearch_api_up "$es_pass"

    # Determine if the current user has permission to run docker
    local docker_sudo=""
    if [ ! -w "/var/run/docker.sock" ]; then
        docker_sudo="sudo -E"
    fi

    # Use docker_sudo since the env file ownership is root:docker.
    local service_token=`$docker_sudo grep '^KIBANA_SERVICE_TOKEN' "$BEAKER_CONFIG_DIR/env" | sed -e 's/^[^=][^=]*=//'`
    local token_already_valid=false
    if [ -n "$service_token" -a "$service_token" != "KIBANA_TOKEN_PLACEHOLDER" ]; then
        # Token was already generated, could be upgrade install or overwrite install
        # Check to see if token is valid
        if curl --fail -s -k -H "Authorization: Bearer $service_token" "https://localhost:9200/_security/_authenticate" > /dev/null ; then
            # Token is valid, don't modify anything
            token_already_valid=true
            echo "Kibana service account token already exists and is valid, skipping creation"
        fi
    fi

    if ! "$token_already_valid"; then 
        # Verify that the token does exist for the elastic/kibana service account
        if ! curl --fail -s -u "elastic:$es_pass" -X GET -k "https://localhost:9200/_security/service/elastic/kibana/credential" | grep -q "\"kibana-beaker\""; then
            echo "Token does not already exist, creating..."
        else
            echo "Token already exists, recreating..."
            if ! curl --fail -s -u "elastic:$es_pass" -X DELETE -k "https://localhost:9200/_security/service/elastic/kibana/credential/token/kibana-beaker" > /dev/null; then
                fail "Failed to remove service account token" 
            fi
        fi

        local output=$(curl -s -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_security/service/elastic/kibana/credential/token/kibana-beaker")
        has_token=$(echo "$output" | { grep -o "\"value\":\".*\"" || true; })
        if [ -n "$has_token" ]; then
            local new_token=${has_token##*\":} # grab the portion of the string that comes after "value":
            new_token=${new_token//\"/} # remove all double quotes
            if [ -n "$new_token" ]; then
                if [ -n "$service_token" ]; then
                    $docker_sudo sed -i "s/KIBANA_SERVICE_TOKEN=.*/KIBANA_SERVICE_TOKEN=$new_token/g" "$BEAKER_CONFIG_DIR/env"
                else
                    echo "KIBANA_SERVICE_TOKEN=$new_token" | $docker_sudo tee -a "$BEAKER_CONFIG_DIR/env" > /dev/null
                fi
                printf "${GREEN}\u2714${NC} Successfully created Kibana service account token\n"
                echo "Restarting BeaKer..."
                ./beaker down && ./beaker up -d --force-recreate >&2
                status "Waiting for initialization"
                sleep 15
            else
                fail "Failed to create Kibana service account token, token parsing failed"
            fi
        else
            fail "Failed to create Kibana service account token"
        fi
    fi

}

create_index_lifecycle_policy() {
    # Loads index lifecycle policy if it doesn't already exist
    local es_pass="$1"

    require_elasticsearch_api_up "$es_pass"

    INDEX_LIFECYCLE_POLICY="elasticsearch/templates/winlogbeat-ilm-policy.json"

    if [ ! -r "$INDEX_LIFECYCLE_POLICY" ]; then
        fail "Couldn't find required index lifecycle policy file: $INDEX_LIFECYCLE_POLICY"
    fi

    # Check if policy exists
    if ! curl --fail -s -u "elastic:$es_pass" -XGET -k "https://localhost:9200/_ilm/policy/beaker" > /dev/null; then
        # Load policy if it doesn't exist
        if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_ilm/policy/beaker" -H 'Content-Type: application/json' --data-binary "@$INDEX_LIFECYCLE_POLICY" > /dev/null; then
            fail "Couldn't load index lifecycle policy" 
        fi
        printf "  ${GREEN}\u2714${NC} Loaded winlogbeat index lifecycle policy\n"
    else
        echo "Index lifecycle policy already exists, skipping..."
    fi

}

create_data_stream() {
    # Loads index template
    # Creates data stream using new index template
    local es_pass="$1"
    local version="$2"

    require_elasticsearch_api_up "$es_pass"

    INDEX_TEMPLATE="elasticsearch/templates/winlogbeat-$version.template.json"
    if [ ! -r "$INDEX_TEMPLATE" ]; then
        fail "Couldn't find required index template file: $INDEX_TEMPLATE"
    fi

     # Load index template
    if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_index_template/winlogbeat-$version" -H 'Content-Type: application/json' --data-binary "@$INDEX_TEMPLATE" > /dev/null; then
        fail "Couldn't load winlogbeat-$version index template" 
    else 
        printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version index template\n"
        # Check if data stream exists, as this route doesn't accept overwriting with PUT
        if curl -s -u "elastic:$es_pass" -XGET -k "https://localhost:9200/_data_stream/winlogbeat-$version" | grep -q "index_not_found_exception"; then
            # Load data stream since it doesn't already exist
            echo "Data stream doesn't exist, creating..."
            if ! curl --fail -s -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_data_stream/winlogbeat-$version" > /dev/null; then
                fail "Couldn't load winlogbeat-$version data stream" 
            fi
            printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version data stream\n"
        fi
    fi

}

create_ingest_pipelines() {
    # Creates winlogbeat ingest pipelines by loading the default templates
    # In order for data to properly be ingested into Kibana, the following must exist:
    # Index template with matching winlogbeat version
    # Data stream with matching index name
    # Winlogbeat ingest pipelines 
    
    local es_pass="$1"
    local version="$2"

    POWERSHELL_PIPELINE="elasticsearch/templates/winlogbeat-$version-powershell.json"
    POWERSHELL_OPERATIONAL_PIPELINE="elasticsearch/templates/winlogbeat-$version-powershell_operational.json"
    ROUTING_PIPELINE="elasticsearch/templates/winlogbeat-$version-routing.json"
    SECURITY_PIPELINE="elasticsearch/templates/winlogbeat-$version-security.json"
    SYSMON_PIPELINE="elasticsearch/templates/winlogbeat-$version-sysmon.json"

    if [[ ! -r "$ROUTING_PIPELINE" || ! -r "$SYSMON_PIPELINE" || ! -r "$POWERSHELL_PIPELINE" || ! -r "$POWERSHELL_OPERATIONAL_PIPELINE"  || ! -r "$SECURITY_PIPELINE" ]]; then
        fail "Couldn't find required ingest pipeline template files: $ROUTING_PIPELINE, $SYSMON_PIPELINE, $POWERSHELL_PIPELINE, $POWERSHELL_OPERATIONAL_PIPELINE, $SECURITY_PIPELINE"
    fi

    # Load index template and data stream
    create_data_stream "$es_pass" "$version"

    require_elasticsearch_api_up "$es_pass"

    # Load winlogbeat-x.x.x-routing ingest pipeline
    if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_ingest/pipeline/winlogbeat-$version-routing" -H 'Content-Type: application/json' --data-binary "@$ROUTING_PIPELINE" > /dev/null; then
        fail "Couldn't load winlogbeat-$version routing ingest pipeline"
    else
        # Load winlogbeat-x.x.x-sysmon ingest pipeline
        printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version routing ingest pipeline\n"
        if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_ingest/pipeline/winlogbeat-$version-sysmon" -H 'Content-Type: application/json' --data-binary "@$SYSMON_PIPELINE" > /dev/null; then
            fail "Couldn't load winlogbeat-$version sysmon ingest pipeline"
        else
            # Load winlogbeat-x.x.x-security ingest pipeline
            printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version sysmon ingest pipeline\n"
            if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_ingest/pipeline/winlogbeat-$version-security" -H 'Content-Type: application/json' --data-binary "@$SECURITY_PIPELINE" > /dev/null; then
                fail "Couldn't load winlogbeat-$version security ingest pipeline"
            else 
                # Load winlogbeat-x.x.x-powershell ingest pipeline
                printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version security ingest pipeline\n"
                if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_ingest/pipeline/winlogbeat-$version-powershell" -H 'Content-Type: application/json' --data-binary "@$POWERSHELL_PIPELINE" > /dev/null; then
                    fail "Couldn't load winlogbeat-$version powershell ingest pipeline"
                else 
                    # Load winlogbeat-x.x.x-powershell_operational ingest pipeline
                    printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version powershell ingest pipeline\n"
                    if ! curl --fail -u "elastic:$es_pass" -X PUT -k "https://localhost:9200/_ingest/pipeline/winlogbeat-$version-powershell_operational" -H 'Content-Type: application/json' --data-binary "@$POWERSHELL_OPERATIONAL_PIPELINE" > /dev/null; then
                        fail "Couldn't load winlogbeat-$version powershell_operational ingest pipeline"
                    else 
                        printf "  ${GREEN}\u2714${NC} Loaded winlogbeat-$version powershell_operational ingest pipeline\n"
                    fi
                fi
            fi
        fi
    fi
}

upgrade_beaker() {
    local es_pass="$1"
    local docker_sudo="$2"
    local install_elastic_version="$INSTALL_ELASTIC_VERSION"
    mandatory_upgrade_version="7.17.9"
    if "$UPGRADE_INSTALL" ; then
        # default to v7.0.0 if current version doesn't exist in env file
        if [ -z "$CURRENT_ELASTIC_VERSION" ]; then
            CURRENT_ELASTIC_VERSION="7.0.0"
        fi
        major_version=$(echo "$CURRENT_ELASTIC_VERSION" | cut -d "." -f 1)
        minor_version=$(echo "$CURRENT_ELASTIC_VERSION" | cut -d "." -f 2)

        # If ELK version less than 8.0.0
        if [ $major_version -lt 8 ]; then
            if [ $minor_version -lt 17 ]; then 
                # If ELK version less than 7.17, force upgrade to 7.17.x
                install_elastic_version="$mandatory_upgrade_version"
            elif [ $minor_version -eq 17 ]; then
                if [ "$acm_no_interactive" != 'yes' ]; then
                    echo "The currently installed Elastic stack version is v$CURRENT_ELASTIC_VERSION"
                    echo "Would you like to upgrade to Elastic stack v$install_elastic_version or reinstall v$CURRENT_ELASTIC_VERSION?"
                    echo "[Y] Upgrade to v$install_elastic_version    [N] Reinstall $CURRENT_ELASTIC_VERSION"
                    if askYN; then 
                        printf "${YELLOW}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}\n"
                        printf "${YELLOW}Elastic v$install_elastic_version is a major release version upgrade!${NC}\n"
                        echo "While BeaKer attempts to prepare your system as best as possible for the upgrade, your particular deployment and usage of the Elastic stack may require additional preparation."
                        echo "If your BeaKer installation is meant to run in a production environment, please take the following precautionary steps:"
                        echo "  [1]  Use the Kibana Upgrade assistant to resolve any critical issues before upgrading. It can be found in the Kibana UI under Stack Management > Upgrade Assistant."
                        echo "  [2]  Upgrade your Windows agents to Winlogbeat v$mandatory_upgrade_version using install-sysmon-beats.ps1 if you have not already."
                        echo ""
                        echo "The Elastic stack $(tput bold)cannot$(tput sgr0) be downgraded to a previous version."
                        echo "In the event of upgrade failure, BeaKer must be reinstalled with the previously installed version."
                        echo "The BeaKer installer will prompt you to create a snapshot that can be used to restore your data in the event of upgrade failure."
                        printf "${YELLOW}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}\n"
                        echo ""
                        echo "Would you like to continue upgrading to Elastic v$install_elastic_version? (Y/N)"
                        if ! askYN; then 
                            echo "Upgrade installation was cancelled by the user."
                            exit
                        fi
                        echo "Would you like to create a snapshot?"
                        if askYN; then 
                            status "Creating snapshot"
                            create_snapshot "$es_pass"
                        else
                            echo "Upgrading without creating snapshot..."
                        fi
                    else
                        install_elastic_version="$mandatory_upgrade_version"
                    fi
                fi
            fi
        else
            # ELK stack version is at least 8.0.0
            patch_version=$(echo "$CURRENT_ELASTIC_VERSION" | cut -d "." -f 3)
            install_major_version=$(echo "$install_elastic_version" | cut -d "." -f 1)
            install_minor_version=$(echo "$install_elastic_version" | cut -d "." -f 2)
            install_patch_version=$(echo "$install_elastic_version" | cut -d "." -f 3)
            # If the upgrade is not to a higher major version
            if [ $major_version -eq $install_major_version ]; then
                # If the upgrade is to a higher minor version or higher patch version, ask to upgrade or reinstall current version
                if [ $install_minor_version -gt $minor_version ] || [ $install_minor_version -eq $minor_version -a $install_patch_version -gt $patch_version ]; then
                    echo "The currently installed Elastic stack version is v$CURRENT_ELASTIC_VERSION"
                    echo "Would you like to upgrade to Elastic stack v$install_elastic_version or reinstall v$CURRENT_ELASTIC_VERSION?"
                    echo "[Y] Upgrade to v$install_elastic_version   [N] Reinstall $CURRENT_ELASTIC_VERSION"

                    if ! askYN; then 
                        install_elastic_version="$CURRENT_ELASTIC_VERSION"
                    fi
                else
                    install_elastic_version="$CURRENT_ELASTIC_VERSION"
                fi
            fi
        fi
        INSTALL_ELASTIC_VERSION=$install_elastic_version
        status "Upgrading to Elastic v$INSTALL_ELASTIC_VERSION..."
        $docker_sudo sed -i "s/activecm-beaker\/elasticsearch:.*/activecm-beaker\/elasticsearch:$INSTALL_ELASTIC_VERSION/g" /opt/BeaKer/docker-compose.yml
        $docker_sudo sed -i "s/activecm-beaker\/kibana:.*/activecm-beaker\/kibana:$INSTALL_ELASTIC_VERSION/g" /opt/BeaKer/docker-compose.yml
    else
        INSTALL_ELASTIC_VERSION=$install_elastic_version
        status "Installing Elastic v$INSTALL_ELASTIC_VERSION..."
    fi
}

install_beaker () {
    status "Installing Elasticsearch and Kibana"

    # Determine if the current user has permission to run docker
    local docker_sudo=""
    if [ ! -w "/var/run/docker.sock" ]; then
        docker_sudo="sudo -E"
    fi

    # Load password
    # Use docker_sudo since the env file ownership is root:docker.
    local es_pass=`$docker_sudo grep '^ELASTIC_PASSWORD' "$BEAKER_CONFIG_DIR/env" | sed -e 's/^[^=][^=]*=//'`

    INSTALL_ELASTIC_VERSION=$( tail -n 1 ELK_VERSIONS )

    upgrade_beaker "$es_pass" "$docker_sudo"

    # Load the docker images
    gzip -d -c images-latest.tar.gz | $docker_sudo docker load >&2

    ensure_certificates_exist

    # Start Elasticsearch and Kibana with the new images
    ./beaker up -d --force-recreate >&2

    status "Waiting for initialization"
    sleep 15

    install_major_version=$(echo "$INSTALL_ELASTIC_VERSION" | cut -d "." -f 1)

    status "Creating service account token"
    create_service_account_token "$es_pass"

    status "Loading index lifecycle policy"
    create_index_lifecycle_policy "$es_pass"

    dashboard_filename="kibana_dashboards-8.0.0.ndjson"

    if [ $install_major_version -eq 8 ]; then 
        status "Loading Ingest Pipelines"
        create_ingest_pipelines "$es_pass" "$INSTALL_ELASTIC_VERSION"
    elif [ $install_major_version -lt 8 ]; then 
        status "Loading Index Template & Data Stream"
        create_data_stream "$es_pass" "$INSTALL_ELASTIC_VERSION"
        dashboard_filename="kibana_dashboards-7.17.0.ndjson"
    fi
    
    require_elasticsearch_api_up "$es_pass"
    status "Waiting for Kibana to come online"
    echo "This might take a while..."
    require_kibana_available "$es_pass"

    status "Loading Kibana dashboards"

    echo "Uploading $dashboard_filename"
    local connection_attempts=0
    local data_uploaded="false"
    while [ $connection_attempts -lt 8 -a "$data_uploaded" != "true" ]; do
        if echo "$es_pass" | kibana/import_dashboards.sh "kibana/$dashboard_filename" >&2 ; then
            printf "${GREEN}\u2714${NC} The installer successfully uploaded dashboards to Kibana.\n"
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

    # Update installed version tag in config
    $docker_sudo sed -i "s/ELK_STACK_VERSION=.*/ELK_STACK_VERSION=$INSTALL_ELASTIC_VERSION/g" "$BEAKER_CONFIG_DIR/env"
}


configure_ingest_account () {
    # Determine if the current user has permission to run docker/ read the env file
    local docker_sudo=""
    if [ ! -w "/var/run/docker.sock" ]; then
        docker_sudo="sudo"
    fi
    local es_pass=`$docker_sudo grep ELASTIC_PASSWORD "$BEAKER_CONFIG_DIR/env" | cut -d= -f2`

    require_elasticsearch_api_up "$es_pass"

    ingest_account_exists=false

    # Don't configure the ingest account if it already exists
    if curl --fail -s -u "elastic:$es_pass" -X GET -k "https://localhost:9200/_security/user/sysmon-ingest" | grep -q "\"username\":\"sysmon-ingest\""; then
        ingest_account_exists=true
    fi

    if [ "$acm_no_interactive" = 'yes' ]; then
        echo2 "We are in non-interactive mode but the ingest account is not configured, exiting."
        exit 1
    fi

    if ! $ingest_account_exists ; then
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
    fi

    if ! curl --fail -s -u "elastic:$es_pass" -X POST -k "https://localhost:9200/_security/role/sysmon-ingest" -H 'Content-Type: application/json' -d'
    {
        "run_as": [],
        "cluster": [ "monitor", "read_ilm", "read_pipeline" ],
        "indices": [
            {
                "names": [ "sysmon-*" ],
                "privileges": [ "create_doc", "create_index" ]
            },
            {
                "names": [ "winlogbeat-*" ],
                "privileges": [ "create_doc", "create_index", "auto_configure" ]
            }
        ]
    }
    ' > /dev/null ; then
        fail "Unable to create Elasticsearch ingest role."
    fi

    if ! $ingest_account_exists ; then
        if ! curl --fail -s -u "elastic:$es_pass" -X POST -k "https://localhost:9200/_security/user/sysmon-ingest" -H 'Content-Type: application/json' -d"
        {
            \"password\" : \"$ingest_password\",
            \"roles\" : [ \"sysmon-ingest\" ]
        }
        " > /dev/null ; then
            fail "Unable to create Elasticsearch ingest user."
        fi
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
    export acm_no_interactive

    test_system

    move_files
    link_executables

    status "Installing supporting software"
    ensure_common_tools_installed

    install_docker

    ensure_snapshot_repo_exists
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
