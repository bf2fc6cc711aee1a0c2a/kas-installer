#!/usr/bin/env bash

# Inspired from: https://gist.github.com/b1zzu/ccd9ef553d546a2009eca21ab45db97a

set -eEu -o pipefail
# shellcheck disable=SC2154
trap 's=$?; echo "$0: error on $0:$LINENO"; exit $s' ERR

