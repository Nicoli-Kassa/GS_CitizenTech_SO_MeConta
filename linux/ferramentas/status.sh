#!/usr/bin/env bash
# Resumo do servidor Me Conta: identidade, rede, serviços, recursos, alertas e versão publicada.
# Uso: sudo bash linux/ferramentas/status.sh
set -uo pipefail

AZUL=$'\e[1;34m'; VERDE=$'\e[1;32m'; VERMELHO=$'\e[1;31m'; SEM_COR=$'\e[0m'
[[ -t 1 ]] || { AZUL=""; VERDE=""; VERMELHO=""; SEM_COR=""; }
secao() { echo; echo "${AZUL}## $1${SEM_COR}"; }
estado() {
    local situacao
    situacao="$(systemctl is-active "$1" 2> /dev/null)"
    if [[ "$situacao" == "active" ]]; then
        printf '  %-18s %s%s%s (habilitado no boot: %s)\n' "$1" "$VERDE" "$situacao" "$SEM_COR" "$(systemctl is-enabled "$1" 2> /dev/null)"
    else
        printf '  %-18s %s%s%s\n' "$1" "$VERMELHO" "$situacao" "$SEM_COR"
    fi
}

secao "Servidor"
echo "  hostname:  $(hostname)  |  FQDN: $(hostname -f 2> /dev/null)"
echo "  sistema:   $(. /etc/os-release && echo "$PRETTY_NAME"), kernel $(uname -r)"
echo "  ligado há: $(uptime -p | sed 's/^up //')  |  carga: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "  horário:   $(date '+%d/%m/%Y %H:%M:%S %Z')"

secao "Rede"
ip -br -4 addr show scope global | sed 's/^/  /'
echo "  gateway:   $(ip -4 route show default | awk '{print $3}')"
echo "  DNS:       $(resolvectl dns 2> /dev/null | awk -F': ' 'NF > 1 && $2 != "" {print $2}' | head -n1)"
[[ -r /etc/meconta/ip-publico ]] && echo "  IP público: $(cat /etc/meconta/ip-publico)"
echo "  firewall:  $(ufw status 2> /dev/null | head -n1)"

secao "Serviços"
for servico in meconta-api meconta-monitor nginx auditd ssh; do estado "$servico"; done
echo "  /health:   $(curl -fsS -m 3 http://127.0.0.1/health 2> /dev/null || echo 'sem resposta')"
[[ -r /opt/meconta/app/VERSAO ]] && echo "  versão:    commit $(cat /opt/meconta/app/VERSAO) em $(readlink -f /opt/meconta/app)"

secao "Recursos (monitor)"
if command -v meconta-monitor > /dev/null; then
    echo "  $(meconta-monitor --uma-vez)"
fi
free -h | sed 's/^/  /'
df -h / | sed 's/^/  /'

secao "Últimos eventos do monitor"
if [[ -r /var/log/meconta/alertas.log ]]; then
    tail -n 8 /var/log/meconta/alertas.log | sed 's/^/  /'
else
    echo "  (sem eventos)"
fi
