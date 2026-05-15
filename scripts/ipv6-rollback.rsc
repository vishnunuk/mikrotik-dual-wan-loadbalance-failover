# ipv6-rollback.rsc
# Reverte ipv6-setup.rsc - volta IPv6 desabilitado (estado pos-mikrotik-dual-wan-ecmp.rsc).
#
# Uso: /import scripts/ipv6-rollback.rsc

:put "Revertendo IPv6..."

# DHCPv6 client
:do { /ipv6 dhcp-client remove [find where comment~"DHCPv6: Vivo"] } on-error={}

# LAN address + ND (restaura default nd entry que o setup desabilitou)
:do { /ipv6 address remove [find where comment~"IPv6: LAN ULA"] } on-error={}
:do { /ipv6 address remove [find where comment="IPv6: Vivo PD-derived WAN"] } on-error={}
:do { /ipv6 nd remove [find where comment~"IPv6: LAN RA"] } on-error={}
:do { /ipv6 nd set [find default=yes] disabled=no } on-error={}

# Address-list
:do { /ipv6 firewall address-list remove [find where list="LocalTraffic6"] } on-error={}

# NAT66
:do { /ipv6 firewall nat remove [find where comment~"NAT66"] } on-error={}

# Firewall input + forward
:do { /ipv6 firewall filter remove [find where chain=input and dynamic=no] } on-error={}
:do { /ipv6 firewall filter remove [find where chain=forward and dynamic=no] } on-error={}

# Firewall raw (bogons + DoT + SYN rate-limit)
:do { /ipv6 firewall raw remove [find where comment~"IPv6 bogon" or comment~"IPv6: Block DoT" or comment~"IPv6 SYN"] } on-error={}

# Pool dinamico (removido junto com dhcp-client mas garantia)
:do { /ipv6 pool remove [find where name="vivo-pd6"] } on-error={}

# Recria regra reject all forward (igual mikrotik-dual-wan-ecmp.rsc)
:do { /ipv6 firewall filter add chain=forward action=reject reject-with=icmp-no-route comment="Reject: All IPv6 forward (no IPv6 firewall configured)" } on-error={}

# Desabilita stack
/ipv6 settings set disable-ipv6=yes disable-link-local-address=yes forward=no accept-router-advertisements=yes-if-forwarding-disabled accept-router-advertisements-on=all

:put "IPv6 desabilitado. Estado igual apos mikrotik-dual-wan-ecmp.rsc."
:put "Nota: addresses/rotas dinamicas cached podem aparecer como 'I' (invalid) ate TTL expirar - inofensivo."
