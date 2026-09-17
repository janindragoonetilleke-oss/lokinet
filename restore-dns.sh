#!/bin/bash
set -e

echo "=== Reverting DNS to automatic (DHCP) ==="
networksetup -setdnsservers Wi-Fi empty
echo "Wi-Fi DNS reset to default (Empty/DHCP)"

if networksetup -listallnetworkservices | grep -q "AX88179A"; then
    networksetup -setdnsservers AX88179A empty 2>/dev/null || true
    echo "AX88179A DNS reset to default (Empty/DHCP)"
fi

PLIST="/Library/LaunchDaemons/com.janindra.doh.dnsstub.plist"
if [ -f "${PLIST}.bak" ]; then
    echo "Restoring original dnsproxy plist..."
    cp "${PLIST}.bak" "$PLIST"
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "dnsproxy restored to port 53."
fi

dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true
echo "DNS cache flushed. Restored to normal."
