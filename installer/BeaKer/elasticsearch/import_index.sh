#!/usr/bin/env bash

# Grab input arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: ./import_index.sh path/to/archive.tar"
    exit 1
fi

input_tar=`realpath "$1"`

# Change dir to script parent dir after calling realpath on the output directory
pushd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null

# Use main function for local vars to hold sensitive info
main() {
    local input_tar_dir=`dirname "$input_tar"`
    local index_name=`tar --exclude='*/*' -tf "$input_tar"`
    
    tar -xf "$input_tar" -C "$input_tar_dir"
    local index_dir="$input_tar_dir/$index_name"
    
    local username=""
    IFS="" read -es -p "Elasticsearch Username: " username
    echo "" 
    local password=""
    IFS="" read -es -p "Elasticsearch Password: " password
    echo ""
    ./beaker run -v "$index_dir:/$index_name" --entrypoint multielasticdump es-dump --direction=load --input="/$index_name" --output="https://$username:$password@elasticsearch:9200"
    
    rm -rf "$index_dir"
}

main

# Change back to original directory
popd > /dev/null
