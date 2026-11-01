#!/usr/bin/env bash

case "$1" in
  --version | -V)
    echo " 1.54.0-mock"
    ;;
  *)
    echo "goose invoked with: $*"
    ;;
esac
exit 0
