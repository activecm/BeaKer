#!/bin/bash

curl -u "elastic:$ELASTIC_PASSWORD" -X POST "localhost:5601/api/saved_objects/_export" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -d'
{
  "type": ["index-pattern", "config", "visualization", "dashboard", "map", "canvas-workpad", "canvas-element", "query", "search", "url"],
  "includeReferencesDeep": true
}
'