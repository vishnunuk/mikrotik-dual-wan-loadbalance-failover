# MikroTik Dual WAN - RouterOS v7
# Features: PCC Load Balancing, Recursive Routing Failover, Connection Tracking Cleanup

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================

:global ISP1Name "Primary-ISP"
:global ISP2Name "Backup-ISP"
:global PreferredISP "ISP1"

:global WAN1Interface "ether1"
:global WAN1Gateway "192.168.0.1"
:global WAN2Interface "ether2"
:global WAN2Gateway "192.168.20.1"
:global LANInterface "ether5"

# Monitor IPs for Recursive Routing
:global ISP1MonitorIP1 "1.1.1.1"
:global ISP1MonitorIP2 "8.8.8.8"
:global ISP2MonitorIP1 "8.8.4.4"
:global ISP2MonitorIP2 "1.0.0.1"

# Failover Parameters
:global CheckInterval "3s"
:global CheckTimeout "800ms"
:global FailureThreshold 3

# Load Balancing Ratio (1:1 = Equal Distribution)
:global LBRatio1 1
:global LBRatio2 1

# ==============================================================================
# SYSTEM RESET
# ==============================================================================
:put "Starting configuration reset..."
:do { /ip firewall nat remove [find] } on-error={}
:do { /ip firewall mangle remove [find] } on-error={}
:do { /ip firewall filter remove [find dynamic=no] } on-error={}
:do { /ip route remove [find dynamic=no] } on-error={}
:do { /routing table remove [find name~"ISP"] } on-error={}
:do { /tool netwatch remove [find] } on-error={}
:delay 1s

# ==============================================================================
# ROUTING TABLES
# ==============================================================================
/routing table
add name=ISP1 fib comment=$ISP1Name
add name=ISP2 fib comment=$ISP2Name

# ==============================================================================
# IP ADDRESS CONFIGURATION
# ==============================================================================
/ip address
:do { remove [find interface=$WAN1Interface] } on-error={}
:do { remove [find interface=$WAN2Interface] } on-error={}
:do { remove [find interface=$LANInterface] } on-error={}
add address=192.168.0.3/24 interface=$WAN1Interface comment="WAN1"
add address=192.168.20.3/24 interface=$WAN2Interface comment="WAN2"
add address=192.168.100.1/24 interface=$LANInterface comment="LAN"

# ==============================================================================
# MANGLE RULES (PCC LOAD BALANCING)
# ==============================================================================
/ip firewall mangle

# Bypass Load Balancing for Local Subnets
add chain=prerouting dst-address=192.168.0.0/24 action=accept comment="Local: WAN1 Subnet"
add chain=prerouting dst-address=192.168.20.0/24 action=accept comment="Local: WAN2 Subnet"
add chain=prerouting dst-address=192.168.100.0/24 action=accept comment="Local: LAN Subnet"

# Bypass Load Balancing for DNS (Improves Resolution Speed)
add chain=prerouting protocol=udp dst-port=53 action=accept comment="Bypass: DNS"

# Calculate PCC Total
:local PCCTotal ($LBRatio1 + $LBRatio2)

# PCC Classification Loop
:local pccIndex 0
:while ($pccIndex < $LBRatio1) do={
    add chain=prerouting in-interface=$LANInterface connection-state=new connection-mark=no-mark \
        per-connection-classifier=("both-addresses-and-ports:" . $PCCTotal . "/" . $pccIndex) \
        action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
        comment=("PCC: ISP1 (" . ($pccIndex + 1) . "/" . $PCCTotal . ")")
    :set pccIndex ($pccIndex + 1)
}

:while ($pccIndex < $PCCTotal) do={
    add chain=prerouting in-interface=$LANInterface connection-state=new connection-mark=no-mark \
        per-connection-classifier=("both-addresses-and-ports:" . $PCCTotal . "/" . $pccIndex) \
        action=mark-connection new-connection-mark=ISP2_conn passthrough=yes \
        comment=("PCC: ISP2 (" . ($pccIndex + 1) . "/" . $PCCTotal . ")")
    :set pccIndex ($pccIndex + 1)
}

# Mark Routing based on Connection Mark
add chain=prerouting connection-mark=ISP1_conn in-interface=$LANInterface \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Route: ISP1"

add chain=prerouting connection-mark=ISP2_conn in-interface=$LANInterface \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Route: ISP2"

