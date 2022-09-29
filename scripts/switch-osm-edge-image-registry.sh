#!/bin/bash

set -euo pipefail

if [ -z "$1" ]; then
  echo "Error: expected one argument OSM Edge Image's Registry"
  exit 1
fi

ImageRegistry=$1

find ./demo -type f -name "*.md" -exec sed -i "s#--set=osm.image.registry=.*\\\\#--set=osm.image.registry=${ImageRegistry} \\\\#g" {} +