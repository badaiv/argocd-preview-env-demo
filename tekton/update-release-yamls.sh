#!/bin/bash
download_file() {
  local arg1=$1
  local arg2=$2
  local arg3=$3
  local url="https://storage.googleapis.com/tekton-releases/${arg1}/previous/${arg2}/${arg3:-release}.yaml"

  echo "Downloading from URL: $url to directory: $arg2"
  curl -s -o "${arg1}-${arg2}-$(basename $url)" "$url"
}

download_file "pipeline" "v0.68.1"
download_file "triggers" "v0.30.1"
download_file "triggers" "v0.30.1" "interceptors"
download_file "dashboard" "v0.56.0"