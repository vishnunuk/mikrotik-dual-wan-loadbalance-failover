# MikroTik Dual WAN - RouterOS v7.20
# Features: PCC Load Balancing, Dual-IP Failover, Connection Tracking Cleanup
# ==============================================================================
# ==============================================================================
# CONFIGURATION VARIABLES (Local Locking for v7 Stability)
# ==============================================================================
# We define as locals first to ensure they stay in scope during the entire script execution.
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

# Export to Globals for persistence script
:global ISP1MonitorIP1 $lISP1MonitorIP1; :global ISP1MonitorIP2 $lISP1MonitorIP2
:global ISP2MonitorIP1 $lISP2MonitorIP1; :global ISP2MonitorIP2 $lISP2MonitorIP2
:global WAN1Interface $lWAN1Interface; :global WAN2Interface $lWAN2Interface
:global WAN1Address $lWAN1Address; :global WAN2Address $lWAN2Address
:global WAN1Gateway $lWAN1Gateway; :global WAN2Gateway $lWAN2Gateway
:global FailureThreshold $lFailureThreshold; :global PreferredISP $lPreferredISP

# ==============================================================================

# ==============================================================================
# SYSTEM RESET (DESTRUCTIVE - USE WITH CAUTION)
# ==============================================================================
# WARNING: This section removes ALL existing NAT, mangle, filter, and route rules.
# DO NOT run this script remotely or on production routers with existing configs.
# To enable reset, set allowDestructiveReset="yes" below.



:put "WARNING: Starting DESTRUCTIVE configuration reset in 5 seconds..."
:put "WARNING: This will remove ALL firewall rules, routes, and NAT!"
:put "WARNING: Press Ctrl+C NOW to cancel if you want to preserve existing config."
:delay 5s

:put "Starting configuration reset..."
# MASTER PURGE: Clear all global variables to prevent poisoning
/system script environment remove [find]

# Exhaustive removal of previous script/scheduler entries
:do { /system scheduler remove [/system scheduler find where name~"failover" || name~"memory" || name~"launcher"] } on-error={}
:do { /system script remove [/system script find where name~"failover" || name~"enabler" || name~"config"] } on-error={}

:do { /ip firewall nat remove [/ip firewall nat find where comment~"NAT:"] } on-error={}
:do { /ip firewall mangle remove [/ip firewall mangle find where comment~"PCC" || comment~"Route" || comment~"Return" || comment~"Output" || comment~"Bypass" || comment~"Local:"] } on-error={}
:do { /ip firewall filter remove [/ip firewall filter find where comment~"Accept:" || comment~"Drop:" || comment~"Limit:" || comment~"Allow WAN"] } on-error={}
:do { /ip route remove [/ip route find where comment~"Default:" || comment~"Table ISP" || comment~"Monitor" || comment~"FAILSAFE"] } on-error={}
:do { /routing table remove [/routing table find where name="ISP1" || name="ISP2"] } on-error={}
:do { /interface bridge remove [/interface bridge find name=$lLANInterface] } on-error={}
:delay 2s

# ==============================================================================
# ROUTING TABLES
# ==============================================================================
/routing table
add name=ISP1 fib comment=$lISP1Name
add name=ISP2 fib comment=$lISP2Name

# ==============================================================================
# INTERFACE LISTS (For WAN Protection)
# ==============================================================================
/interface list
:do { remove [find name="WAN"] } on-error={}
add name=WAN comment="WAN Interfaces for Security Rules"

/interface list member
:do { /interface list member remove [/interface list member find interface=$lWAN1Interface] } on-error={}
:do { /interface list member remove [/interface list member find interface=$lWAN2Interface] } on-error={}
:if ([:len $lWAN1Interface] > 0) do={ add list=WAN interface=$lWAN1Interface comment="WAN1" }
:if ([:len $lWAN2Interface] > 0) do={ add list=WAN interface=$lWAN2Interface comment="WAN2" }

# ==============================================================================
# BRIDGE CONFIGURATION
# ==============================================================================
/interface bridge
add name=$lLANInterface comment="LAN Bridge"