# Ensure Return Traffic Uses Correct Interface
add chain=prerouting connection-state=established,related in-interface=$WAN1Interface \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Return: WAN1"

add chain=prerouting connection-state=established,related in-interface=$WAN2Interface \
    action=mark-connection new-connection-mark=ISP2_conn passthrough=yes \
    comment="Return: WAN2"

# Output Chain (Router Traffic)
add chain=output connection-mark=ISP1_conn \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Output: ISP1"

add chain=output connection-mark=ISP2_conn \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Output: ISP2"

# DNS Output Marking
add chain=output protocol=udp dst-port=53 connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: DNS Default"

# ==============================================================================
# NAT CONFIGURATION
# ==============================================================================
/ip firewall nat
add chain=srcnat out-interface=$WAN1Interface action=masquerade comment="NAT: WAN1"
add chain=srcnat out-interface=$WAN2Interface action=masquerade comment="NAT: WAN2"
add chain=srcnat src-address=192.168.100.0/24 dst-address=192.168.100.0/24 \
    action=masquerade comment="NAT: Hairpin"

# ==============================================================================
# FIREWALL RULES
# ==============================================================================
/ip firewall filter

# Allow Tailscale
add chain=input protocol=udp dst-port=41641 action=accept comment="Allow: Tailscale"

# Drop Invalid Connections
add chain=input connection-state=invalid action=drop comment="Drop: Invalid Input"
add chain=forward connection-state=invalid action=drop comment="Drop: Invalid Forward"

# Accept Established/Related
add chain=input connection-state=established,related action=accept comment="Accept: Established Input"
add chain=forward connection-state=established,related action=accept comment="Accept: Established Forward"

# Accept LAN Traffic
add chain=input in-interface=$LANInterface action=accept comment="Accept: LAN Input"
add chain=forward in-interface=$LANInterface action=accept comment="Accept: LAN Forward"

# ICMP Rate Limiting
add chain=input protocol=icmp limit=10,5:packet action=accept comment="Limit: ICMP"
add chain=input protocol=icmp action=drop comment="Drop: Excess ICMP"

# Drop WAN Input (Security)
add chain=input in-interface=$WAN1Interface action=drop comment="Drop: WAN1 Input"
add chain=input in-interface=$WAN2Interface action=drop comment="Drop: WAN2 Input"

# ==============================================================================
# RECURSIVE ROUTING (FAILOVER)
# ==============================================================================
/ip route

# Host Routes to Monitor IPs
add dst-address=($ISP1MonitorIP1 . "/32") gateway=$WAN1Gateway scope=10 target-scope=10 comment="Monitor: ISP1 Primary"
add dst-address=($ISP1MonitorIP2 . "/32") gateway=$WAN1Gateway scope=10 target-scope=10 comment="Monitor: ISP1 Secondary"
add dst-address=($ISP2MonitorIP1 . "/32") gateway=$WAN2Gateway scope=10 target-scope=10 comment="Monitor: ISP2 Primary"
add dst-address=($ISP2MonitorIP2 . "/32") gateway=$WAN2Gateway scope=10 target-scope=10 comment="Monitor: ISP2 Secondary"

# Recursive Default Routes
:if ($PreferredISP = "ISP1") do={
    add dst-address=0.0.0.0/0 gateway=$ISP1MonitorIP1 check-gateway=ping distance=1 scope=30 target-scope=11 comment="Default: ISP1"
    add dst-address=0.0.0.0/0 gateway=$ISP2MonitorIP1 check-gateway=ping distance=2 scope=30 target-scope=11 comment="Default: ISP2 (Backup)"
} else={
    add dst-address=0.0.0.0/0 gateway=$ISP2MonitorIP1 check-gateway=ping distance=1 scope=30 target-scope=11 comment="Default: ISP2"
    add dst-address=0.0.0.0/0 gateway=$ISP1MonitorIP1 check-gateway=ping distance=2 scope=30 target-scope=11 comment="Default: ISP1 (Backup)"
}

# Routing Table Entries with Cross-Failover
add dst-address=0.0.0.0/0 gateway=$ISP1MonitorIP1 routing-table=ISP1 check-gateway=ping distance=1 scope=30 target-scope=11 comment="Table ISP1: Primary"
add dst-address=0.0.0.0/0 gateway=$ISP2MonitorIP1 routing-table=ISP1 check-gateway=ping distance=2 scope=30 target-scope=11 comment="Table ISP1: Failover"

