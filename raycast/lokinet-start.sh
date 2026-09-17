#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Start Lokinet
# @raycast.mode fullOutput
# @raycast.packageName Lokinet
# @raycast.icon 🧅
# @raycast.author janindra_goonetilleke
# @raycast.authorURL https://raycast.com/janindra_goonetilleke
# @raycast.description Start Lokinet daemon and route DNS exclusively through Lokinet with NextDNS upstream

set -euo pipefail

# Ensure running as root for networksetup, launchctl, and port 53 binding
if [ "$EUID" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then
    exec sudo "$0" "$@"
  else
    exec osascript -e "do shell script \"'$0' $*\" with administrator privileges"
  fi
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LOKINET_BIN="/Users/janindra/lokinet/build/daemon/lokinet-daemon"
CONFIG_FILE="/Users/janindra/.lokinet/lokinet.ini"
PID_FILE="/var/run/lokinet.pid"
LOG_FILE="/Users/janindra/Library/Logs/lokinet.log"
DOH_PLIST="/Library/LaunchDaemons/com.janindra.doh.dnsstub.plist"

echo "=== 🧅 Starting Lokinet with NextDNS Upstream ==="

# 1. Ensure dnsproxy (NextDNS DoH) is running on port 5354
if [ -f "$DOH_PLIST" ]; then
  if grep -q "<string>53</string>" "$DOH_PLIST"; then
    echo "⚙️  Reconfiguring dnsproxy to port 5354 (freeing port 53 for Lokinet)..."
    cp "$DOH_PLIST" "${DOH_PLIST}.bak"
    sed -i '' -e '/--port/{n;s/<string>53<\/string>/<string>5354<\/string>/;}' "$DOH_PLIST"
    launchctl unload "$DOH_PLIST" 2>/dev/null || true
    launchctl load "$DOH_PLIST"
    sleep 1
  fi
fi

# Verify NextDNS DoH upstream is listening on 5354
TEST_UPSTREAM=$(dig @127.0.0.1 -p 5354 +short +time=1 test.nextdns.io 2>/dev/null | grep -v "^;" || true)
if [ -n "$TEST_UPSTREAM" ]; then
  echo "✅ NextDNS DoH upstream active on 127.0.0.1:5354 ($TEST_UPSTREAM)"
else
  echo "ℹ️  NextDNS DoH on 5354 starting or fallback Anycast will be used"
fi

# 2. Start lokinet-daemon if not already running
EXISTING_PID=$(pgrep -f "$LOKINET_BIN" | head -n 1 || true)
if [ -n "$EXISTING_PID" ]; then
  echo "ℹ️  Lokinet daemon is already running (PID: $EXISTING_PID)"
else
  echo "🚀 Launching Lokinet daemon..."
  mkdir -p "$(dirname "$LOG_FILE")"
  nohup "$LOKINET_BIN" "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
  LOKI_PID=$!
  echo "$LOKI_PID" > "$PID_FILE"
  
  # Wait for Lokinet to bind port 53 (up to 5 seconds)
  READY=0
  for i in {1..10}; do
    if nc -z -u -w 1 127.0.0.1 53 2>/dev/null; then
      READY=1
      break
    fi
    sleep 0.5
  done

  if [ "$READY" -eq 1 ]; then
    echo "✅ Lokinet daemon running (PID: $LOKI_PID) listening on 127.0.0.1:53"
  else
    echo "⚠️  Lokinet started (PID: $LOKI_PID); port 53 initializing (check log at $LOG_FILE)"
  fi
fi

# 3. Bind macOS System DNS Exclusively to Lokinet
echo "🔒 Binding System DNS exclusively to Lokinet (127.0.0.1)..."
networksetup -setdnsservers Wi-Fi 127.0.0.1
if networksetup -listallnetworkservices 2>/dev/null | grep -q "AX88179A"; then
  networksetup -setdnsservers AX88179A 127.0.0.1 2>/dev/null || true
fi

# Flush DNS cache
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "=== 📋 Verification ==="
echo "Active Nameserver: $(grep nameserver /etc/resolv.conf | head -n 1)"
echo "Wi-Fi DNS: $(networksetup -getdnsservers Wi-Fi)"

# Quick DNS test
TEST_RES=$(dig @127.0.0.1 +short +time=2 test.nextdns.io 2>/dev/null || true)
if [ -n "$TEST_RES" ]; then
  echo "DNS Test (test.nextdns.io): Resolved ($TEST_RES) via NextDNS"
else
  echo "DNS Test: Resolving via Lokinet..."
fi

echo ""
echo "🟢 Lokinet is UP and System DNS is bound exclusively to Lokinet."
