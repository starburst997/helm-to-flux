#!/bin/bash
helm list -A -o json | jq -r '.[] | "\(.name) \(.namespace)"' | while read name ns; do
  echo "Extracting $name from $ns"
  ./convert.sh "$name" "$ns"
done