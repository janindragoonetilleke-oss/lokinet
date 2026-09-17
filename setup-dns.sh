#!/bin/bash
set -e

echo "=== 1. Updating dnsproxy (NextDNS DoH stub) to listen on port 5354 ==="
PLIST="/Library/LaunchDaemons/com.janindra.doh.dnsstub.plist"

if [ -f "$PLIST" ]; then
    # Backup plist
    cp "$PLIST" "${PLIST}.bak"
    # Update port 53 to 5354
    sed -i '' -e '/--port/{n;s/<string>53<\/string>/<string>5354<\/string>/;}' "$PLIST"
    
    echo "Reloading com.janindra.doh.dnsstub..."
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    sleep 1
    echo "dnsproxy reloaded on 127.0.0.1:5354 (NextDNS DoH upstream)."
else
    echo "Warning: $PLIST not found. If running dnsproxy manually, ensure it runs on --port 5354."
fi

echo ""
echo "=== 2. Binding system DNS exclusively to Lokinet (127.0.0.1) ==="
# Set Wi-Fi DNS
networksetup -setdnsservers Wi-Fi 127.0.0.1
echo "Wi-Fi DNS set to 127.0.0.1"

# Set Ethernet if present
if networksetup -listallnetworkservices | grep -q "AX88179A"; then
    networksetup -setdnsservers AX88179A 127.0.0.1 2>/dev/null || true
    echo "AX88179A Ethernet DNS set to 127.0.0.1"
fi

echo "Flushing macOS DNS cache..."
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "=== 3. Current /etc/resolv.conf ==="
cat /etc/resolv.conf

echo ""
echo "=== Configuration Complete ==="
echo "Port 53 is now reserved for Lokinet on 127.0.0.1."
echo "Upstream queries from Lokinet are forwarded to NextDNS DoH proxy on 127.0.0.1:5354."
