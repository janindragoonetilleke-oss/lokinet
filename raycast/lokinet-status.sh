#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Lokinet Status
# @raycast.mode fullOutput
# @raycast.packageName Lokinet
# @raycast.icon 📊
# @raycast.author janindra_goonetilleke
# @raycast.authorURL https://raycast.com/janindra_goonetilleke
# @raycast.description Check Lokinet daemon process, DNS binding, and NextDNS upstream status

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

LOKINET_BIN="lokinet-daemon"

echo "=== 🧅 Lokinet Status Report ==="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo ""

# 1. Check Lokinet Daemon Process
LOKI_PID=$(pgrep -f "$LOKINET_BIN" | head -n 1 || true)
if [ -n "$LOKI_PID" ]; then
  LOKI_STATUS="🟢 RUNNING"
  PROC_INFO=$(ps -p "$LOKI_PID" -o pid,%cpu,%mem,etime,comm | tail -n 1)
  echo "1. Lokinet Daemon:  $LOKI_STATUS (PID: $LOKI_PID)"
  echo "   Process Details: $PROC_INFO"
else
  LOKI_STATUS="⚪ STOPPED"
  echo "1. Lokinet Daemon:  $LOKI_STATUS"
fi

# 2. Check Port 53 Binding
echo ""
if dig @127.0.0.1 -p 53 +time=1 +tries=1 . >/dev/null 2>&1; then
  echo "2. Port 53 Listener: 🟢 ACTIVE on 127.0.0.1:53 (DNS responding)"
elif [ -n "$LOKI_PID" ]; then
  echo "2. Port 53 Listener: 🟡 Daemon alive, but port 53 not yet answering"
else
  echo "2. Port 53 Listener: ⚪ INACTIVE (Nothing listening on 127.0.0.1:53)"
fi

# 3. Check NextDNS DoH Upstream (Port 5354)
echo ""
TEST_DOH=$(dig @127.0.0.1 -p 5354 +short +time=1 test.nextdns.io 2>/dev/null | grep -v "^;" || true)
if [ -n "$TEST_DOH" ]; then
  echo "3. NextDNS DoH Proxy: 🟢 ACTIVE (127.0.0.1:5354) — Verified ($TEST_DOH)"
else
  echo "3. NextDNS DoH Proxy: ⚪ NOT LISTENING on 5354 (Fallback NextDNS Anycast in use)"
fi

# 4. Check macOS System DNS Configuration
echo ""
WIFI_DNS=$(networksetup -getdnsservers Wi-Fi 2>/dev/null || echo "Unknown")
RESOLV_NS=$(grep nameserver /etc/resolv.conf 2>/dev/null | tr '\n' ' ' || echo "None")
echo "4. System DNS Config:"
echo "   Wi-Fi Setting:    $WIFI_DNS"
echo "   /etc/resolv.conf: $RESOLV_NS"

# 5. Overall Summary
echo ""
echo "=== 🏁 Summary ==="
if [ -n "$LOKI_PID" ] && echo "$WIFI_DNS" | grep -q "127.0.0.1"; then
  echo "🟢 Lokinet is ACTIVE and handling all System DNS exclusively."
  echo "   • .loki domains route via Lokinet"
  echo "   • Internet domains route securely via NextDNS"
elif [ -n "$LOKI_PID" ]; then
  echo "🟡 Lokinet is RUNNING, but System DNS is NOT bound to 127.0.0.1 (run 'Start Lokinet' to bind)."
elif echo "$WIFI_DNS" | grep -q "127.0.0.1"; then
  echo "🔴 CRITICAL: System DNS is pointing to 127.0.0.1, but Lokinet daemon is NOT running!"
  echo "   Your DNS is currently broken. Run 'Stop Lokinet' to revert back to default DHCP."
else
  echo "⚪ Lokinet is INACTIVE. System is using Default DHCP."
fi
