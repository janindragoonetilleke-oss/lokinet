# Lokinet (macOS Apple Silicon Native)

[![Platform](https://img.shields.io/badge/Platform-macOS%20Apple%20Silicon%20(arm64)-000000?logo=apple)](https://apple.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Protocol](https://img.shields.io/badge/Protocol-LLARP%20Layer%203%20Onion%20Routing-purple)](https://oxen.io)

**Lokinet** is the reference implementation of **LLARP** (*Low Latency Anonymous Routing Protocol*), a decentralized layer-3 onion routing network. Unlike traditional anonymity networks that only operate at layer 4 (such as Tor's SOCKS proxy), Lokinet handles IP packets directly, allowing any UDP, TCP, or ICMP traffic to travel anonymously across a multi-hop, Sybil-resistant mesh of Oxen Service Nodes.

This repository features **native Apple Silicon (`arm64`) compilation**, resolved macOS API compatibility, modern dependency fixes, secure NextDNS integration, and custom Raycast automation scripts.

---

## Features in this Fork

- **Native ARM64 Compilation**: Fully optimized and compiled for Apple Silicon Macs (M1/M2/M3/M4) without Rosetta emulation.
- **Standalone CLI Daemon (`lokinet-daemon`)**: Direct command-line binary built from `daemon/lokinet.cpp` that runs natively in terminal and background services.
- **Interactive Control Utility (`lokinet-cntrl`)**: Native CLI utility for querying real-time router status, paths, sessions, and bandwidth.
- **Repaired Static Dependency Engine**:
  - Switched outdated and failing upstream mirrors to reliable GNU FTP archives.
  - Patched `ExternalProject_Add` build targets for seamless compatibility with Ninja on Darwin.
  - Fixed Unbound entropy resolution under macOS 11+.
  - Resolved Swift architecture compiler flags that previously forced `x86_64`.
- **Integrated NextDNS DoH Support**: Configured to bind system DNS to `127.0.0.1:53` for resolving `.loki` domains while routing all clearnet lookups through an encrypted NextDNS DNS-over-HTTPS (DoH) proxy.
- **Raycast Integration**: Included Raycast Script Commands for 1-click startup, graceful teardown, and live status reporting.

---

## Architecture Overview

```
                          ┌────────────────────────┐
                          │   macOS Applications   │
                          └───────────┬────────────┘
                                      │ DNS Queries (127.0.0.1:53)
                                      ▼
                        ┌────────────────────────────┐
                        │       Lokinet Daemon       │
                        │    (Embedded Resolver)     │
                        └──────┬──────────────┬──────┘
             .loki Domains     │              │ Clearnet Domains
             ┌─────────────────┘              └────────────────┐
             ▼                                                 ▼
┌─────────────────────────┐                     ┌─────────────────────────────┐
│  Lokinet Onion Network  │                     │   NextDNS DoH Proxy / TLS   │
│  (Multi-Hop SNApp Mesh) │                     │     (127.0.0.1:5354)        │
└─────────────────────────┘                     └──────────────┬──────────────┘
                                                               │ Encrypted DoH
                                                               ▼
                                                ┌─────────────────────────────┐
                                                │      NextDNS Profile        │
                                                │       (Account: ff6bd9)     │
                                                └─────────────────────────────┘
```

---

## Building on macOS (Apple Silicon)

### Prerequisites

Install build tooling via [Homebrew](https://brew.sh):

```bash
brew install cmake ninja fmt libuv imagemagick
```

### Configure and Build

1. Clone repository with submodules:
   ```bash
   git clone --recursive https://github.com/janindragoonetilleke-oss/lokinet.git
   cd lokinet
   ```

2. Generate build files:
   ```bash
   cmake -B build -G Ninja \
     -DCMAKE_BUILD_TYPE=Release \
     -DBUILD_STATIC_DEPS=ON \
     -DLOKINET_GUI=OFF \
     -DCODESIGN=OFF
   ```

3. Build the executables:
   ```bash
   ninja -C build lokinet-daemon lokinet-cntrl
   ```

4. Verify native ARM64 architecture:
   ```bash
   file build/daemon/lokinet-daemon
   # Expected output: Mach-O 64-bit executable arm64
   ```

---

## Configuration & DNS Integration

### 1. Initialize Configuration

Generate default client configuration files:

```bash
./build/daemon/lokinet-daemon -g --config ~/.lokinet/lokinet.ini
cp contrib/bootstrap/mainnet.signed ~/.lokinet/bootstrap.signed
```

### 2. Configure NextDNS as Upstream

Edit `~/.lokinet/lokinet.ini` under the `[dns]` section:

```ini
[dns]
# Bind to local port 53 for handling system DNS
bind=127.0.0.1:53

# Enable Lokinet's embedded DNS server
l3-intercept=false

# Secure Upstream NextDNS
# Primary: Local NextDNS DoH encrypted proxy
upstream=127.0.0.1:5354
# Fallbacks: NextDNS Anycast resolvers
upstream=45.90.28.0:53
upstream=45.90.30.0:53
```

### 3. Bind System DNS Exclusively to Lokinet

Run the automated configuration script:

```bash
sudo ./setup-dns.sh
```

This script:
- Reconfigures local `dnsproxy` to listen on port `5354`, leaving port `53` available for Lokinet.
- Binds macOS Wi-Fi DNS to `127.0.0.1`.
- Populates `/etc/resolv.conf` with `nameserver 127.0.0.1`.
- Flushes the macOS DNS cache.

---

## Raycast Scripts

Pre-configured Raycast Script Commands are located in `raycast/` and symlinked to `~/.raycast/lokinet/`:

| Command | Icon | Mode | Description |
|---|---|---|---|
| **Start Lokinet** | 🧅 | `fullOutput` | Moves NextDNS proxy to 5354, launches `lokinet-daemon`, binds system DNS to 127.0.0.1, and tests resolution. |
| **Stop Lokinet** | 🛑 | `fullOutput` | Gracefully shuts down `lokinet-daemon`, reverts Wi-Fi DNS to DHCP default, and flushes cache. |
| **Lokinet Status** | 📊 | `fullOutput` | Live dashboard showing daemon process health, port 53 binding, NextDNS DoH status, and active nameservers. |

### Adding to Raycast:
1. Open Raycast Preferences (`Cmd + ,`).
2. Go to **Extensions** → **Script Commands**.
3. Click **Add Directories** and add `/Users/janindra/lokinet/raycast`.

---

## Traffic Routing Modes

Lokinet supports two operation models:

### 1. Split / SNApp Mode (Default)
- **`.loki` domains**: Encrypted and routed end-to-end through the Lokinet onion network.
- **Clearnet domains (`.com`, `.org`, etc.)**: DNS resolved via encrypted NextDNS DoH; standard IP payload connects directly through your ISP connection for full bandwidth and low latency.

### 2. Full VPN / Exit Node Mode
To route **all internet traffic** through Lokinet (so external websites see the Exit Node's IP address instead of your real ISP IP), configure an exit node in `~/.lokinet/lokinet.ini`:

```ini
[exit]
# Route all clearnet traffic through a chosen exit node
reserved-range=exit.loki

# If the exit node requires an authentication token:
# auth=exit.loki:auth_code_here
```

---

## License

Lokinet is free software licensed under the **GNU General Public License v3.0 (GPL-3.0)**.  
See [LICENSE](LICENSE) for full terms.

```
Copyright © 2018-2022 The Oxen Project
Copyright © 2018-2022 Jeff Becker
Copyright © 2018-2020 Rick V.
```
