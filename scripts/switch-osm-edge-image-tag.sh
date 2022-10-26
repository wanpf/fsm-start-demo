#!/bin/bash

set -euo pipefail

if [ -z "$1" ]; then
  echo "Error: expected one argument OSM Edge Image's Tag"
  exit 1
fi

ImageTag=$1

find ./demo -type f -name "*.md" -exec sed -i "s#--set=osm.image.tag=.*\\\\#--set=osm.image.tag=${ImageTag} \\\\#g" {} +