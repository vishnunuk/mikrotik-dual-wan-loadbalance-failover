# MikroTik Dual WAN - RouterOS v7.20
# Features: PCC Load Balancing, Dual-IP Failover, Connection Tracking Cleanup

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================

:global ISP1Name "Primary-ISP"
:global ISP2Name "Backup-ISP"
:global PreferredISP "ISP1"

:global WAN1Interface "ether1"
:global WAN1Address "192.168.0.3"
:global WAN1Gateway "192.168.0.1"
:global WAN1Subnet "192.168.0.0/24"
:global WAN2Interface "ether2"
:global WAN2Address "192.168.20.3"
:global WAN2Gateway "192.168.20.1"
:global WAN2Subnet "192.168.20.0/24"
:global LANInterface "bridge-lan"
:global LANPort1 "ether3"
:global LANPort2 "ether4"
:global LANPort3 "ether5"
:global LANSubnet "192.168.100.0/24"
:global LANAddress "192.168.100.1/24"
:global LANGateway "192.168.100.1"
:global DHCPPoolStart "192.168.100.100"
:global DHCPPoolEnd "192.168.100.200"

# Monitor IPs for Dual-IP Failover (BOTH must fail to trigger failover)
:global ISP1MonitorIP1 "1.1.1.1"
:global ISP1MonitorIP2 "8.8.8.8"
:global ISP2MonitorIP1 "8.8.4.4"
:global ISP2MonitorIP2 "1.0.0.1"

# Failover Parameters
:global CheckInterval "3s"
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
:do { /system scheduler remove [find name="dual-ip-failover"] } on-error={}
:do { /interface bridge remove [find name=$LANInterface] } on-error={}
:delay 1s

# ==============================================================================
# ROUTING TABLES
# ==============================================================================
/routing table
add name=ISP1 fib comment=$ISP1Name
add name=ISP2 fib comment=$ISP2Name

# ==============================================================================
# BRIDGE CONFIGURATION
# ==============================================================================
/interface bridge
add name=$LANInterface comment="LAN Bridge"

/interface bridge port
:do { remove [find interface=$LANPort1] } on-error={}
:do { remove [find interface=$LANPort2] } on-error={}
:do { remove [find interface=$LANPort3] } on-error={}
add bridge=$LANInterface interface=$LANPort1 comment="LAN Port 1"
add bridge=$LANInterface interface=$LANPort2 comment="LAN Port 2"
add bridge=$LANInterface interface=$LANPort3 comment="LAN Port 3"

# ==============================================================================
# IP ADDRESS CONFIGURATION
# ==============================================================================
/ip address
:do { remove [find interface=$WAN1Interface] } on-error={}
:do { remove [find interface=$WAN2Interface] } on-error={}
:do { remove [find interface=$LANInterface] } on-error={}
add address=($WAN1Address . "/24") interface=$WAN1Interface comment="WAN1"
add address=($WAN2Address . "/24") interface=$WAN2Interface comment="WAN2"
add address=$LANAddress interface=$LANInterface comment="LAN"

# ==============================================================================
# DHCP SERVER CONFIGURATION
# ==============================================================================
/ip pool
:do { remove [find name="lan-dhcp-pool"] } on-error={}
add name=lan-dhcp-pool ranges=($DHCPPoolStart . "-" . $DHCPPoolEnd) comment="LAN DHCP Pool"

/ip dhcp-server
:do { remove [find name="lan-dhcp"] } on-error={}
add name=lan-dhcp interface=$LANInterface address-pool=lan-dhcp-pool disabled=no comment="LAN DHCP Server"

/ip dhcp-server network
:do { remove [find address=$LANSubnet] } on-error={}
add address=$LANSubnet gateway=$LANGateway dns-server=$LANGateway comment="LAN DHCP Network"

# ==============================================================================
# MANGLE RULES (PCC LOAD BALANCING)
# ==============================================================================
/ip firewall mangle