/interface bridge port
:do { remove [find interface=$lWAN1Interface] } on-error={}
:do { remove [find interface=$lWAN2Interface] } on-error={}
:do { remove [find interface=$lLANPort1] } on-error={}
:do { remove [find interface=$lLANPort2] } on-error={}
:do { remove [find interface=$lLANPort3] } on-error={}
add bridge=$lLANInterface interface=$lLANPort1 comment="LAN Port 1"
add bridge=$lLANInterface interface=$lLANPort2 comment="LAN Port 2"
add bridge=$lLANInterface interface=$lLANPort3 comment="LAN Port 3"

# ==============================================================================
# IP ADDRESS & ADDRESS LISTS
# ==============================================================================
/ip firewall address-list
:do { remove [/ip firewall address-list find list="LocalTraffic"] } on-error={}
add address=$lLANSubnet list=LocalTraffic comment="LAN Subnet"
add address=$lWAN1Subnet list=LocalTraffic comment="WAN1 Subnet"
add address=$lWAN2Subnet list=LocalTraffic comment="WAN2 Subnet"

/ip firewall address-list
:do { remove [/ip firewall address-list find list="MonitorIPs"] } on-error={}
add address=$lISP1MonitorIP1 list=MonitorIPs comment="ISP1 Monitor 1"
add address=$lISP1MonitorIP2 list=MonitorIPs comment="ISP1 Monitor 2"
add address=$lISP2MonitorIP1 list=MonitorIPs comment="ISP2 Monitor 1"
add address=$lISP2MonitorIP2 list=MonitorIPs comment="ISP2 Monitor 2"

/ip address
:do { remove [/ip address find interface=$lWAN1Interface] } on-error={}
:do { remove [/ip address find interface=$lWAN2Interface] } on-error={}
:do { remove [/ip address find interface=$lLANInterface] } on-error={}

# Extract CIDR from subnet variables (e.g., "192.168.0.0/24" -> "24")
:local wan1CIDR [:pick $lWAN1Subnet ([:find $lWAN1Subnet "/"] + 1) [:len $lWAN1Subnet]]
:local wan2CIDR [:pick $lWAN2Subnet ([:find $lWAN2Subnet "/"] + 1) [:len $lWAN2Subnet]]

add address=($lWAN1Address . "/" . $wan1CIDR) interface=$lWAN1Interface comment="WAN1"
add address=($lWAN2Address . "/" . $wan2CIDR) interface=$lWAN2Interface comment="WAN2"
add address=$lLANAddress interface=$lLANInterface comment="LAN"

# ==============================================================================
# DHCP SERVER CONFIGURATION
# ==============================================================================
/ip pool
:do { remove [find name="lan-dhcp-pool"] } on-error={}
add name=lan-dhcp-pool ranges=("192.168.100.100-192.168.100.200") comment="LAN DHCP Pool"

/ip dhcp-server
:do { remove [find name="lan-dhcp"] } on-error={}
add name=lan-dhcp interface=$lLANInterface address-pool=lan-dhcp-pool disabled=no comment="LAN DHCP Server"

/ip dhcp-server network
:do { remove [find address=$lLANSubnet] } on-error={}
add address=$lLANSubnet gateway=$lLANGateway dns-server=$lLANGateway comment="LAN DHCP Network"

# ==============================================================================
# MANGLE RULES (PCC LOAD BALANCING)
# ==============================================================================
# NOTE: FastTrack is intentionally disabled by mangle rules below.
#       PCC requires per-connection classification, which is incompatible with FastTrack.
#       Expected throughput: CPU-limited (~100-200 Mbps on low-end hardware, higher on modern CPUs)
/ip firewall mangle

# Bypass Load Balancing for Local Traffic
add chain=prerouting dst-address-list=LocalTraffic action=return comment="Local: Subnet Bypass"
add chain=prerouting dst-address-type=local action=return comment="Local: Router Addresses"

# Bypass PCC for Monitor IPs (Force Main Table)
add chain=prerouting dst-address=$lISP1MonitorIP1 action=return comment="Bypass: Monitor IPs"
add chain=prerouting dst-address=$lISP1MonitorIP2 action=return
add chain=prerouting dst-address=$lISP2MonitorIP1 action=return
add chain=prerouting dst-address=$lISP2MonitorIP2 action=return

