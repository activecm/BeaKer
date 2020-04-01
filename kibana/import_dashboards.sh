#!/bin/bash

# Reads the elasticsearch password from stdin and uploads
# the file given to localhost:5601.

set -e

DASHBOARD_FILE="$1"

read_password() {
    local reply=""
    if [ -t 0 ]; then
        IFS="" read -es -p "Elasticsearch Password: " reply
        echo "" >&2
    else
        IFS="" read reply <&0;
    fi
    echo "$reply"
}

main () {
    local es_pass="$(read_password)"
    local resp=`curl -u "elastic:$es_pass" -X POST -k "https://localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -F file=@$DASHBOARD_FILE`
    if [ $? -ne 0 -o "$resp" == "Kibana server is not ready yet" ]; then
        exit 2
    fi
}

main "$@"