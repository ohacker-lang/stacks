#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi

case "${INFOPLIST_KEY_STACKS_REVENUECAT_API_KEY:-}" in
    appl_?*) ;;
    *)
        echo "error: Release requires the public Apple RevenueCat SDK key (appl_...) in INFOPLIST_KEY_STACKS_REVENUECAT_API_KEY. Never archive with the Test Store key."
        exit 1
        ;;
esac