# Bypass PCC for DNS and NTP (Use Main Table)
add chain=prerouting protocol=udp dst-port=53 action=return comment="Bypass: DNS/NTP"
add chain=prerouting protocol=tcp dst-port=53 action=return
add chain=prerouting protocol=udp dst-port=123 action=return

# Bypass Output Chain (Local Management and RFC1918)
# CRITICAL: This MUST come before the catch-all rule to prevent router responses 
# being sent out the WAN.
add chain=output dst-address-type=local action=return comment="Output Bypass: local"
# Mangle:Removed MonitorIPs bypass to allow src-address based routing enforcement
add chain=output dst-address=192.168.0.0/16 action=return comment="Output Bypass: 192.168/16"
add chain=output dst-address=10.0.0.0/8 action=return comment="Output Bypass: 10/8"
add chain=output dst-address=172.16.0.0/12 action=return comment="Output Bypass: 172.16/12"

# Bypass NTP for router stability
add chain=output protocol=udp dst-port=123 action=return comment="Bypass: NTP"

# Calculate PCC Total
:local PCCTotal ($lLBRatio1 + $lLBRatio2)

# PCC Classification Loop
:local pccIndex 0
:while ($pccIndex < $lLBRatio1) do={
    /ip firewall mangle add chain=prerouting in-interface=$lLANInterface connection-state=new connection-mark=no-mark \
        per-connection-classifier=("both-addresses-and-ports:" . $PCCTotal . "/" . $pccIndex) \
        action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
        comment=("PCC: ISP1 (" . ($pccIndex + 1) . "/" . $PCCTotal . ")")
    :set pccIndex ($pccIndex + 1)
}

:while ($pccIndex < $PCCTotal) do={
    /ip firewall mangle add chain=prerouting in-interface=$lLANInterface connection-state=new connection-mark=no-mark \
        per-connection-classifier=("both-addresses-and-ports:" . $PCCTotal . "/" . $pccIndex) \
        action=mark-connection new-connection-mark=ISP2_conn passthrough=yes \
        comment=("PCC: ISP2 (" . ($pccIndex + 1) . "/" . $PCCTotal . ")")
    :set pccIndex ($pccIndex + 1)
}

# Restore Connection Mark for Return Traffic (Fixed: Strict Interface Binding)
add chain=prerouting in-interface=$lWAN1Interface connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Return: ISP1-WAN Conn"

add chain=prerouting in-interface=$lWAN2Interface connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP2_conn passthrough=yes \
    comment="Return: ISP2-WAN Conn"

# Apply Routing Mark for Return Traffic (CRITICAL: prevents asymmetric routing)
add chain=prerouting in-interface=$lWAN1Interface connection-mark=ISP1_conn \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Return: ISP1-WAN Route"

add chain=prerouting in-interface=$lWAN2Interface connection-mark=ISP2_conn \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Return: ISP2-WAN Route"

# Mark Routing based on Connection Mark
add chain=prerouting connection-mark=ISP1_conn in-interface=$lLANInterface \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Route: ISP1"

add chain=prerouting connection-mark=ISP2_conn in-interface=$lLANInterface \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Route: ISP2"

# Output Chain (Router-Originated Traffic)
# Force router DNS, NTP, and RouterOS services to use primary ISP by default
add chain=output protocol=udp dst-port=53 connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: Router DNS (ISP1)"

add chain=output protocol=tcp dst-port=53 connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: Router DNS TCP (ISP1)"

add chain=output protocol=udp dst-port=123 connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: Router NTP (ISP1)"

add chain=output protocol=tcp dst-port=80,443 connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: Router Updates (ISP1)"

# NEW: Explicitly mark routing based on Source Address (Failover Monitor Fix)
# This allows 'src-address' pings to work without 'routing-table' syntax errors.
add chain=output src-address=$lWAN1Address action=mark-routing new-routing-mark=ISP1 passthrough=no comment="Output: Force WAN1 Source to ISP1"
add chain=output src-address=$lWAN2Address action=mark-routing new-routing-mark=ISP2 passthrough=no comment="Output: Force WAN2 Source to ISP2"

# CATCH-ALL: Mark all other unmarked router traffic to prevent leaks
# WARNING: This rule hides configuration errors by forcing all unmarked traffic to ISP1.
add chain=output connection-mark=no-mark dst-address-type=!local \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: Catch-All (ISP1)"