# Bypass Load Balancing for Local Subnets
add chain=prerouting dst-address=$WAN1Subnet action=accept comment="Local: WAN1 Subnet"
add chain=prerouting dst-address=$WAN2Subnet action=accept comment="Local: WAN2 Subnet"
add chain=prerouting dst-address=$LANSubnet action=accept comment="Local: LAN Subnet"

# Bypass PCC for Monitor IPs (Force Main Table)
add chain=prerouting dst-address=$ISP1MonitorIP1 action=accept comment="Bypass: Monitor IPs"
add chain=prerouting dst-address=$ISP1MonitorIP2 action=accept
add chain=prerouting dst-address=$ISP2MonitorIP1 action=accept
add chain=prerouting dst-address=$ISP2MonitorIP2 action=accept

# Bypass PCC for DNS and NTP (Use Main Table)
add chain=prerouting protocol=udp dst-port=53 action=accept comment="Bypass: DNS/NTP"
add chain=prerouting protocol=tcp dst-port=53 action=accept
add chain=prerouting protocol=udp dst-port=123 action=accept

# Bypass NTP for router stability
add chain=output protocol=udp dst-port=123 action=accept comment="Bypass: NTP"

# Calculate PCC Total
:local PCCTotal ($LBRatio1 + $LBRatio2)

# PCC Classification Loop
:local pccIndex 0
:while ($pccIndex < $LBRatio1) do={
    add chain=prerouting in-interface=$LANInterface connection-state=new connection-mark=no-mark \
        per-connection-classifier=("both-addresses:" . $PCCTotal . "/" . $pccIndex) \
        action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
        comment=("PCC: ISP1 (" . ($pccIndex + 1) . "/" . $PCCTotal . ")")
    :set pccIndex ($pccIndex + 1)
}

:while ($pccIndex < $PCCTotal) do={
    add chain=prerouting in-interface=$LANInterface connection-state=new connection-mark=no-mark \
        per-connection-classifier=("both-addresses:" . $PCCTotal . "/" . $pccIndex) \
        action=mark-connection new-connection-mark=ISP2_conn passthrough=yes \
        comment=("PCC: ISP2 (" . ($pccIndex + 1) . "/" . $PCCTotal . ")")
    :set pccIndex ($pccIndex + 1)
}

# Restore Connection Mark for Return Traffic
add chain=prerouting connection-state=established,related in-interface=$WAN1Interface connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Return: WAN1"

add chain=prerouting connection-state=established,related in-interface=$WAN2Interface connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP2_conn passthrough=yes \
    comment="Return: WAN2"



# Mark Routing based on Connection Mark
add chain=prerouting connection-mark=ISP1_conn in-interface=$LANInterface \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Route: ISP1"

add chain=prerouting connection-mark=ISP2_conn in-interface=$LANInterface \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Route: ISP2"

# Output Chain (Router Traffic)
add chain=output protocol=udp dst-port=53 connection-mark=no-mark \
    action=mark-connection new-connection-mark=ISP1_conn passthrough=yes \
    comment="Output: DNS Default"

add chain=output connection-mark=ISP1_conn \
    action=mark-routing new-routing-mark=ISP1 passthrough=no \
    comment="Output: ISP1"

add chain=output connection-mark=ISP2_conn \
    action=mark-routing new-routing-mark=ISP2 passthrough=no \
    comment="Output: ISP2"

# ==============================================================================
# NAT CONFIGURATION
# ==============================================================================
/ip firewall nat
add chain=srcnat out-interface=$WAN1Interface action=masquerade comment="NAT: WAN1"
add chain=srcnat out-interface=$WAN2Interface action=masquerade comment="NAT: WAN2"
add chain=srcnat src-address=$LANSubnet dst-address=$LANSubnet \
    action=masquerade comment="NAT: Hairpin"

# ==============================================================================
# FIREWALL RULES
# ==============================================================================
/ip firewall filter

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
# ROUTING CONFIGURATION (DUAL-IP FAILOVER)
# ==============================================================================
/ip route

