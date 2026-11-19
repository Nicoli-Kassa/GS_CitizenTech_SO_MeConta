#!/usr/bin/env bash
# Relatório de auditoria do servidor Me Conta: quem fez o quê, quando.
# Uso: sudo bash linux/ferramentas/auditoria.sh [horas]   (padrão: últimas 24 horas)
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }

HORAS="${1:-24}"
# O ausearch lê datas no formato do locale; com LC_TIME=C o formato é mm/dd/aa.
export LC_TIME=C
DESDE_DATA="$(date -d "-${HORAS} hours" '+%m/%d/%y')"
DESDE_HORA="$(date -d "-${HORAS} hours" '+%H:%M:%S')"
AZUL=$'\e[1;34m'; SEM_COR=$'\e[0m'
[[ -t 1 ]] || { AZUL=""; SEM_COR=""; }
secao() { echo; echo "${AZUL}## $1${SEM_COR}"; }

echo "Relatório de auditoria de $(hostname) - últimas ${HORAS} h (gerado em $(date '+%d/%m/%Y %H:%M:%S'))"

secao "Logins por SSH"
journalctl -u ssh --since "-${HORAS}h" --no-pager -o short-iso 2> /dev/null \
    | grep -E 'Accepted|Failed|Invalid user' | tail -n 10 | sed 's/^/  /' || true

secao "Mudanças monitoradas pelo auditd (por chave)"
for chave in identidade privilegios ssh rede firewall meconta-config meconta-segredos meconta-servicos meconta-publicacao nginx meconta-logs; do
    total="$(ausearch -k "$chave" -ts "$DESDE_DATA" "$DESDE_HORA" 2> /dev/null | grep -c '^type=SYSCALL' || true)"
    printf '  %-20s %s eventos\n' "$chave" "$total"
done

secao "Últimas alterações em arquivos observados (data, hora, arquivo, syscall, ok?, programa, usuário)"
for chave in identidade privilegios ssh rede firewall meconta-config meconta-segredos meconta-servicos nginx; do
    ausearch -k "$chave" -ts "$DESDE_DATA" "$DESDE_HORA" --raw 2> /dev/null | aureport -f -i 2> /dev/null | grep -E '^[0-9]+\.'
done | sort -k2,3 | tail -n 12 | sed 's/^/  /' || true

secao "Serviços parados, iniciados ou reiniciados por pessoas (systemctl)"
ausearch -k systemctl -ts "$DESDE_DATA" "$DESDE_HORA" -i 2> /dev/null \
    | grep '^type=EXECVE' | sed -E 's/.*msg=audit\(([^)]+)\).*a0=[^ ]+ (.*)/  \1 | systemctl \2/; s/a[0-9]+=//g' | tail -n 10 || true

secao "Comandos com sudo"
journalctl _COMM=sudo --since "-${HORAS}h" --no-pager -o short-iso 2> /dev/null \
    | grep 'COMMAND=' | sed -E 's/^([^ ]+) [^:]+: +([^ ]+) : .*COMMAND=(.*)/  \1 | \2 | \3/' | tail -n 10 || true

secao "Reinícios automáticos (systemd e monitor)"
journalctl -u meconta-api -u meconta-monitor --since "-${HORAS}h" --no-pager -o short-iso 2> /dev/null \
    | grep -E 'Scheduled restart|Main process exited|Watchdog timeout|Started' | tail -n 10 | sed 's/^/  /' || true
grep -E '\| (ACAO|ALERTA)' /var/log/meconta/alertas.log 2> /dev/null | tail -n 10 | sed 's/^/  /' || true

secao "Provisionamento (últimas ações)"
grep -vE '\| INFO ' /var/log/meconta/provisionamento.log 2> /dev/null | tail -n 10 | sed 's/^/  /' || true

secao "Acessos à API (nginx): status HTTP nas últimas ${HORAS} h"
if [[ -r /var/log/nginx/meconta-acesso.log ]]; then
    limite="$(date -d "-${HORAS} hours" '+%Y-%m-%dT%H:%M:%S')"
    awk -v limite="$limite" 'substr($1, 1, 19) >= limite {match($0, /status=[0-9]+/); s[substr($0, RSTART+7, RLENGTH-7)]++}
         END {for (k in s) printf "  %s: %d requisições\n", k, s[k]}' /var/log/nginx/meconta-acesso.log | sort
    echo "  tentativas de login bloqueadas pelo limite (429): $(grep -c 'caminho=/api/v1/auth/login status=429' /var/log/nginx/meconta-acesso.log)"
fi