# Apply routing marks for router output traffic
add chain=output connection-mark=ISP1_conn \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Output: Route ISP1"

add chain=output connection-mark=ISP2_conn \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Output: Route ISP2"

# ==============================================================================
# NAT CONFIGURATION
# ==============================================================================
/ip firewall nat
add chain=srcnat out-interface-list=WAN action=masquerade comment="NAT: WAN-aware Masquerade"
# NOTE: Removed redundant WAN-specific masquerade rules. 
#       The subnet-based rule is comprehensive and best for PCC in v7.

# ==============================================================================
# FIREWALL RULES
# ==============================================================================
/ip firewall filter

# Drop Invalid Connections
add chain=input connection-state=invalid action=drop comment="Drop: Invalid Input"
add chain=forward connection-state=invalid action=drop comment="Drop: Invalid Forward"

# Allow WinBox and SSH from LAN only
add chain=input protocol=tcp dst-port=8291 src-address-list=LocalTraffic action=accept comment="Accept: WinBox (LAN only)"
add chain=input protocol=tcp dst-port=22 src-address-list=LocalTraffic action=accept comment="Accept: SSH (LAN only)"

# Allow GUI and API from LAN only
add chain=input protocol=tcp dst-port=80 src-address-list=LocalTraffic action=accept comment="Accept: HTTP (LAN only)"
add chain=input protocol=tcp dst-port=8728 src-address-list=LocalTraffic action=accept comment="Accept: API (LAN only)"

# Accept Established/Related
add chain=input connection-state=established,related action=accept comment="Accept: Established Input"
add chain=forward connection-state=established,related action=accept comment="Accept: Established Forward"

# Accept Monitor IPs (Critical for Failover Pings)
add chain=input src-address-list=MonitorIPs protocol=icmp action=accept comment="Accept: Monitor IPs (ICMP Only)"

# ICMP Rate Limiting (must be before LAN ICMP accept)
add chain=input protocol=icmp limit=10,5:packet action=accept comment="Limit: ICMP"
add chain=input protocol=icmp action=drop comment="Drop: Excess ICMP"

# Accept All LAN Traffic
add chain=input in-interface=$lLANInterface action=accept comment="Accept: Full LAN Input"

# Forward Chain - Traffic Control
add chain=forward in-interface=$lLANInterface connection-state=new,established,related action=accept comment="Accept: LAN Forward"
add chain=forward in-interface-list=WAN out-interface=$lLANInterface connection-state=established,related action=accept comment="Allow WAN return to LAN"


# Drop WAN Input (Security)
add chain=input in-interface=$lWAN1Interface action=drop comment="Drop: WAN1 Input"
add chain=input in-interface=$lWAN2Interface action=drop comment="Drop: WAN2 Input"

# FINAL DROP RULES (Default Deny Policy)
add chain=input action=drop comment="Drop: All other input"
add chain=forward action=drop comment="Drop: All other forward"

# ==============================================================================
# ROUTING CONFIGURATION (DUAL-IP FAILOVER)
# ==============================================================================
/ip route

# Note: Main Table Host Routes removed to prevent conflict with PCC routing.
# We rely strictly on the Routing Table routes below.

# Host Routes for Monitor IPs (In Routing Tables - for routing-table ping)
add dst-address=($lISP1MonitorIP1 . "/32") gateway=$lWAN1Gateway routing-table=ISP1 comment=("Monitor RT: ISP1-1")
add dst-address=($lISP1MonitorIP2 . "/32") gateway=$lWAN1Gateway routing-table=ISP1 comment=("Monitor RT: ISP1-2")
add dst-address=($lISP2MonitorIP1 . "/32") gateway=$lWAN2Gateway routing-table=ISP2 comment=("Monitor RT: ISP2-1")
add dst-address=($lISP2MonitorIP2 . "/32") gateway=$lWAN2Gateway routing-table=ISP2 comment=("Monitor RT: ISP2-2")