# Host Routes for Monitor IPs
add dst-address=($ISP1MonitorIP1 . "/32") gateway=$WAN1Gateway scope=10 target-scope=10 comment=("Monitor: ISP1-1 (" . $ISP1MonitorIP1 . ")")
add dst-address=($ISP1MonitorIP2 . "/32") gateway=$WAN1Gateway scope=10 target-scope=10 comment=("Monitor: ISP1-2 (" . $ISP1MonitorIP2 . ")")
add dst-address=($ISP2MonitorIP1 . "/32") gateway=$WAN2Gateway scope=10 target-scope=10 comment=("Monitor: ISP2-1 (" . $ISP2MonitorIP1 . ")")
add dst-address=($ISP2MonitorIP2 . "/32") gateway=$WAN2Gateway scope=10 target-scope=10 comment=("Monitor: ISP2-2 (" . $ISP2MonitorIP2 . ")")

# Main Default Routes (controlled by scheduler script)
:if ($PreferredISP = "ISP1") do={
    add dst-address=0.0.0.0/0 gateway=$WAN1Gateway distance=1 comment="Default: ISP1"
    add dst-address=0.0.0.0/0 gateway=$WAN2Gateway distance=2 comment="Default: ISP2 (Backup)"
} else={
    add dst-address=0.0.0.0/0 gateway=$WAN2Gateway distance=1 comment="Default: ISP2"
    add dst-address=0.0.0.0/0 gateway=$WAN1Gateway distance=2 comment="Default: ISP1 (Backup)"
}

# Routing Table Entries with Cross-Failover
add dst-address=0.0.0.0/0 gateway=$WAN1Gateway routing-table=ISP1 distance=1 comment="Table ISP1: Primary"
add dst-address=0.0.0.0/0 gateway=$WAN2Gateway routing-table=ISP1 distance=2 comment="Table ISP1: Failover"

add dst-address=0.0.0.0/0 gateway=$WAN2Gateway routing-table=ISP2 distance=1 comment="Table ISP2: Primary"
add dst-address=0.0.0.0/0 gateway=$WAN1Gateway routing-table=ISP2 distance=2 comment="Table ISP2: Failover"

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

