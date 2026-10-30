#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi

# While Stacks Pro is paused (StacksPro.isEnabled = false) Release may ship
# without a RevenueCat key. Before re-enabling Pro, require appl_ here again.
case "${INFOPLIST_KEY_STACKS_REVENUECAT_API_KEY:-}" in
    appl_?*) ;;
    "")
        echo "warning: Release has no RevenueCat key. Fine while Stacks Pro is paused; add the appl_ key before turning Pro back on."
        ;;
    *)
        echo "error: Release requires the public Apple RevenueCat SDK key (appl_...) in INFOPLIST_KEY_STACKS_REVENUECAT_API_KEY. Never archive with the Test Store key."
        exit 1
        ;;
esac