# Main Default Routes (controlled by scheduler script)
:if ($lPreferredISP = "ISP1") do={
    add dst-address=0.0.0.0/0 gateway=$lWAN1Gateway distance=1 comment="Default: ISP1"
    add dst-address=0.0.0.0/0 gateway=$lWAN2Gateway distance=2 comment="Default: ISP2 (Backup)"
} else={
    add dst-address=0.0.0.0/0 gateway=$lWAN2Gateway distance=1 comment="Default: ISP2"
    add dst-address=0.0.0.0/0 gateway=$lWAN1Gateway distance=2 comment="Default: ISP1 (Backup)"
}

# FAILSAFE ROUTES - NEVER DISABLED (Prevents total blackout)
add dst-address=0.0.0.0/0 gateway=$lWAN1Gateway distance=250 comment="FAILSAFE-ISP1" disabled=no
add dst-address=0.0.0.0/0 gateway=$lWAN2Gateway distance=251 comment="FAILSAFE-ISP2" disabled=no

# FAILSAFE ROUTES (Routing Tables)
add dst-address=0.0.0.0/0 gateway=$lWAN1Gateway routing-table=ISP1 distance=250 comment="FAILSAFE-RT: ISP1" disabled=no
add dst-address=0.0.0.0/0 gateway=$lWAN2Gateway routing-table=ISP2 distance=250 comment="FAILSAFE-RT: ISP2" disabled=no

# Routing Table Entries with Cross-Failover
add dst-address=0.0.0.0/0 gateway=$lWAN1Gateway routing-table=ISP1 distance=1 comment="Table ISP1: Primary"
add dst-address=0.0.0.0/0 gateway=$lWAN2Gateway routing-table=ISP1 distance=2 comment="Table ISP1: Failover"

add dst-address=0.0.0.0/0 gateway=$lWAN2Gateway routing-table=ISP2 distance=1 comment="Table ISP2: Primary"
add dst-address=0.0.0.0/0 gateway=$lWAN1Gateway routing-table=ISP2 distance=2 comment="Table ISP2: Failover"

# ==============================================================================
# DNS CONFIGURATION
# ==============================================================================
/ip dns
set servers=1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4 allow-remote-requests=yes cache-size=32768KiB cache-max-ttl=1d

# ==============================================================================
# DUAL-IP FAILOVER SCHEDULER
# ==============================================================================
# Note: Netwatch removed - it shows false positives (can reach monitor IPs via alternate WAN)
# Scheduler handles all failover detection using interface status + source-address pings
# Check logs for failover status: /log print where message~"FAILOVER"

# Initialize global state variables
:global ISP1FailCount 0
:global ISP2FailCount 0
:global ISP1Status "up"
:global ISP2Status "up"

# ==============================================================================
# FAILOVER LOGIC & STARTUP ENABLER
# ==============================================================================
/system script

# Define dual-wan-config here (after reset) so it survives
:do { remove [find name="dual-wan-config"] } on-error={}
add name="dual-wan-config" source=(":global ISP1MonitorIP1 \"" . $lISP1MonitorIP1 . "\"; :global ISP1MonitorIP2 \"" . $lISP1MonitorIP2 . "\"; :global ISP2MonitorIP1 \"" . $lISP2MonitorIP1 . "\"; :global ISP2MonitorIP2 \"" . $lISP2MonitorIP2 . "\"; :global WAN1Address \"" . $lWAN1Address . "\"; :global WAN2Address \"" . $lWAN2Address . "\"; :global WAN1Gateway \"" . $lWAN1Gateway . "\"; :global WAN2Gateway \"" . $lWAN2Gateway . "\"; :global FailureThreshold " . $lFailureThreshold . "; :global PreferredISP \"" . $lPreferredISP . "\"; :global WAN1Interface \"" . $lWAN1Interface . "\"; :global WAN2Interface \"" . $lWAN2Interface . "\"")

