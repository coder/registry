#!/bin/sh
# minimal mock that prints args and exits
printf "cursor mock invoked with: %s\n" "$*"
# Exit successfully regardless
exit 0
