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
