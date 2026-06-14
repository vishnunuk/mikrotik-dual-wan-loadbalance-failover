# MikroTik Dual WAN Load Balancing and Failover (RouterOS v7)

[![MikroTik](https://img.shields.io/badge/MikroTik-RouterOS%20v7-blue)](https://mikrotik.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A production-ready MikroTik RouterOS v7 configuration for Dual WAN Load Balancing and Automatic Failover. This configuration combines Per Connection Classifier (PCC) with Policy-Based Routing (PBR) to provide reliable internet redundancy and bandwidth aggregation.

Suitable for environments requiring high availability across multiple ISP connections.

---

## Features

### Load Balancing
- **PCC Load Balancing**: Distributes traffic across both WANs with configurable ratios (e.g., 1:1, 2:1, 3:1).
- **Dynamic Hashing**: Utilizes `both-addresses-and-ports` hashing by default for optimal bandwidth aggregation across multiple connections.
- **Bandwidth Aggregation**: Combines throughput from multiple ISPs.
- **Per-Connection Distribution**: Ensures each TCP/UDP connection maintains a single ISP route, preventing packet reordering.
- **Local Traffic Bypass**: Includes built-in bypass rules for LAN, WAN subnets, and RouterOS services (DNS/NTP) to ensure stable routing.

### Automatic Failover
- **Dual-IP Monitoring**: Monitors two distinct IPs for each ISP to verify connectivity.
- **Conflict-Free**: Employs independent monitor IPs (e.g., 45.90.28.0, 9.9.9.9) separate from primary DNS (1.1.1.1, 8.8.8.8) to prevent routing loops.
- **Strict Source-Binding**: Uses `src-address` binding and Mangle Output rules to ensure monitor pings utilize the correct WAN interface.
- **Self-Healing Startup**: Contains logic to detect missing variables during boot and automatically reloads the configuration.
- **Boot Stabilization**: Includes a dedicated startup enabler that waits 90 seconds after boot before activating failover routines, preventing false positives during interface initialization.
- **Smart Detection**: Triggers failover only if both monitor IPs fail on a given connection.
- **Comprehensive Cleanup**: Terminates stalled connections with a 500ms stabilization delay, and disables PCC classification rules while preserving return traffic routing.
- **MSS Clamping**: Clamps TCP MSS to 1400 bytes for reliable operation across PPPoE, LTE, and VPN links.
- **Cross-ISP Failover**: Permits traffic marked for ISP1 to fail over to ISP2, and vice versa.
- **Failsafe Routes**: Incorporates high-distance (250+) static routes to prevent total connectivity loss in case of misconfiguration.
- **Email Notifications**: Supports configurable alerts (1h, 6h, Daily) and recovery notifications.
- **Security Hardening**: Implements strict firewall rules restricting management access (WinBox/SSH) to the LAN interface. MAC WinBox is similarly restricted.

### Network Configuration
- **LAN Bridge**: Automatically provisions a bridge utilizing ether3, ether4, and ether5.
- **DHCP Server**: Provides automatic IP assignment for LAN clients.
- **DNS and NTP**: Automatically provisions DNS caching (32MB) and connects to reliable NTP servers (Cloudflare, Google, NIST) for accurate system logging.
- **Variable-Driven**: Manages IPs, subnets, and interfaces via configuration variables.
- **Script-Based Import**: Uses quoted string source definitions to ensure reliable import parsing.

### Security & Optimization
- **WAN-Aware NAT**: Restricts masquerade rules to `out-interface-list=WAN` to prevent NAT mismatches and asymmetric routing.
- **Correct Mangle Flow**: Uses `action=return` for local bypass rules in the `output` chain.
- **IPv6 Disabled**: Explicitly disables IPv6 to prevent firewall bypass (configuration is IPv4 only).
- **RP-Filter Hardening**: Sets `rp-filter=loose` to accommodate asymmetric Dual-WAN traffic.
- **Service Hardening**: Disables Telnet, FTP, and SSH. Restricts Winbox and WebFig to the LAN.
- **Memory Monitoring**: Includes automated alerts for high memory utilization.
- **v7 Stability Hardening**: Utilizes local variable locking to prevent environment instability.

---

## Prerequisites

- **Router**: MikroTik device running RouterOS v7.20 or higher.
- **Internet**: Two distinct ISP connections.
- **Hardware**: Minimum of 5 ethernet ports (2 WAN + 3 LAN).
- **Access**: Winbox or SSH access to the router.

**Tested on**: RouterOS v7.20+, RB750Gr3, E50UG

---

## Quick Start

### 1. Download Configuration
```bash
wget https://raw.githubusercontent.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/main/mikrotik-dual-wan.rsc
```

### 2. Edit Variables
Modify the parameters in `mikrotik-dual-wan.rsc` to match your network environment:

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

:local lISP1MonitorIP1 "45.90.28.0"
:local lISP1MonitorIP2 "208.67.222.222"
:local lISP2MonitorIP1 "9.9.9.9"
:local lISP2MonitorIP2 "4.2.2.2"

:local lFailureThreshold 2
:local lLBRatio1 1
:local lLBRatio2 1

# NOTIFICATION CONFIGURATION
:local lNotifyDelay1 60;   # Alert 1: 1 Hour (in minutes)
:local lNotifyDelay2 360;  # Alert 2: 6 Hours (in minutes)
:local lEmailEnable true
:local lEmailAddress "your-email@gmail.com"
:local lEmailPassword "your-app-password";  # Use Google App Password (letters/digits only, no special chars)

# SYSTEM SETTINGS
:local lTimeZone "Asia/Kolkata"
:local lDNSServers "1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4"

# DHCP SETTINGS
:local lDHCPPoolRange "192.168.100.100-192.168.100.200"
```

### 3. Upload to Router
Transfer `mikrotik-dual-wan.rsc` to the router using Winbox (Files -> Drag and drop) or SCP/SFTP.

### 4. Import Configuration
> [!WARNING]
> This script will reset your router configuration.
> It clears existing firewall rules, mangle rules, NAT, and routes to ensure a clean deployment.
> Do not execute this script remotely over a VPN or WAN interface as it resets the network interfaces. You must be connected via a local or out-of-band management port.

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

# Monitor failover status
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

## Architecture and Logic

### PCC Load Balancing
The Per Connection Classifier distributes traffic dynamically based on specified parameters:
```text
Client Request → MikroTik Router → PCC Classifier
                                   ├─ Hash 0 → ISP1 (50% traffic)
                                   └─ Hash 1 → ISP2 (50% traffic)
```
- **Per Connection**: Each discrete connection utilizes a single ISP route.
- **Dynamic Distribution**: `both-addresses-and-ports` ensures granular load distribution.
- **Connection Integrity**: Prevents packet reordering issues inherent to per-packet load balancing.

### Dual-IP Failover
The failover mechanism employs a scheduler to monitor two reliable IP addresses per ISP.
```text
Router → Ping 45.90.28.0 via ISP1 → UP
       → Ping 208.67.222.222 via ISP1 → DOWN
       RESULT: ISP1 is UP (At least one monitor responds)

Router → Ping 45.90.28.0 via ISP1 → DOWN
       → Ping 208.67.222.222 via ISP1 → DOWN
       RESULT: ISP1 is DOWN (Both monitors failed) → Failover to ISP2
```
This multi-target approach prevents false positives caused by single-node outages and requires complete loss of connectivity to initiate a failover event.

### Failover Connection Management
Upon detecting a failure on ISP1:
1. The scheduler confirms the failure threshold (e.g., 2 consecutive failures).
2. The script applies a 500ms delay for state synchronization.
3. ISP1 routes and PCC classification rules are disabled; return traffic rules remain active.
4. Client connections are seamlessly transitioned to ISP2.

---

## Performance Expectations

### Bandwidth Aggregation
Multi-threaded applications or downloads utilizing parallel connections will generally reflect combined bandwidth:

| ISP1 Capacity | ISP2 Capacity | Expected Aggregate |
|---------------|---------------|--------------------|
| 500 Mbps      | 100 Mbps      | ~600 Mbps          |
| 300 Mbps      | 300 Mbps      | ~600 Mbps          |
| 100 Mbps      | 50 Mbps       | ~150 Mbps          |

### Failover Metrics
- **Detection Latency**: ~20 seconds (Scheduler runs every 10s × default threshold of 2 failures).
- **Recovery Latency**: 1-5 seconds (PCC rules are disabled immediately, and connections are flushed to force rapid reconnection).

---

## Configuration Tuning

### Load Balance Ratio
Adjust ratios to favor specific interfaces based on bandwidth capacity:
```routeros
:local lLBRatio1 3  # ISP1 processes 75% of new connections
:local lLBRatio2 1  # ISP2 processes 25% of new connections
```

### Monitor IP Adjustment
Specify alternative monitoring targets:
```routeros
:local lISP1MonitorIP1 "45.90.28.0"
:local lISP1MonitorIP2 "208.67.222.222"
```

### Failover Sensitivity
```routeros
:local lFailureThreshold 2  # Failures required before marking interface DOWN
```

### Email Alerts
Configure SMTP notification parameters:
```routeros
:local lNotifyDelay1 60    # Initial alert threshold (minutes)
:local lNotifyDelay2 360   # Critical alert threshold (minutes)
:local lEmailEnable true
:local lEmailAddress "admin@example.com"
:local lEmailPassword "smtp-credentials"
```

---

## Troubleshooting

### Inactive Routes
```routeros
/ip route print detail where dst-address=0.0.0.0/0
```
- Active routes display the `DAc` flag.
- Inactive routes display the `Is` flag. Ensure monitor IPs are reachable via the designated interface.

### Load Balancing Issues
```routeros
/ip firewall connection print where connection-mark~"ISP"
```
- Verify the presence of both `ISP1_conn` and `ISP2_conn` marks.
- Review mangle rules (`/ip firewall mangle print`) if marks are missing.

### Failover Event Logs
```routeros
/log print where message~"FAILOVER"
```
Expected output states:
- `[FAILOVER] ISP1 DOWN - Both monitors failed`
- `[FAILOVER] ISP1 UP - Recovered`

---

## Security Policy

The configuration implements the following default security posture:
- **RAW Filters**: Drops WinBox and SSH traffic originating from the WAN directly in the PREROUTING chain to mitigate SYN flood attacks.
- Drops unauthorized WAN-to-Router access via strict firewall rules.
- Implements strict ICMP rate limiting on the LAN interface.
- Drops invalid connection states.
- Restricts Winbox and WebFig access to the designated local management subnet.
- Disables insecure management protocols (Telnet, FTP, API).

Additional recommendations:
1. Update default administrative credentials.
2. Enable firewall rule logging for auditing.
3. Configure TLS/HTTPS certificates for WebFig/Winbox.
4. Implement regular configuration backups.

---

## License

This project is licensed under the MIT License.

---

## Support and Contributions

- **Issues**: [GitHub Issues](https://github.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/issues)
- **Discussions**: [GitHub Discussions](https://github.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover/discussions)
- **Community**: [forum.mikrotik.com](https://forum.mikrotik.com)

Pull requests addressing bug fixes, optimizations, or documentation improvements are welcome. Please ensure any submitted changes are tested against RouterOS v7 hardware.
