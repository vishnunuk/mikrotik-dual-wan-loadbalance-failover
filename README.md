# MikroTik Dual WAN Load Balancing + Failover | RouterOS v7

[![MikroTik](https://img.shields.io/badge/MikroTik-RouterOS%20v7-blue)](https://mikrotik.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Production-ready **MikroTik RouterOS v7** configuration for **Dual WAN Load Balancing** and **Automatic Failover**. Combines **PCC (Per Connection Classifier)** with **Recursive Routing** for enterprise-grade internet redundancy and bandwidth aggregation.

Perfect for home offices, small businesses, and anyone needing reliable internet with multiple ISP connections.

---

## 🚀 Features

### Load Balancing
- ✅ **PCC Load Balancing** - Distributes traffic across both WANs with configurable ratio (1:1, 2:1, 3:1, etc.)
- ✅ **Session Sticky** - Uses `both-addresses-and-ports` hashing to keep HTTPS/banking sessions on same connection
- ✅ **Bandwidth Aggregation** - Combine speeds from multiple ISPs (e.g., 500Mbps + 100Mbps = 600Mbps total)
- ✅ **Per-Connection Distribution** - Each TCP/UDP connection uses one ISP, preventing packet reordering

### Automatic Failover
- ✅ **Recursive Routing** - Monitors upstream DNS servers (Cloudflare, Google) instead of just gateway
- ✅ **Instant Detection** - Detects ISP failures in 3-5 seconds
- ✅ **Connection Cleanup** - Automatically clears stuck connections during failover
- ✅ **Cross-ISP Failover** - Traffic marked for ISP1 can fail over to ISP2 and vice versa
- ✅ **Dual Monitors** - Two monitoring IPs per ISP for redundant health checks

### Security & Optimization
- ✅ **Stateful Firewall** - Drop invalid connections, rate-limit ICMP
- ✅ **Service Hardening** - Disables insecure services (Telnet, FTP)
- ✅ **Large DNS Cache** - 8MB DNS cache (configurable up to 64MB)
- ✅ **WAN Access Blocking** - Prevents external access to router management
- ✅ **Memory Monitoring** - Automatic alerts for high memory usage

---

## 📋 Prerequisites

- **Router**: MikroTik running RouterOS **v7.x** or higher
- **Internet**: Two ISP connections (cable, fiber, DSL, LTE, etc.)
- **Network**: Basic understanding of IP addressing and RouterOS
- **Access**: Winbox or SSH access to router

**Tested on**: RB750Gr3, hAP ac², CCR series

---

## 🎯 Quick Start

### 1. Download Configuration
```bash
wget https://raw.githubusercontent.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/main/mikrotik-dual-wan.rsc
```

### 2. Edit Variables
Open `mikrotik-dual-wan.rsc` and configure your network:

```routeros
:global WAN1Interface "ether1"      # Your primary WAN interface
:global WAN1Gateway "192.168.0.1"   # ISP1 gateway IP
:global WAN2Interface "ether2"      # Your secondary WAN interface  
:global WAN2Gateway "192.168.20.1"  # ISP2 gateway IP
:global LANInterface "ether5"       # Your LAN interface

# Load balance ratio (1:1 = equal, 2:1 = favor ISP1)
:global LBRatio1 1
:global LBRatio2 1
```

### 3. Upload to Router
- Open **Winbox** → **Files** → Drag and drop `mikrotik-dual-wan.rsc`

### 4. Import Configuration
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

# Check ISP monitoring status
/tool netwatch print

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

### Recursive Routing Failover
```
Router → Ping 1.1.1.1 via ISP1 → ✅ UP → Route Active
      → Ping 8.8.8.8 via ISP2 → ✅ UP → Route Active

Router → Ping 1.1.1.1 via ISP1 → ❌ DOWN → Route Inactive
      → Ping 8.8.8.8 via ISP2 → ✅ UP → All traffic via ISP2
```

**Why recursive routing?**
- Detects ISP routing issues even if physical link is up
- More reliable than simple gateway ping
- Monitors real internet connectivity

### Connection Cleanup on Failover
When ISP1 fails:
1. Netwatch detects failure (3-5 seconds)
2. Script clears all `ISP1_conn` connections from tracking table
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
:global CheckTimeout "800ms"  # Timeout for ping (default: 800ms)
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
```routeros
/tool netwatch print
/log print where topics~"error|warning"
```
- Check if monitors are up
- Review logs for failover events

### Speed Test Shows Only One ISP
- Normal for single-connection tests
- Use multi-connection speed tests (Speedtest.net, OpenSpeedTest)

---

## 🔐 Security Considerations

### What's Included
- ✅ Firewall blocks WAN→Router access
- ✅ ICMP rate limiting (prevents ping floods)
- ✅ Drops invalid connections
- ✅ Winbox restricted to LAN only
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
