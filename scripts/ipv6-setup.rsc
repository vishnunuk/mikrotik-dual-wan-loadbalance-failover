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
