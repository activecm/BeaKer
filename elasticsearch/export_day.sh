#!/usr/bin/env bash

# Grab input arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: ./export_day.sh day_to_save (format: YYYY-MM-DD) output/directory"
    exit 1
fi

day="$1"
output_dir=`realpath "$2"`
index_name="sysmon-$day"

# Change dir to script parent dir after calling realpath on the output directory
pushd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null

# Use main function for local vars to hold sensitive info
main() {

    mkdir -p "$output_dir/$index_name"


    local username=""
    IFS="" read -es -p "Elasticsearch Username: " username
    echo "" 
    local password=""
    IFS="" read -es -p "Elasticsearch Password: " password
    echo ""

    previous_day=$(date --date="${day} -1 day" +%Y-%m-%d)

    # Export winlogbeat-* data by matching on winlogbeat data stream ALIAS
    ./beaker run -v "$output_dir/$index_name:/exports:rw" \
    --entrypoint multielasticdump es-dump \
    --direction=dump \
    --input="https://$username:$password@elasticsearch:9200" \
    --output="/exports" \
    --includeType="data,mapping" \
    --match="^winlogbeat-.*$" \
    --searchBody="{\"query\":{\"range\":{\"@timestamp\": {\"gt\": \"${previous_day}\", \"lte\": \"${day}\"}}}}"
    

    tar -C "$output_dir" -czf "$output_dir/$index_name.tar.gz" "$index_name"
    rm -rf "$output_dir/$index_name"
}

main

# Change back to original directory
popd > /dev/null
