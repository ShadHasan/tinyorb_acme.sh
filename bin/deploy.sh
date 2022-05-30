#!/bin/bash

set -e

path="$(readlink -f ${BASH_SOURCE[0]})"
docker_path="$(dirname $(dirname ${path}))"
echo ${docker_path}
case $1 in
reload)
  sudo docker kill tinyorb_acme || true
  sudo docker rm tinyorb_acme || true
  case $3 in
  all)
    sudo docker image rm tinyorb_acmesh || true
    ;;
  esac
  ;;
esac
if [ -f "${docker_path}/Dockerfile" ]; then
  sudo docker image build -t tinyorb_acmesh -f Dockerfile "${docker_path}"
  sudo docker run --name=tinyorb_acme -d tinyorb_acmesh
fi