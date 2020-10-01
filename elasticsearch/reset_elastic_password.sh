#!/usr/bin/env bash
set -e

# Change dir to script dir
pushd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" > /dev/null

main() {
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

    echo "Creating temporary local admin to change the elastic account password" >&2
    local temp_pass=`apg -a 0 -m 12 -x 12 -M NCL -E '015|=' -n 1`

    beaker exec elasticsearch /usr/share/elasticsearch/bin/elasticsearch-users userdel temp_admin > /dev/null || true
    beaker exec elasticsearch /usr/share/elasticsearch/bin/elasticsearch-users useradd temp_admin -p "$temp_pass" -r superuser

    echo "Updating the elastic account password via REST interface" >&2
    sleep 5

    curl --fail -k -s -u temp_admin:"$temp_pass" -XPUT "https://localhost:9200/_xpack/security/user/elastic/_password?pretty" -H 'Content-Type: application/json' -d"
    {
        \"password\" : \"$elastic_password\"
    }
    "

    echo "Removing temporary local admin" >&2
    beaker exec elasticsearch /usr/share/elasticsearch/bin/elasticsearch-users userdel temp_admin

    local BEAKER_CONFIG_DIR=${BEAKER_CONFIG_DIR:-/etc/BeaKer}
    echo "Updating Kibana configuration in $BEAKER_CONFIG_DIR/env" >&2
    sudo sed --in-place=bak "s/^ELASTIC_PASSWORD=.*\$/ELASTIC_PASSWORD=$elastic_password/" "$BEAKER_CONFIG_DIR"/env

    beaker down
    beaker up -d
}

main

# Change back to original directory
popd > /dev/null