add dst-address=0.0.0.0/0 gateway=$ISP2MonitorIP1 routing-table=ISP2 check-gateway=ping distance=1 scope=30 target-scope=11 comment="Table ISP2: Primary"
add dst-address=0.0.0.0/0 gateway=$ISP1MonitorIP1 routing-table=ISP2 check-gateway=ping distance=2 scope=30 target-scope=11 comment="Table ISP2: Failover"

# ==============================================================================
# DNS CONFIGURATION
# ==============================================================================
/ip dns
set servers=1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4 allow-remote-requests=yes cache-size=32768KiB cache-max-ttl=1d

# ==============================================================================
# NETWATCH (AUTOMATED FAILOVER & CLEANUP)
# ==============================================================================
/tool netwatch

# ISP1 Monitors
add host=$ISP1MonitorIP1 interval=$CheckInterval timeout=$CheckTimeout \
    down-script={ :log warning "Monitor: ISP1 Primary DOWN" } \
    up-script={ :log info "Monitor: ISP1 Primary UP" } \
    comment="Monitor: ISP1 Primary"

add host=$ISP1MonitorIP2 interval=$CheckInterval timeout=$CheckTimeout \
    down-script={
        :log error "Monitor: ISP1 FAILED. Clearing connections."
        /ip firewall connection remove [find connection-mark=ISP1_conn]
    } \
    up-script={ :log info "Monitor: ISP1 Secondary UP" } \
    comment="Monitor: ISP1 Secondary"

# ISP2 Monitors
add host=$ISP2MonitorIP1 interval=$CheckInterval timeout=$CheckTimeout \
    down-script={ :log warning "Monitor: ISP2 Primary DOWN" } \
    up-script={ :log info "Monitor: ISP2 Primary UP" } \
    comment="Monitor: ISP2 Primary"

add host=$ISP2MonitorIP2 interval=$CheckInterval timeout=$CheckTimeout \
    down-script={
        :log error "Monitor: ISP2 FAILED. Clearing connections."
        /ip firewall connection remove [find connection-mark=ISP2_conn]
    } \
    up-script={ :log info "Monitor: ISP2 Secondary UP" } \
    comment="Monitor: ISP2 Secondary"

# ==============================================================================
# SERVICE HARDENING
# ==============================================================================
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set www-ssl disabled=yes
set ssh disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox disabled=no

# ==============================================================================
# SYSTEM CONFIGURATION
# ==============================================================================
/system clock set time-zone-name=Asia/Kolkata
/system identity set name="DualWAN-Router"

# Logging Configuration
/system logging
:do { remove [find topics~"info" prefix="[INFO]"] } on-error={}
:do { remove [find topics~"error" prefix="[ERROR]"] } on-error={}
:do { remove [find topics~"warning" prefix="[WARN]"] } on-error={}
add topics=info prefix="[INFO] "
add topics=error prefix="[ERROR] "
add topics=warning prefix="[WARN] "
add topics=firewall,info action=memory prefix="[FW] "

# NTP Configuration
/system ntp client set enabled=yes
/system ntp client servers
:do { remove [find] } on-error={}
add address=time.cloudflare.com
add address=time.google.com
add address=time.nist.gov

# Resource Monitoring Scheduler
/system scheduler
:do { remove [find name="check-memory"] } on-error={}
add name=check-memory interval=1h on-event={
    :local memFree [/system resource get free-memory]
    :local memTotal [/system resource get total-memory]
    :local memPercent (($memTotal - $memFree) * 100 / $memTotal)
    :if ($memPercent > 90) do={
        :log warning ("High Memory Usage: " . $memPercent . "%")
    }
} start-time=startup

# ==============================================================================
# COMPLETION SUMMARY
# ==============================================================================
:put ""
:put "========================================================================"
:put " Configuration Applied Successfully"
:put "========================================================================"
:put ""
:put ("ISP1: " . $ISP1Name . " (" . $WAN1Interface . ")")
:put ("ISP2: " . $ISP2Name . " (" . $WAN2Interface . ")")
:put ("Load Balance Ratio: " . $LBRatio1 . ":" . $LBRatio2)
:put ""
:put "Next Steps:"
:put "1. Verify interfaces are connected."
:put "2. Check routes: /ip route print"
:put "3. Check logs: /log print"
:put "Now Reboot" 
:put "/system reboot"
:put "After reboot run:"
:put "/ip service set winbox address=192.168.100.0/24"
:put ""
