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

# 2. Start lokinet-daemon (restarting any existing instance)
EXISTING_PID=$(pgrep -f "$LOKINET_BIN" | head -n 1 || true)
if [ -n "$EXISTING_PID" ]; then
  echo "🔄 Stopping existing Lokinet daemon (PID: $EXISTING_PID)..."
  kill -TERM "$EXISTING_PID" 2>/dev/null || true
  sleep 0.5
  kill -9 "$EXISTING_PID" 2>/dev/null || true
fi

  echo "🚀 Launching Lokinet daemon..."
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Standard clean detachment without BSD nohup (which fails under AppleScript console detachment)
  "$LOKINET_BIN" "$CONFIG_FILE" </dev/null > "$LOG_FILE" 2>&1 &
  LOKI_PID=$!
  
  # Wait and verify that Lokinet is alive and answering on port 53 (up to 10 seconds)
  READY=0
  for i in {1..20}; do
    if ! kill -0 "$LOKI_PID" 2>/dev/null; then
      echo "❌ Lokinet daemon process exited unexpectedly shortly after launch!"
      break
    fi
    if dig @127.0.0.1 -p 53 +time=1 +tries=1 . >/dev/null 2>&1 || dig @127.0.0.1 -p 53 +time=1 +tries=1 test.nextdns.io >/dev/null 2>&1; then
      READY=1
      break
    fi
    sleep 0.5
  done

  if [ "$READY" -ne 1 ]; then
    echo "❌ Lokinet failed to become ready on 127.0.0.1:53"
    echo ""
    echo "--- 📜 Daemon Log Tail ($LOG_FILE) ---"
    tail -n 15 "$LOG_FILE" 2>/dev/null || true
    echo "---------------------------------------"
    rm -f "$PID_FILE"
    
    # SAFETY ROLLBACK: Ensure Wi-Fi DNS is restored to default DHCP if it pointed to 127.0.0.1
    CURRENT_DNS=$(networksetup -getdnsservers Wi-Fi 2>/dev/null || echo "")
    if [ "$CURRENT_DNS" = "127.0.0.1" ]; then
      echo "🔄 Restoring Wi-Fi DNS to default DHCP to prevent broken resolution..."
      networksetup -setdnsservers Wi-Fi empty
      dscacheutil -flushcache
      killall -HUP mDNSResponder 2>/dev/null || true
    fi
    exit 1
  fi

  echo "$LOKI_PID" > "$PID_FILE"
  echo "✅ Lokinet daemon running (PID: $LOKI_PID) listening on 127.0.0.1:53"
fi

# 3. Bind macOS System DNS Exclusively to Lokinet
echo "🔒 Binding System DNS exclusively to Lokinet (127.0.0.1)..."
networksetup -setdnsservers Wi-Fi 127.0.0.1
if networksetup -listallnetworkservices 2>/dev/null | grep -q "AX88179A"; then
  networksetup -setdnsservers AX88179A 127.0.0.1 2>/dev/null || true
fi

# Configure dedicated .loki domain resolver for macOS system browsers (Comet, Safari, Chrome)
mkdir -p /etc/resolver
cat <<EOF > /etc/resolver/loki
nameserver 127.0.0.1
port 53
EOF

# Flush DNS cache
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "=== 📋 Verification ==="
echo "Active Nameserver: $(grep nameserver /etc/resolv.conf 2>/dev/null | head -n 1 || echo 'none')"
echo "Wi-Fi DNS: $(networksetup -getdnsservers Wi-Fi 2>/dev/null)"

# Quick DNS test
TEST_RES=$(dig @127.0.0.1 +short +time=2 test.nextdns.io 2>/dev/null || true)
if [ -n "$TEST_RES" ]; then
  echo "DNS Test (test.nextdns.io): Resolved ($TEST_RES) via Lokinet -> NextDNS"
else
  echo "DNS Test: Resolving via Lokinet..."
fi

echo ""
echo "🟢 Lokinet is UP and System DNS is bound exclusively to Lokinet."
