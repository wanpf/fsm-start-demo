#!/bin/bash

set -euo pipefail

if [ -z "$1" ]; then
  echo "Error: expected one argument FSM Image's Tag"
  exit 1
fi

ImageTag=$1

find ./demo -type f -name "*.md" -exec sed -i "s#--set=fsm.image.tag=.*\\\\#--set=fsm.image.tag=${ImageTag} \\\\#g" {} +