/system scheduler
add name=dual-ip-failover interval=3s start-time=startup on-event={
    # Import global variables
    :global ISP1MonitorIP1
    :global ISP1MonitorIP2
    :global ISP2MonitorIP1
    :global ISP2MonitorIP2
    :global WAN1Address
    :global WAN2Address
    :global WAN1Gateway
    :global WAN2Gateway
    :global FailureThreshold
    :global ISP1FailCount
    :global ISP2FailCount
    :global ISP1Status
    :global ISP2Status
    :global PreferredISP
    :global WAN1Interface
    :global WAN2Interface
    
    # Check ISP1 - Interface must be running AND BOTH IPs must fail
    :local wan1Running false
    :do {
        :set wan1Running ([/interface get $WAN1Interface running])
    } on-error={ :set wan1Running false }
    
    :local isp1ip1up false
    :local isp1ip2up false
    
    :if ($wan1Running) do={
        :do {
            :set isp1ip1up ([/ping $ISP1MonitorIP1 src-address=$WAN1Address count=1 interval=100ms] > 0)
        } on-error={ :set isp1ip1up false }
        :do {
            :set isp1ip2up ([/ping $ISP1MonitorIP2 src-address=$WAN1Address count=1 interval=100ms] > 0)
        } on-error={ :set isp1ip2up false }
    }
    
    :local isp1BothDown ((!$wan1Running) || ((!$isp1ip1up) && (!$isp1ip2up)))
    
    # Check ISP2 - Interface must be running AND BOTH IPs must fail
    :local wan2Running false
    :do {
        :set wan2Running ([/interface get $WAN2Interface running])
    } on-error={ :set wan2Running false }
    
    :local isp2ip1up false
    :local isp2ip2up false
    
    :if ($wan2Running) do={
        :do {
            :set isp2ip1up ([/ping $ISP2MonitorIP1 src-address=$WAN2Address count=1 interval=100ms] > 0)
        } on-error={ :set isp2ip1up false }
        :do {
            :set isp2ip2up ([/ping $ISP2MonitorIP2 src-address=$WAN2Address count=1 interval=100ms] > 0)
        } on-error={ :set isp2ip2up false }
    }
    
    :local isp2BothDown ((!$wan2Running) || ((!$isp2ip1up) && (!$isp2ip2up)))
    
    # ISP1 Logic
    :if ($isp1BothDown) do={
        :set ISP1FailCount ($ISP1FailCount + 1)
        :if (($ISP1FailCount >= $FailureThreshold) && ($ISP1Status = "up")) do={
            :set ISP1Status "down"
            :log error "[FAILOVER] ISP1 DOWN - Both monitors failed"
            :if ($PreferredISP = "ISP1") do={
                /ip route disable [find comment="Default: ISP1"]
            } else={
                /ip route disable [find comment="Default: ISP1 (Backup)"]
            }
            /ip route disable [find comment="Table ISP1: Primary"]
            /ip firewall connection remove [find connection-mark=ISP1_conn]
        }
    } else={
        :if ($ISP1Status = "down") do={
            :set ISP1Status "up"
            :set ISP1FailCount 0
            :log info "[FAILOVER] ISP1 UP - Recovered"
            :if ($PreferredISP = "ISP1") do={
                /ip route enable [find comment="Default: ISP1"]
            } else={
                /ip route enable [find comment="Default: ISP1 (Backup)"]
            }
            /ip route enable [find comment="Table ISP1: Primary"]
        } else={
            :set ISP1FailCount 0
        }
    }
    
    # ISP2 Logic
    :if ($isp2BothDown) do={
        :set ISP2FailCount ($ISP2FailCount + 1)
        :if (($ISP2FailCount >= $FailureThreshold) && ($ISP2Status = "up")) do={
            :set ISP2Status "down"
            :log error "[FAILOVER] ISP2 DOWN - Both monitors failed"
            :if ($PreferredISP = "ISP2") do={
                /ip route disable [find comment="Default: ISP2"]
            } else={
                /ip route disable [find comment="Default: ISP2 (Backup)"]
            }
            /ip route disable [find comment="Table ISP2: Primary"]
            /ip firewall connection remove [find connection-mark=ISP2_conn]
        }
    } else={
        :if ($ISP2Status = "down") do={
            :set ISP2Status "up"
            :set ISP2FailCount 0
            :log info "[FAILOVER] ISP2 UP - Recovered"
            :if ($PreferredISP = "ISP2") do={
                /ip route enable [find comment="Default: ISP2"]
            } else={
                /ip route enable [find comment="Default: ISP2 (Backup)"]
            }
            /ip route enable [find comment="Table ISP2: Primary"]
        } else={
            :set ISP2FailCount 0
        }
    }
}

# ==============================================================================
# SERVICE HARDENING (SECURITY)
# ==============================================================================
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set www-ssl disabled=yes
set ssh disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox address=$LANSubnet disabled=no

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
:put ("  Monitor IPs: " . $ISP1MonitorIP1 . " AND " . $ISP1MonitorIP2)
:put ("ISP2: " . $ISP2Name . " (" . $WAN2Interface . ")")
:put ("  Monitor IPs: " . $ISP2MonitorIP1 . " AND " . $ISP2MonitorIP2)
:put ("Load Balance Ratio: " . $LBRatio1 . ":" . $LBRatio2)
:put ""
:put "Failover Logic: BOTH monitor IPs must fail to trigger ISP failover"
:put ("Failure Threshold: " . $FailureThreshold . " consecutive checks")
:put ""
:put "Next Steps:"
:put "1. Verify interfaces are connected."
:put "2. Check routes: /ip route print"
:put "3. Check scheduler: /system scheduler print detail where name=dual-ip-failover"
:put "4. Monitor failover: /log print follow where message~\"FAILOVER\""
:put "5. Check all logs: /log print follow where topics~\"error,warning,info\""
:put ""
:put ("Security: WinBox access restricted to LAN (" . $LANSubnet . ") only")
:put ""