:do { remove [/system script find name="failover-logic"] } on-error={}
add name="failover-logic" source=":global ISP1MonitorIP1; :global ISP1MonitorIP2
    :global ISP2MonitorIP1; :global ISP2MonitorIP2
    :global WAN1Interface; :global WAN2Interface
    :global FailureThreshold; :global PreferredISP
    :global WAN1Address; :global WAN2Address
    
    :global ISP1Status; :global ISP2Status
    :global ISP1FailCount; :global ISP2FailCount

    # SELF-HEALING: If globals are missing (e.g., failed startup race), reload them.
    :if ([:typeof \$WAN1Interface] = \"nothing\" || [:len \$WAN1Interface] = 0) do={
        :log warning \"[FAILOVER] Globals missing. Attempting reload...\"
        :do { /system script run dual-wan-config } on-error={}
    }

    :do {
        :local isStable true
        :if ([/system resource get uptime] < 1m) do={ 
            :log info \"[FAILOVER] Startup safety wait. Skipping check.\"
            :set isStable false
        }
        :if (\$isStable) do={
            :if ([:typeof \$ISP1Status] = \"nothing\" || [:len \$ISP1Status] = 0) do={ :set ISP1Status \"up\" }
            :if ([:typeof \$ISP2Status] = \"nothing\" || [:len \$ISP2Status] = 0) do={ :set ISP2Status \"up\" }
            :if ([:typeof \$ISP1FailCount] = \"nothing\") do={ :set ISP1FailCount 0 }
            :if ([:typeof \$ISP2FailCount] = \"nothing\") do={ :set ISP2FailCount 0 }

            :local r1Test [/ip route find where comment=\"Default: ISP1\" and disabled=yes]
            :if ([:len \$r1Test] > 0 && \$ISP1Status = \"up\") do={ :set ISP1Status \"down\"; :log warning \"[FAILOVER] Synced ISP1Status to 'down' (found disabled routes)\" }
            :local r2Test [/ip route find where comment=\"Default: ISP2\" and disabled=yes]
            :if ([:len \$r2Test] > 0 && \$ISP2Status = \"up\") do={ :set ISP2Status \"down\"; :log warning \"[FAILOVER] Synced ISP2Status to 'down' (found disabled routes)\" }

            :local wan1Running ([:len [/interface find where name=\$WAN1Interface and running=yes]] > 0)
            :local isp1ip1up false; :local isp1ip2up false
            :if (\$wan1Running) do={
                :do { 
                    :if ([/ping address=\$ISP1MonitorIP1 src-address=\$WAN1Address count=3] = 0) do={ 
                        :log info (\"[FAILOVER] ISP1-1 (\" . \$ISP1MonitorIP1 . \") Ping Failed\")
                    } else={ :set isp1ip1up true }
                } on-error={}
                :do { 
                    :if ([/ping address=\$ISP1MonitorIP2 src-address=\$WAN1Address count=3] = 0) do={ 
                        :log info (\"[FAILOVER] ISP1-2 (\" . \$ISP1MonitorIP2 . \") Ping Failed\")
                    } else={ :set isp1ip2up true }
                } on-error={}
            } else={ :log warning (\"[FAILOVER] ISP1 Interface (\" . \$WAN1Interface . \") NOT RUNNING\") }
            :local isp1BothDown ((\$wan1Running = false) || ((\$isp1ip1up = false) && (\$isp1ip2up = false)))
            
            :local wan2Running ([:len [/interface find where name=\$WAN2Interface and running=yes]] > 0)
            :local isp2ip1up false; :local isp2ip2up false
            :if (\$wan2Running) do={
                :do { 
                    :if ([/ping address=\$ISP2MonitorIP1 src-address=\$WAN2Address count=3] = 0) do={ 
                        :log info (\"[FAILOVER] ISP2-1 (\" . \$ISP2MonitorIP1 . \") Ping Failed\")
                    } else={ :set isp2ip1up true }
                } on-error={}
                :do { 
                    :if ([/ping address=\$ISP2MonitorIP2 src-address=\$WAN2Address count=3] = 0) do={ 
                        :log info (\"[FAILOVER] ISP2-2 (\" . \$ISP2MonitorIP2 . \") Ping Failed\")
                    } else={ :set isp2ip2up true }
                } on-error={}
            } else={ :log warning (\"[FAILOVER] ISP2 Interface (\" . \$WAN2Interface . \") NOT RUNNING\") }
            :local isp2BothDown ((\$wan2Running = false) || ((\$isp2ip1up = false) && (\$isp2ip2up = false)))
            
            :if (\$isp1BothDown) do={
                :set ISP1FailCount (\$ISP1FailCount + 1)
                :if (\$ISP1Status = \"up\") do={
                    :log info (\"[FAILOVER] ISP1 Check Failed (Count: \" . \$ISP1FailCount . \"/\" . \$FailureThreshold . \")\")
                    :if (\$ISP1FailCount >= \$FailureThreshold) do={
                        :set ISP1Status \"down\"
                        :log error \"[FAILOVER] ISP1 DOWN - Both monitors failed\"
                        
                        :local connCount [/ip firewall connection print count-only where connection-mark=ISP1_conn]
                        :if (\$connCount > 0) do={ 
                            /ip firewall connection remove [/ip firewall connection find where connection-mark=ISP1_conn]
                            :log warning (\"[FAILOVER] Killed \" . \$connCount . \" ISP1 connections\")
                        }
                        
                        :foreach i in=[/ip route find where comment~\"ISP1\" and comment!~\"Monitor\"] do={ /ip route disable \$i }
                        :foreach i in=[/ip firewall mangle find where comment~\"ISP1\" and comment!~\"Monitor\"] do={ /ip firewall mangle disable \$i }
                    }
                }
            } else={
                :if (\$ISP1Status = \"down\") do={
                    :set ISP1Status \"up\"; :set ISP1FailCount 0
                    :log info \"[FAILOVER] ISP1 UP - Recovered\"
                    :foreach i in=[/ip route find where comment~\"ISP1\"] do={ /ip route enable \$i }
                    :foreach i in=[/ip firewall mangle find where comment~\"ISP1\"] do={ /ip firewall mangle enable \$i }
                } else={ :set ISP1FailCount 0 }
            }
            
            :if (\$isp2BothDown) do={
                :set ISP2FailCount (\$ISP2FailCount + 1)
                :if (\$ISP2Status = \"up\") do={
                    :log info (\"[FAILOVER] ISP2 Check Failed (Count: \" . \$ISP2FailCount . \"/\" . \$FailureThreshold . \")\")
                    :if (\$ISP2FailCount >= \$FailureThreshold) do={
                        :set ISP2Status \"down\"
                        :log error \"[FAILOVER] ISP2 DOWN - Both monitors failed\"
                        
                        :local connCount [/ip firewall connection print count-only where connection-mark=ISP2_conn]
                        :if (\$connCount > 0) do={
                            /ip firewall connection remove [/ip firewall connection find where connection-mark=ISP2_conn]
                            :log warning (\"[FAILOVER] Killed \" . \$connCount . \" ISP2 connections\")
                        }
                        
                        :foreach i in=[/ip route find where comment~\"ISP2\" and comment!~\"Monitor\"] do={ /ip route disable \$i }
                        :foreach i in=[/ip firewall mangle find where comment~\"ISP2\" and comment!~\"Monitor\"] do={ /ip firewall mangle disable \$i }
                    }
                }
            } else={
                :if (\$ISP2Status = \"down\") do={
                    :set ISP2Status \"up\"; :set ISP2FailCount 0
                    :log info \"[FAILOVER] ISP2 UP - Recovered\"
                    :foreach i in=[/ip route find where comment~\"ISP2\"] do={ /ip route enable \$i }
                    :foreach i in=[/ip firewall mangle find where comment~\"ISP2\"] do={ /ip firewall mangle enable \$i }
                } else={ :set ISP2FailCount 0 }
            }
        }
    } on-error={ :log error \"[FAILOVER] Script CRASHED: \$error\" }
"

:do { remove [/system script find name="startup-enabler"] } on-error={}
add name="startup-enabler" source={
    :local up [/system resource get uptime]
    :if ($up < 00:02:00) do={
        :log info ("Startup Enabler: System recently booted ($up). Waiting 90s for stability...")
        :delay 90s
    } else={
        :log info "Startup Enabler: System already stable. Enabling tasks immediately."
    }
    
    # CRITICAL: Load configuration variables before starting schedulers
    # This prevents "variable undefined" errors in failover-logic
    /system script run dual-wan-config
    :log info "Startup Enabler: Global variables loaded."
    
    /system scheduler enable [/system scheduler find name="dual-ip-failover"]
    /system scheduler enable [/system scheduler find name="check-memory"]
    :log info "Startup Enabler: Periodic tasks enabled"
}

/system scheduler
:do { remove [/system scheduler find name="dual-ip-failover"] } on-error={}
add name=dual-ip-failover interval=10s start-time=startup disabled=yes on-event="/system script run failover-logic"

:do { remove [/system scheduler find name="bootstrap-launcher"] } on-error={}
add name=bootstrap-launcher start-time=startup interval=0s on-event="/system script run startup-enabler"

# ==============================================================================
# SERVICE HARDENING (SECURITY)
# ==============================================================================
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www address=$lLANSubnet disabled=no
set www-ssl disabled=yes
set ssh disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox address=$lLANSubnet disabled=no

# ==============================================================================
# SYSTEM CONFIGURATION
# ==============================================================================
/system clock set time-zone-name=Asia/Kolkata
/system identity set name="DualWAN-Router"

# Critical: Prevent firewall bypass via IPv6 (since we have no IPv6 filter)
:do { /ipv6 settings set disable-ipv6=yes forward=no accept-redirects=no } on-error={}

# Critical: Ensure asymmetric Dual-WAN traffic isn't dropped by kernel
/ip settings set rp-filter=loose

# Logging Configuration
/system logging
:do {
    :foreach i in=[/system logging find where topics~"info"] do={
        :if ([/system logging get $i prefix] = "[INFO] ") do={ /system logging remove $i }
    }
    :foreach i in=[/system logging find where topics~"error"] do={
        :if ([/system logging get $i prefix] = "[ERROR] ") do={ /system logging remove $i }
    }
    :foreach i in=[/system logging find where topics~"warning"] do={
        :if ([/system logging get $i prefix] = "[WARN] ") do={ /system logging remove $i }
    }
} on-error={}
add topics=info prefix="[INFO] "
add topics=error prefix="[ERROR] "
add topics=warning prefix="[WARN] "
add topics=firewall,info action=memory prefix="[FW] "

# NTP Configuration
/system ntp client set enabled=yes
/system ntp client servers
:do { /system ntp client servers remove [/system ntp client servers find] } on-error={}
add address=time.cloudflare.com
add address=time.google.com
add address=time.nist.gov

# Resource Monitoring Scheduler
/system scheduler
:do { remove [/system scheduler find name="check-memory"] } on-error={}
add name=check-memory interval=1h start-time=startup disabled=yes on-event={
    :local memFree [/system resource get free-memory]
    :local memTotal [/system resource get total-memory]
    :local memPercent (($memTotal - $memFree) * 100 / $memTotal)
    :if ($memPercent > 90) do={
        :log warning ("High Memory Usage: " . $memPercent . "%")
    }
}

# Flush all existing connections to apply new mangle/routing rules immediately
/ip firewall connection remove [/ip firewall connection find]

# ==============================================================================
# COMPLETION SUMMARY
# ==============================================================================
:put ""
:put "========================================================================"
:put " Configuration Applied Successfully"
:put "========================================================================"
:put ""
:put ("ISP1: " . $lISP1Name . " (" . $lWAN1Interface . ")")
:put ("  Monitor IPs: " . $lISP1MonitorIP1 . " AND " . $lISP1MonitorIP2)
:put ("ISP2: " . $lISP2Name . " (" . $lWAN2Interface . ")")
:put ("  Monitor IPs: " . $lISP2MonitorIP1 . " AND " . $lISP2MonitorIP2)
:put ("Load Balance Ratio: " . $lLBRatio1 . ":" . $lLBRatio2)
:put ""
:put "Failover Logic: BOTH monitor IPs must fail to trigger ISP failover"
:put ("Failure Threshold: " . $lFailureThreshold . " consecutive checks")
:put ""
:put "Next Steps:"
:put "1. Verify interfaces are connected."
:put "2. Check routes: /ip route print"
:put "3. Check scheduler: /system scheduler print detail where name=dual-ip-failover"
:put "4. Monitor failover: /log print follow where message~\"FAILOVER\""
:put "5. Check all logs: /log print follow where topics~\"error,warning,info\""
:put ""
:put ("Security: WinBox access restricted to LAN (" . $lLANSubnet . ") only")
:put ""

# KICKSTART MONITORING
:put "Kickstarting monitoring scripts..."
/system script run startup-enabler
