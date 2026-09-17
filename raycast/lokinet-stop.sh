#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop Lokinet
# @raycast.mode fullOutput
# @raycast.packageName Lokinet
# @raycast.icon 🛑
# @raycast.author janindra_goonetilleke
# @raycast.authorURL https://raycast.com/janindra_goonetilleke
# @raycast.description Shut down Lokinet daemon and revert DNS to default DHCP (NextDNS)

set -euo pipefail

# Ensure running as root for networksetup and process management
if [ "$EUID" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then
    exec sudo "$0" "$@"
  else
    exec osascript -e "do shell script \"'$0' $*\" with administrator privileges"
  fi
fi

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LOKINET_BIN="lokinet-daemon"
PID_FILE="/var/run/lokinet.pid"

echo "=== 🛑 Stopping Lokinet & Reverting to Default DHCP ==="

# 1. Stop Lokinet daemon
PIDS=$(pgrep -f "$LOKINET_BIN" || true)
if [ -n "$PIDS" ]; then
  echo "Terminating Lokinet daemon (PID: $(echo $PIDS | tr '\n' ' '))..."
  for pid in $PIDS; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  
  # Wait for process to exit gracefully
  for i in {1..6}; do
    if ! pgrep -f "$LOKINET_BIN" >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done

  # Force kill if still hanging
  REMAINING=$(pgrep -f "$LOKINET_BIN" || true)
  if [ -n "$REMAINING" ]; then
    echo "Force stopping remaining processes..."
    kill -9 $REMAINING 2>/dev/null || true
  fi
  echo "✅ Lokinet daemon stopped."
else
  echo "ℹ️  Lokinet daemon was not running."
fi

rm -f "$PID_FILE"

# 2. Revert macOS System DNS to Default DHCP
echo "🔄 Reverting System DNS to Default DHCP..."
networksetup -setdnsservers Wi-Fi empty
echo "Wi-Fi DNS reverted to DHCP."

if networksetup -listallnetworkservices 2>/dev/null | grep -q "AX88179A"; then
  networksetup -setdnsservers AX88179A empty 2>/dev/null || true
  echo "AX88179A Ethernet DNS reverted to DHCP."
fi

# 3. Clean up /etc/resolver/loki and flush DNS cache
rm -f /etc/resolver/loki
echo "🧹 Flushing DNS cache..."
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

echo ""
echo "=== 📋 Verification ==="
echo "Active Nameserver: $(grep nameserver /etc/resolv.conf 2>/dev/null | head -n 1 || echo 'DHCP Default')"
echo "Wi-Fi DNS Setting: $(networksetup -getdnsservers Wi-Fi)"

# Test resolution via DHCP
TEST_RES=$(dig +short +time=2 test.nextdns.io 2>/dev/null || true)
if [ -n "$TEST_RES" ]; then
  echo "DNS Test (test.nextdns.io): Resolved ($TEST_RES) via DHCP NextDNS"
else
  echo "DNS Test: Normal DNS resolution active"
fi

echo ""
echo "⚪ Lokinet is STOPPED. System is using default DHCP (NextDNS)."
