# MikroTik Dual WAN Load Balancing + Failover | RouterOS v7

[![MikroTik](https://img.shields.io/badge/MikroTik-RouterOS%20v7-blue)](https://mikrotik.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Production-ready **MikroTik RouterOS v7** configuration for **Dual WAN Load Balancing** and **Automatic Failover**. Combines **PCC (Per Connection Classifier)** with **Recursive Routing** for enterprise-grade internet redundancy and bandwidth aggregation.

Perfect for home offices, small businesses, and anyone needing reliable internet with multiple ISP connections.

---

## 🚀 Features

### Load Balancing
- ✅ **PCC Load Balancing** - Distributes traffic across both WANs with configurable ratio (1:1, 2:1, 3:1, etc.)
- ✅ **Session Sticky** - Uses `both-addresses` hashing (ignoring ports) to ensure HTTPS/banking sites stay on the same ISP
- ✅ **Bandwidth Aggregation** - Combine speeds from multiple ISPs (e.g., 500Mbps + 100Mbps = 600Mbps total)
- ✅ **Per-Connection Distribution** - Each TCP/UDP connection uses one ISP, preventing packet reordering

### Automatic Failover
- ✅ **Dual-IP Monitoring** - Monitors TWO reliable IPs (e.g., 1.1.1.1 & 8.8.8.8) for EACH ISP
- ✅ **Smart Detection** - Failover triggers ONLY if **BOTH** monitor IPs fail, preventing false alarms
- ✅ **Instant Detection** - Detects ISP failures in ~3-5 seconds (configurable)
- ✅ **Connection Cleanup** - Automatically clears stuck connections during failover
- ✅ **Cross-ISP Failover** - Traffic marked for ISP1 can fail over to ISP2 and vice versa
- ✅ **Monitor IP Bypass** - Forces monitor traffic to use the main routing table, preventing load-balancing conflicts
- ✅ **Error Handling** - Graceful handling of disconnected WANs, no scheduler crashes

### Network Configuration
- ✅ **LAN Bridge** - Automatically creates bridge with ether3, ether4, ether5 for LAN connectivity
- ✅ **DHCP Server** - Automatic IP assignment for LAN clients (192.168.100.100-200 by default)
- ✅ **Variable-Driven** - All IPs, subnets, and interfaces defined in configuration variables
- ✅ **No Hardcoded Values** - Easy to customize for different network setups

### Security & Optimization
- ✅ **Stateful Firewall** - Drop invalid connections, rate-limit ICMP
- ✅ **Service Hardening** - Disables Telnet, FTP, SSH, and WebFig (Winbox only by default)
- ✅ **Large DNS Cache** - 32MB DNS cache (configurable)
- ✅ **WAN Access Blocking** - Prevents external access to router management
- ✅ **Memory Monitoring** - Automatic alerts for high memory usage

---

## 📋 Prerequisites

- **Router**: MikroTik running RouterOS **v7.2** or higher
- **Internet**: Two ISP connections (cable, fiber, DSL, LTE, etc.)
- **Ports**: At least 5 ethernet ports (2 WAN + 3 LAN, or more)
- **Network**: Basic understanding of IP addressing and RouterOS
- **Access**: Winbox or SSH access to router

**Tested on**: RouterOS v7.2+, RB750Gr3, E50UG

---

## 🎯 Quick Start

### 1. Download Configuration
```bash
wget https://raw.githubusercontent.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/main/mikrotik-dual-wan.rsc
```

### 2. Edit Variables
Open `mikrotik-dual-wan.rsc` and configure your network:

```routeros
:global ISP1Name "Primary-ISP"      # Name for ISP1
:global ISP2Name "Backup-ISP"       # Name for ISP2
:global PreferredISP "ISP1"         # Preferred ISP for failover (ISP1 or ISP2)

:global WAN1Interface "ether1"      # Your primary WAN interface
:global WAN1Address "192.168.0.3"   # Your static IP on WAN1
:global WAN1Gateway "192.168.0.1"   # ISP1 gateway IP
:global WAN1Subnet "192.168.0.0/24" # WAN1 subnet

:global WAN2Interface "ether2"      # Your secondary WAN interface
:global WAN2Address "192.168.20.3"  # Your static IP on WAN2
:global WAN2Gateway "192.168.20.1"  # ISP2 gateway IP
:global WAN2Subnet "192.168.20.0/24" # WAN2 subnet

:global LANInterface "bridge-lan"   # LAN bridge interface
:global LANPort1 "ether3"           # LAN port 1
:global LANPort2 "ether4"           # LAN port 2
:global LANPort3 "ether5"           # LAN port 3
:global LANSubnet "192.168.100.0/24" # Your LAN subnet
:global LANAddress "192.168.100.1/24" # LAN gateway address
:global LANGateway "192.168.100.1"   # LAN gateway IP
:global DHCPPoolStart "192.168.100.100" # DHCP pool start
:global DHCPPoolEnd "192.168.100.200"   # DHCP pool end

# Load balance ratio (1:1 = equal, 2:1 = favor ISP1)
:global LBRatio1 1
:global LBRatio2 1
```

### 3. Upload to Router
- Open **Winbox** → **Files** → Drag and drop `mikrotik-dual-wan.rsc`

### 4. Import Configuration
> [!WARNING]
> **This script will RESET your router configuration!**
> It clears existing firewall rules, mangle rules, NAT, and routes to ensure a clean setup.
> Make sure to backup your current configuration before proceeding.

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
:put [/global get ISP1Status]
:put [/global get ISP2Status]

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
- **Sticky Sessions**: Same source+destination = same ISP every time
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
:global LBRatio1 3  # ISP1 gets 75% of connections
:global LBRatio2 1  # ISP2 gets 25% of connections
```

### Change Monitor IPs
Use different DNS servers for monitoring:
```routeros
:global ISP1MonitorIP1 "1.1.1.1"    # Cloudflare
:global ISP1MonitorIP2 "8.8.8.8"    # Google
:global ISP2MonitorIP1 "8.8.4.4"    # Google
:global ISP2MonitorIP2 "1.0.0.1"    # Cloudflare
```

### Adjust Failover Sensitivity
```routeros
:global CheckInterval "3s"    # How often to check (default: 3s)
```

### Change DHCP Pool Range
Adjust the number of DHCP clients:
```routeros
:global DHCPPoolStart "192.168.100.50"   # Start from .50
:global DHCPPoolEnd "192.168.100.250"    # End at .250 (200 addresses)
```

### Increase DNS Cache
If you have extra memory:
```routeros
/ip dns set cache-size=32768KiB  # 32MB cache
```

### Prefer One ISP Over Another
```routeros
:global PreferredISP "ISP1"  # or "ISP2"
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

### Failover Not Working

**Check the scheduler logs** (netwatch has been removed due to false positives):
```routeros
# View recent failover events
/log print where message~"FAILOVER"

# Live monitoring
/log print follow where message~"FAILOVER"

# Check ISP status
:put [/global get ISP1Status]
:put [/global get ISP2Status]

# Test pings manually with source address
/ping 1.1.1.1 src-address=192.168.0.3 count=5
/ping 8.8.8.8 src-address=192.168.0.3 count=5
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
- ✅ **Winbox restricted to LAN only** (uses your configured `$LANSubnet`)
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
