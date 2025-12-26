# MikroTik Dual WAN Load Balancing + Failover | RouterOS v7

[![MikroTik](https://img.shields.io/badge/MikroTik-RouterOS%20v7-blue)](https://mikrotik.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Production-ready **MikroTik RouterOS v7** configuration for **Dual WAN Load Balancing** and **Automatic Failover**. Combines **PCC (Per Connection Classifier)** with **Recursive Routing** for enterprise-grade internet redundancy and bandwidth aggregation.

Perfect for home offices, small businesses, and anyone needing reliable internet with multiple ISP connections.

---

## 🚀 Features

### Load Balancing
- ✅ **PCC Load Balancing** - Distributes traffic across both WANs with configurable ratio (1:1, 2:1, 3:1, etc.)
- ✅ **Dynamic Hashing** - Uses `both-addresses-and-ports` hashing by default for maximum bandwidth aggregation across many connections.
- ✅ **Bandwidth Aggregation** - Combine speeds from multiple ISPs (e.g., 500Mbps + 100Mbps = 600Mbps total)
- ✅ **Per-Connection Distribution** - Each TCP/UDP connection uses one ISP, preventing packet reordering
- ✅ **Local Traffic Bypass** - Built-in bypass for LAN, WAN subnets, and RouterOS services (DNS/NTP) to ensure stable routing.

### Automatic Failover
- ✅ **Dual-IP Monitoring** - Monitors TWO reliable IPs (e.g., 1.1.1.1 & 8.8.8.8) for EACH ISP
- ✅ **Strict Source-Binding** - Uses `src-address` binding + Mangle Output rules to guarantee monitor pings use the correct WAN, eliminating "expected end of command" syntax errors common in v7.
- ✅ **Self-Healing Startup** - Intelligent logic detects missing variables (e.g., due to race conditions) and automatically reloads the configuration, eliminating "Interface () NOT RUNNING" boot errors.
- ✅ **Smart Detection** - Failover triggers ONLY if **BOTH** monitor IPs fail
- ✅ **Comprehensive Cleanup** - Automatically clears stuck connections AND disables ALL ISP-specific mangle rules during failover (PCC, Return, DNS, NTP)
- ✅ **Cross-ISP Failover** - Traffic marked for ISP1 can fail over to ISP2 and vice versa
- ✅ **Failsafe Routes** - High-distance (250+) static routes provide a "last resort" connection to prevent total blackout if variables are misconfigured.
- ✅ **Email Notifications** - Configurable alerts for long-duration outages (e.g., 1h, 6h) via Email/Gmail.

### Network Configuration
- ✅ **LAN Bridge** - Automatically creates bridge with ether3, ether4, ether5 for LAN connectivity
- ✅ **DHCP Server** - Automatic IP assignment for LAN clients
- ✅ **Variable-Driven** - All IPs, subnets, and interfaces defined in configuration variables
- ✅ **Script-Based Import** - Uses robust "Quoted String" source definitions to bypass RouterOS import parser limitations.

### Security & Optimization
- ✅ **WAN-Aware NAT** - Restricted masquerade to `out-interface-list=WAN` to prevent NAT mismatches and asymmetric routing.
- ✅ **Correct Mangle Flow** - Uses `action=return` for local bypass rules in the `output` chain, ensuring correct traverse for router-originated traffic.
- ✅ **IPv6 Disabled** - Explicitly disables IPv6 to prevent firewall bypass (since this config is IPv4 only).
- ✅ **RP-Filter Hardening** - Sets `rp-filter=loose` to ensure asymmetric Dual-WAN traffic is not dropped by the kernel.
- ✅ **Service Hardening** - Disables Telnet, FTP, and SSH (Winbox & WebFig restricted to LAN)
- ✅ **Memory Monitoring** - Automatic alerts for high memory usage
- ✅ **v7 Stability Hardening** - Uses "Local Variable Locking" and "Self-Baking" scripts to prevent environment crashes common in RouterOS v7.

---

## 📋 Prerequisites

- **Router**: MikroTik running RouterOS **v7.20** or higher
- **Internet**: Two ISP connections (cable, fiber, DSL, LTE, etc.)
- **Ports**: At least 5 ethernet ports (2 WAN + 3 LAN, or more)
- **Network**: Basic understanding of IP addressing and RouterOS
- **Access**: Winbox or SSH access to router

**Tested on**: RouterOS v7.20+, RB750Gr3, E50UG

---

## 🎯 Quick Start

### 1. Download Configuration
```bash
wget https://raw.githubusercontent.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/main/mikrotik-dual-wan.rsc
```

### 2. Edit Variables
Open `mikrotik-dual-wan.rsc` and configure your network:

```routeros
:local lISP1Name "Primary-ISP"
:local lISP2Name "Backup-ISP"
:local lPreferredISP "ISP1"

:local lWAN1Interface "ether1"
:local lWAN1Address "192.168.0.3"
:local lWAN1Gateway "192.168.0.1"
:local lWAN1Subnet "192.168.0.0/24"

:local lWAN2Interface "ether2"
:local lWAN2Address "192.168.20.3"
:local lWAN2Gateway "192.168.20.1"
:local lWAN2Subnet "192.168.20.0/24"

:local lLANInterface "bridge-lan"
:local lLANSubnet "192.168.100.0/24"
:local lLANAddress "192.168.100.1/24"
:local lLANGateway "192.168.100.1"
:local lLANPort1 "ether3"
:local lLANPort2 "ether4"
:local lLANPort3 "ether5"

:local lISP1MonitorIP1 "1.1.1.1"
:local lISP1MonitorIP2 "8.8.8.8"
:local lISP2MonitorIP1 "8.8.4.4"
:local lISP2MonitorIP2 "1.0.0.1"

:local lFailureThreshold 2
:local lCheckInterval "10s"
:local lLBRatio1 1
:local lLBRatio2 1

# Email Notifications
:local lNotifyDelay1 60;   # Alert 1: 1 Hour (in minutes)
:local lNotifyDelay2 360;  # Alert 2: 6 Hours (in minutes)
:local lEmailEnable true
:local lEmailAddress "your-email@gmail.com"
:local lEmailPassword "your-app-password"
```

### 3. Upload to Router
- Open **Winbox** → **Files** → Drag and drop `mikrotik-dual-wan.rsc`

### 4. Import Configuration
> [!WARNING]
> **This script will RESET your router configuration!**
> It clears existing firewall rules, mangle rules, NAT, and routes to ensure a clean setup.
> The script is fully automated and will execute immediately upon import.

```routeros
/import mikrotik-dual-wan.rsc
```

### 5. Reboot Router
```routeros
/system reboot
```

### 6. Verify Configuration
```routeros
# Check routes are active
/ip route print detail where dst-address=0.0.0.0/0

# Check scheduler is running
/system scheduler print detail where name=dual-ip-failover

# Monitor failover status (live)
/log print follow where message~"FAILOVER"

# Check ISP status
:global ISP1Status; :put $ISP1Status
:global ISP2Status; :put $ISP2Status

# Verify DHCP server is running
/ip dhcp-server print

# Test connectivity
/tool ping 1.1.1.1 count=100
```

---

## 🔧 How It Works

### PCC Load Balancing Explained
```
Client Request → MikroTik Router → PCC Classifier
                                   ├─ Hash 0 → ISP1 (50% traffic)
                                   └─ Hash 1 → ISP2 (50% traffic)
```

- **Per Connection**: Each connection (web page, download, stream) uses ONE ISP
- **Dynamic Distribution**: Uses `both-addresses-and-ports` for granular balancing (recommended for bandwidth aggregation).
- **No Packet Reordering**: Prevents TCP performance issues

### Dual-IP Failover Logic
The script uses a dedicated scheduler to monitor **two** reliable IPs (e.g., Cloudflare 1.1.1.1 and Google 8.8.8.8) for *each* ISP.

```
Router → Ping 1.1.1.1 via ISP1 → ✅ UP
      → Ping 8.8.8.8 via ISP1 → ❌ DOWN
      RESULT: ISP1 is UP (At least one monitor is reachable)

Router → Ping 1.1.1.1 via ISP1 → ❌ DOWN
      → Ping 8.8.8.8 via ISP1 → ❌ DOWN
      RESULT: ISP1 is DOWN (Both monitors failed) → Failover to ISP2
```

**Why this approach?**
- **Prevents False Positives**: A single packet drop or one DNS server outage won't trigger a disruptive failover.
- **Robustness**: Requires total loss of connectivity to multiple major providers to declare an ISP down.
- **Automatic Recovery**: Routes are re-enabled automatically when at least one monitor IP responds.

### Connection Cleanup on Failover
When ISP1 fails:
1. Scheduler detects failure (both IPs down for 3 consecutive checks)
2. Script disables ISP1 routes and clears `ISP1_conn` connections
3. Clients reconnect automatically via ISP2
4. **Result**: 10-30 second interruption instead of 2-5 minute hang

---

## 📊 Performance & Testing

### Speed Test Results
Multi-connection speed tests (Speedtest.net, OpenSpeedTest) will show **combined bandwidth**:

| ISP1 Speed | ISP2 Speed | Combined Result |
|------------|------------|-----------------|
| 500 Mbps   | 100 Mbps   | ~600 Mbps       |
| 300 Mbps   | 300 Mbps   | ~600 Mbps       |
| 100 Mbps   | 50 Mbps    | ~150 Mbps       |

**Why?** These tools use 6-16 parallel connections, which get distributed across both ISPs.

### Failover Speed
- **Detection Time**: 3-5 seconds (configurable)
- **Recovery Time**: 10-30 seconds for most applications
- **Packet Loss**: Minimal (only during transition)

### Compatibility
✅ **Works perfectly with**:
- Web browsing (HTTP/HTTPS)
- Video streaming (YouTube, Netflix, Twitch)
- Downloads (multi-threaded)
- Gaming (single connection = single ISP, no lag)
- General internet use

⚠️ **Temporary interruption during failover**:
- VoIP calls (WhatsApp, Zoom) - will drop and need redial
- Live streams - 10-30 second buffer
- Long-running SSH/VPN sessions

---

## ⚙️ Customization

### Change Load Balance Ratio
Favor faster ISP for better utilization:
```routeros
:local lLBRatio1 3  # ISP1 gets 75% of connections
:local lLBRatio2 1  # ISP2 gets 25% of connections
```

### Change Monitor IPs
Use different DNS servers for monitoring:
```routeros
:local lISP1MonitorIP1 "1.1.1.1"    # Cloudflare
:local lISP1MonitorIP2 "8.8.8.8"    # Google
:local lISP2MonitorIP1 "8.8.4.4"    # Google
:local lISP2MonitorIP2 "1.0.0.1"    # Cloudflare
```

### Adjust Failover Sensitivity
```routeros
:local lCheckInterval "10s"    # How often to check (default: 10s)
:local lFailureThreshold 2     # Consecutive failures before marking DOWN
```

### Change DHCP Pool Range
Adjust the number of DHCP clients:
```routeros
```routeros
# You can modify the pool range in the script where 'lan-dhcp-pool' is defined
# Default: 192.168.100.100-192.168.100.200
```

### Increase DNS Cache
If you have extra memory:
```routeros
/ip dns set cache-size=32768KiB  # 32MB cache
```

### Prefer One ISP Over Another
```routeros
:local lPreferredISP "ISP1"  # or "ISP2"
```

### Configure Email Alerts
Receive notifications if an ISP stays down for too long:
```routeros
:local lNotifyDelay1 60    # First alert after 60 minutes
:local lNotifyDelay2 360   # Critical alert after 6 hours
:local lEmailEnable true   # Enable/Disable emails
:local lEmailAddress "your-email@gmail.com"
:local lEmailPassword "your-app-password"
```
*Note: Uses GMAIL settings (smtp.gmail.com:587) by default. To use another provider, edit the `/tool e-mail set` command at the bottom of the script.*
```

---

## 🛠️ Troubleshooting

### Routes Show Inactive
```routeros
/ip route print detail where dst-address=0.0.0.0/0
```
- Look for flags: `DAc` (active) or `Is` (inactive)
- Check if monitor IPs are reachable: `/tool ping 1.1.1.1`

### No Load Balancing
```routeros
/ip firewall connection print where connection-mark~"ISP"
```
- Should show mix of `ISP1_conn` and `ISP2_conn`
- If empty, check mangle rules: `/ip firewall mangle print`
- **Note**: The "Catch-All" output rule (Line ~245) might mask configuration errors by forcing unmarked traffic to ISP1.

### Failover Not Working

**Check the scheduler logs** (netwatch has been removed due to false positives):
```routeros
# View recent failover events
/log print where message~"FAILOVER"

# Live monitoring
/log print follow where message~"FAILOVER"

# Check ISP status
:global ISP1Status; :put $ISP1Status
:global ISP2Status; :put $ISP2Status

# Test pings manually with interface binding
/ping 1.1.1.1 interface=ether1 count=5
/ping 8.8.8.8 interface=ether1 count=5
```

**Expected log messages:**
- `[FAILOVER] ISP1 DOWN - Both monitors failed` - ISP has failed
- `[FAILOVER] ISP1 UP - Recovered` - ISP recovered

**Remember**: BOTH monitor IPs must fail to trigger failover (by design)

### Speed Test Shows Only One ISP
- Normal for single-connection tests
- Use multi-connection speed tests (Speedtest.net, OpenSpeedTest)

---

## 🔐 Security Considerations

### What's Included
- ✅ Firewall blocks WAN→Router access
- ✅ ICMP rate limiting (prevents ping floods)
- ✅ Drops invalid connections
- ✅ **Winbox & WebFig restricted to LAN only** (uses your configured `$LANSubnet`)
- ✅ All insecure services disabled

### Additional Recommendations
1. **Change default credentials**
2. **Enable firewall logging**: `/ip firewall filter set [find] log=yes`
3. **Restrict Winbox IP**: Already configured to LAN only
4. **Enable HTTPS for Winbox**: Certificate setup recommended
5. **Regular backups**: Schedule automatic backups

---

## 📚 Use Cases

### Home Office
- **Scenario**: Primary fiber + backup LTE
- **Benefit**: Never lose internet during work calls/meetings

### Small Business  
- **Scenario**: Two cable ISPs for redundancy
- **Benefit**: Combine bandwidth + automatic failover

### Remote Location
- **Scenario**: Satellite + 4G/5G backup
- **Benefit**: Always-on connectivity in rural areas

### Content Creator
- **Scenario**: Two fiber connections
- **Benefit**: Upload large files faster with combined bandwidth

### Gaming + Streaming
- **Scenario**: Low-latency fiber + high-bandwidth cable
- **Benefit**: Game on one ISP, stream on another

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test on actual hardware
4. Submit pull request with clear description

### Reporting Issues
Include:
- RouterOS version
- Router model
- Configuration variables used
- Error messages from `/log print`

---

## 📄 License

MIT License - Feel free to use, modify, and distribute.

---

## 🙏 Credits

- **MikroTik Community**: For extensive documentation
- **RouterOS Wiki**: Best practices and examples
- **Contributors**: Everyone who tested and provided feedback

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/issues)
- **Discussions**: [GitHub Discussions](https://github.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/discussions)
- **MikroTik Forum**: [forum.mikrotik.com](https://forum.mikrotik.com)

---

## 🔗 Related Projects

- [MikroTik Scripts Collection](https://github.com/topics/mikrotik-scripts)
- [RouterOS Automation](https://github.com/topics/routeros)
- [Network Monitoring Tools](https://github.com/topics/network-monitoring)

---

## ⭐ Star History

If this project helped you, please consider giving it a star! ⭐

---

**Keywords**: MikroTik dual WAN, RouterOS load balancing, PCC failover, multi-ISP setup, bandwidth aggregation, internet redundancy, automatic failover, MikroTik script, RouterOS v7, network redundancy, ISP failover, connection tracking, recursive routing, enterprise networking, home office internet, small business networking

---

Made with ❤️ for the MikroTik community
