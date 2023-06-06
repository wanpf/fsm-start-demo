#!/bin/bash

set -euo pipefail

if [ -z "$1" ]; then
  echo "Error: expected one argument FSM Demo's Repo"
  exit 1
fi

DemoRepo=$1

find ./demo -type f -name "*.md" -exec sed -i "s#-f .*/demo#-f ${DemoRepo}/demo#g" {} +