# ipv6-setup.rsc
# Importar DEPOIS do mikrotik-dual-wan-ecmp.rsc e vivo-pppoe.rsc
# Habilita IPv6 dual-stack com NAT66 nas duas WANs (ECMP via conntrack pinning).
#
# Topologia:
#   - Vivo (pppoe-vivo): DHCPv6-PD recebe /64 da Vivo + SLAAC WAN address
#   - Claro (sfp1): SLAAC publico /64 (sem PD)
#   - LAN (bridge-lan): ULA fd64:1e57:9364:1::/64, RA pra clientes
#   - NAT66 masquerade nas duas WANs (resolve uRPF do BNG)
#
# Gotcha: IPv6CP no PPPoE so negocia se IPv6 stack estiver ON na hora do connect.
# Por isso este script reconecta pppoe-vivo (Vivo cai ~10s).
#
# Rollback: /import scripts/ipv6-rollback.rsc

:local lVivoIf "pppoe-vivo"
:local lClaroIf "sfp1"
:local lLanIf "bridge-lan"
:local lLanULA "fd64:1e57:9364:1::1/64"
:local lLanULAPrefix "fd64:1e57:9364:1::/64"

:put "Configurando IPv6 dual-stack..."

# --- 1. Limpa regra do script principal que rejeita IPv6 forward ---
:do { /ipv6 firewall filter remove [find where comment~"Reject: All IPv6 forward"] } on-error={}

# --- 2. Stack IPv6 ---
# accept-RA whitelist nas WANs (nao LAN — evita rogue RA injection).
# forward=yes pra router rotear IPv6 entre interfaces.
/ipv6 settings set disable-ipv6=no forward=yes disable-link-local-address=no accept-router-advertisements=yes accept-router-advertisements-on=($lClaroIf . "," . $lVivoIf)

# --- 3. Reconnect pppoe-vivo pra forcar IPv6CP ---
# Pula se pppoe-vivo nao existir (script principal puro, sem vivo-pppoe.rsc).
# Sem IPv6CP, DHCPv6 nunca completa.
:if ([:len [/interface pppoe-client find where name=$lVivoIf]] > 0) do={
    :put "Reconectando $lVivoIf (Vivo cai ~10s)..."
    /interface pppoe-client disable [find name=$lVivoIf]
    :delay 3s
    /interface pppoe-client enable [find name=$lVivoIf]
    :delay 12s
}

# --- 4. DHCPv6 client Vivo (request=prefix) ---
:do { /ipv6 dhcp-client remove [find where comment~"DHCPv6: Vivo"] } on-error={}
/ipv6 dhcp-client add interface=$lVivoIf request=prefix add-default-route=yes default-route-distance=1 use-peer-dns=no pool-name=vivo-pd6 pool-prefix-length=64 comment="DHCPv6: Vivo PD"

# Claro: SLAAC e default route automaticos via accept-RA whitelist (acima), nada a configurar.

# --- 5. LAN: ULA + ND/RA ---
# advertise=yes faz hosts LAN derivarem endereco SLAAC do prefixo /64.
:do { /ipv6 address remove [find where comment~"IPv6: LAN ULA"] } on-error={}
/ipv6 address add address=$lLanULA interface=$lLanIf advertise=yes comment="IPv6: LAN ULA"

# SLAAC puro: managed=no other=no (sem DHCPv6 server na LAN).
:do { /ipv6 nd remove [find where interface=$lLanIf and !default] } on-error={}
/ipv6 nd add interface=$lLanIf advertise-mac-address=yes managed-address-configuration=no other-configuration=no comment="IPv6: LAN RA"

# --- 6. Address-list LocalTraffic6 (espelho IPv4 LocalTraffic) ---
:do { /ipv6 firewall address-list remove [find where list="LocalTraffic6"] } on-error={}
/ipv6 firewall address-list add list=LocalTraffic6 address=$lLanULAPrefix comment="LAN ULA"

# --- 7. NAT66 masquerade nas duas WANs ---
# Conntrack mantem cada conexao pinned na WAN escolhida pelo ECMP hash.
# Resolve uRPF: pacote sai com src=address da WAN de saida, nunca cross-WAN.
:do { /ipv6 firewall nat remove [find where comment~"NAT66"] } on-error={}
/ipv6 firewall nat add chain=srcnat out-interface=$lVivoIf action=masquerade comment="NAT66: Vivo masquerade"
/ipv6 firewall nat add chain=srcnat out-interface=$lClaroIf action=masquerade comment="NAT66: Claro masquerade"

# --- 8. Firewall IPv6 input ---
# Espelho do IPv4 com diferencas:
#   - Sem accept management (ssh/www/winbox) IPv6 — fica IPv4-only
#   - ICMPv6 nao pode rate-limitar inteiro (NDP/MLD essenciais); rate-limit so echo-request
#   - Accept link-local source (fe80::/10) necessario pra NDP
#   - Accept DHCPv6 client reply (UDP 546) pra receber PD da Vivo
:do { /ipv6 firewall filter remove [find where chain=input] } on-error={}
/ipv6 firewall filter add chain=input action=drop connection-state=invalid comment="Drop: Invalid Input"
/ipv6 firewall filter add chain=input action=accept connection-state=established,related,untracked comment="Accept: Established Input"
/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 icmp-options=133:0,134:0,135:0,136:0,141:0,142:0 comment="Accept: NDP"
/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 icmp-options=130:0,131:0,132:0,143:0 comment="Accept: MLD"
/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 icmp-options=1:0-255,2:0,3:0-255,4:0-255 comment="Accept: ICMPv6 errors"
/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 icmp-options=128:0 limit=50,5:packet comment="Limit: ICMPv6 echo-request"
/ipv6 firewall filter add chain=input action=drop protocol=icmpv6 icmp-options=128:0 comment="Drop: Excess ICMPv6 echo"
/ipv6 firewall filter add chain=input action=accept src-address=fe80::/10 comment="Accept: Link-local Source"
/ipv6 firewall filter add chain=input action=accept in-interface=$lLanIf comment="Accept: LAN Input"
/ipv6 firewall filter add chain=input action=accept protocol=udp dst-port=546 comment="Accept: DHCPv6 client"
/ipv6 firewall filter add chain=input action=drop comment="Drop: WAN Input (default)"

# --- 9. Firewall IPv6 forward + FastTrack ---
# FastTrack ANTES de qualquer outra regra (matched conns bypassam conntrack/firewall).
# Drop invalid logo depois pra rejeitar conns malformadas que escaparam FastTrack.
:do { /ipv6 firewall filter remove [find where chain=forward] } on-error={}
/ipv6 firewall filter add chain=forward action=fasttrack-connection connection-state=established,related comment="FastTrack: Established/Related"
/ipv6 firewall filter add chain=forward action=drop connection-state=invalid comment="Drop: Invalid Forward"
/ipv6 firewall filter add chain=forward action=accept connection-state=established,related,untracked comment="Accept: Established Forward"
/ipv6 firewall filter add chain=forward action=accept src-address-list=LocalTraffic6 comment="Accept: LAN New Forward"
/ipv6 firewall filter add chain=forward action=accept protocol=icmpv6 hop-limit=equal:1 comment="Accept: ICMPv6 link-local hops"
/ipv6 firewall filter add chain=forward action=drop comment="Drop: All Other Forward"
