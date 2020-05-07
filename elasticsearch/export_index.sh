#!/usr/bin/env bash

# Grab input arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: ./export_index.sh index_to_save output/directory"
    exit 1
fi

index_name="$1"
output_dir=`realpath "$2"`

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

    ./beaker run -v "$output_dir/$index_name:/exports:rw" --entrypoint multielasticdump es-dump --input="https://$username:$password@elasticsearch:9200" --output="/exports" --includeType="data,mapping" --match="^$index_name\$"
    
    tar -C "$output_dir" -czf "$output_dir/$index_name.tar.gz" "$index_name"
    rm -rf "$output_dir/$index_name"
}

main

# Change back to original directory
popd > /dev/null
