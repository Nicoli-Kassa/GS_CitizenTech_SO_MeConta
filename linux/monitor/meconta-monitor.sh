#!/usr/bin/env bash
# =============================================================================
# meconta-monitor: monitoramento do servidor do Me Conta
#
# A cada INTERVALO_SEGUNDOS mede CPU, memória e disco e confere a saúde da API.
#   - Uso acima do limite por LEITURAS_PARA_ALERTAR leituras seguidas -> ALERTA
#     (log, journal, mensagem no terminal de quem estiver logado e webhook opcional).
#   - Quando volta ao normal -> NORMAL (fecha o alerta).
#   - /health da API falhando FALHAS_DE_SAUDE_PARA_REINICIAR vezes -> ACAO: reinicia a API.
#
# Roda como serviço systemd (meconta-monitor.service) com watchdog: se o próprio monitor
# travar ou cair, o systemd o reinicia. Configuração em /etc/meconta/monitor.conf
# (recarregada sem parar o serviço com: systemctl reload meconta-monitor).
#
# Uso manual: meconta-monitor --uma-vez   (mede uma vez e mostra na tela)
# =============================================================================
set -uo pipefail

ARQUIVO_DE_CONFIGURACAO="${MECONTA_MONITOR_CONF:-/etc/meconta/monitor.conf}"
PASTA_DE_LOGS="${MECONTA_PASTA_DE_LOGS:-/var/log/meconta}"
LOG_DE_ALERTAS="${PASTA_DE_LOGS}/alertas.log"
LOG_DE_METRICAS="${PASTA_DE_LOGS}/metricas.log"
ARQUIVO_DE_ESTADO="${RUNTIME_DIRECTORY:-/run/meconta-monitor}/status.json"

carregar_configuracao() {
    # Valores padrão, sobrescritos pelo arquivo de configuração.
    LIMITE_CPU=80; LIMITE_MEMORIA=80; LIMITE_DISCO=80
    INTERVALO_SEGUNDOS=10; LEITURAS_PARA_ALERTAR=3; FALHAS_DE_SAUDE_PARA_REINICIAR=3
    URL_DE_SAUDE="http://127.0.0.1:5000/health"; ALERTA_WEBHOOK=""
    # shellcheck source=/dev/null
    [[ -r "$ARQUIVO_DE_CONFIGURACAO" ]] && source "$ARQUIVO_DE_CONFIGURACAO"
}

agora() { date '+%Y-%m-%d %H:%M:%S'; }

avisar_systemd() {
    # Só fala com o systemd quando roda como serviço (NOTIFY_SOCKET existe).
    [[ -n "${NOTIFY_SOCKET:-}" ]] && systemd-notify "$@" 2> /dev/null
    return 0
}

# ---------------------------------------------------------------------------
# Medições
# ---------------------------------------------------------------------------
CPU_TOTAL_ANTERIOR=0
CPU_OCIOSO_ANTERIOR=0

# % de CPU usada desde a última leitura, a partir dos contadores do kernel em /proc/stat.
medir_cpu() {
    local _ usuario nice sistema ocioso espera irq softirq roubado total ocioso_total
    read -r _ usuario nice sistema ocioso espera irq softirq roubado _ < /proc/stat
    total=$((usuario + nice + sistema + ocioso + espera + irq + softirq + roubado))
    ocioso_total=$((ocioso + espera))
    local delta_total=$((total - CPU_TOTAL_ANTERIOR))
    local delta_ocioso=$((ocioso_total - CPU_OCIOSO_ANTERIOR))
    CPU_TOTAL_ANTERIOR=$total
    CPU_OCIOSO_ANTERIOR=$ocioso_total
    if ((delta_total <= 0)); then echo 0; return; fi
    echo $(((100 * (delta_total - delta_ocioso)) / delta_total))
}

# % de memória em uso: (total - disponível) / total, de /proc/meminfo.
medir_memoria() {
    awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {d=$2} END {printf "%d\n", (t-d)*100/t}' /proc/meminfo
}

# % do disco raiz em uso (onde ficam o banco e os áudios).
medir_disco() {
    df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}'
}

conferir_api() {
    if curl -fsS -m 3 "$URL_DE_SAUDE" > /dev/null 2>&1; then echo ok; else echo falhou; fi
}

processo_que_mais_usa() {
    # $1 = %cpu ou %mem
    ps -eo comm,pid,"$1" --sort=-"$1" --no-headers | head -n1 | awk '{printf "%s (PID %s, %s%%)", $1, $2, $3}'
}

# ---------------------------------------------------------------------------
# Alertas
# ---------------------------------------------------------------------------
declare -A LEITURAS_ACIMA=([cpu]=0 [memoria]=0 [disco]=0)
declare -A EM_ALERTA=([cpu]=0 [memoria]=0 [disco]=0)
FALHAS_DE_SAUDE=0

registrar_evento() {
    # $1 = ALERTA | NORMAL | ACAO | INFO, $2 = recurso, $3 = mensagem
    local tipo="$1" recurso="$2" mensagem="$3" prioridade=info
    [[ "$tipo" == "ALERTA" || "$tipo" == "ACAO" ]] && prioridade=warning
    printf '%s | %-6s | %-7s | %s\n' "$(agora)" "$tipo" "$recurso" "$mensagem" >> "$LOG_DE_ALERTAS"
    logger -t meconta-monitor -p "user.${prioridade}" "${tipo} ${recurso}: ${mensagem}"

    if [[ "$tipo" == "ALERTA" || "$tipo" == "ACAO" ]]; then
        # Aparece no terminal de quem estiver conectado por SSH.
        echo "[Me Conta] ${tipo} ${recurso} em $(hostname): ${mensagem}" | wall 2> /dev/null || true
    fi
    if [[ -n "$ALERTA_WEBHOOK" && "$tipo" != "INFO" ]]; then
        curl -fsS -m 5 -H "Title: Me Conta ${tipo} ${recurso}" \
            -d "$(hostname): ${mensagem}" "$ALERTA_WEBHOOK" > /dev/null 2>&1 &
    fi
}

avaliar() {
    # $1 = recurso, $2 = valor medido, $3 = limite
    local recurso="$1" valor="$2" limite="$3"
    if ((valor >= limite)); then
        LEITURAS_ACIMA[$recurso]=$((LEITURAS_ACIMA[$recurso] + 1))
        if ((LEITURAS_ACIMA[$recurso] >= LEITURAS_PARA_ALERTAR && EM_ALERTA[$recurso] == 0)); then
            EM_ALERTA[$recurso]=1
            local detalhe=""
            [[ "$recurso" == "cpu" ]] && detalhe="; maior consumo: $(processo_que_mais_usa %cpu)"
            [[ "$recurso" == "memoria" ]] && detalhe="; maior consumo: $(processo_que_mais_usa %mem)"
            registrar_evento ALERTA "$recurso" "uso em ${valor}%, acima do limite de ${limite}% (${LEITURAS_ACIMA[$recurso]} leituras seguidas)${detalhe}"
        fi
    else
        LEITURAS_ACIMA[$recurso]=0
        if ((EM_ALERTA[$recurso] == 1)); then
            EM_ALERTA[$recurso]=0
            registrar_evento NORMAL "$recurso" "uso voltou para ${valor}% (limite ${limite}%)"
        fi
    fi
}

avaliar_api() {
    local estado="$1"
    if [[ "$estado" == "ok" ]]; then
        if ((FALHAS_DE_SAUDE >= FALHAS_DE_SAUDE_PARA_REINICIAR)); then
            registrar_evento NORMAL api "a API voltou a responder no /health"
        fi
        FALHAS_DE_SAUDE=0
        return
    fi
    FALHAS_DE_SAUDE=$((FALHAS_DE_SAUDE + 1))
    if ((FALHAS_DE_SAUDE == FALHAS_DE_SAUDE_PARA_REINICIAR)); then
        registrar_evento ACAO api "/health falhou ${FALHAS_DE_SAUDE} vezes seguidas; reiniciando meconta-api"
        systemctl restart --no-block meconta-api.service 2> /dev/null \
            || registrar_evento ALERTA api "não consegui reiniciar meconta-api"
    fi
}

# ---------------------------------------------------------------------------
# Estado para o painel (/servidor/status.json)
# ---------------------------------------------------------------------------
gravar_estado() {
    local cpu="$1" memoria="$2" disco="$3" api="$4" temporario
    temporario="${ARQUIVO_DE_ESTADO}.tmp"
    jq -n \
        --arg servidor "$(hostname)" --arg horario "$(agora)" \
        --argjson cpu "$cpu" --argjson memoria "$memoria" --argjson disco "$disco" \
        --argjson limite_cpu "$LIMITE_CPU" --argjson limite_memoria "$LIMITE_MEMORIA" --argjson limite_disco "$LIMITE_DISCO" \
        --arg api "$api" \
        --arg servico_api "$(systemctl is-active meconta-api.service 2> /dev/null)" \
        --arg servico_nginx "$(systemctl is-active nginx.service 2> /dev/null)" \
        --arg ligado_desde "$(uptime -s)" \
        --arg carga "$(cut -d' ' -f1-3 /proc/loadavg)" \
        --argjson alertas "$(tail -n 8 "$LOG_DE_ALERTAS" 2> /dev/null | jq -R . | jq -s 'reverse')" \
        '{servidor: $servidor, horario: $horario, ligado_desde: $ligado_desde, carga: $carga,
          recursos: {cpu: {uso: $cpu, limite: $limite_cpu}, memoria: {uso: $memoria, limite: $limite_memoria},
                     disco: {uso: $disco, limite: $limite_disco}},
          servicos: {api_health: $api, "meconta-api": $servico_api, nginx: $servico_nginx},
          ultimos_eventos: $alertas}' > "$temporario" && mv -f "$temporario" "$ARQUIVO_DE_ESTADO"
}

# ---------------------------------------------------------------------------
# Laço principal
# ---------------------------------------------------------------------------
uma_vez() {
    carregar_configuracao
    medir_cpu > /dev/null
    sleep 1
    printf 'CPU %s%% | memória %s%% | disco %s%% | API %s\n' \
        "$(medir_cpu)" "$(medir_memoria)" "$(medir_disco)" "$(conferir_api)"
}

monitorar() {
    carregar_configuracao
    mkdir -p "$PASTA_DE_LOGS" "$(dirname "$ARQUIVO_DE_ESTADO")"
    trap 'carregar_configuracao; registrar_evento INFO monitor "configuração recarregada"; avisar_systemd --ready' HUP
    trap 'registrar_evento INFO monitor "monitor parado (PID $$)"; exit 0' TERM INT

    medir_cpu > /dev/null
    registrar_evento INFO monitor "monitor iniciado (PID $$): limites CPU ${LIMITE_CPU}%, memória ${LIMITE_MEMORIA}%, disco ${LIMITE_DISCO}%, a cada ${INTERVALO_SEGUNDOS} s"
    avisar_systemd --ready --status="monitorando"

    while true; do
        sleep "$INTERVALO_SEGUNDOS" & wait $!
        local cpu memoria disco api
        cpu="$(medir_cpu)"; memoria="$(medir_memoria)"; disco="$(medir_disco)"; api="$(conferir_api)"

        echo "$(agora) cpu=${cpu} memoria=${memoria} disco=${disco} api=${api}" >> "$LOG_DE_METRICAS"
        avaliar cpu "$cpu" "$LIMITE_CPU"
        avaliar memoria "$memoria" "$LIMITE_MEMORIA"
        avaliar disco "$disco" "$LIMITE_DISCO"
        avaliar_api "$api"
        gravar_estado "$cpu" "$memoria" "$disco" "$api"

        # "Estou vivo": se esta linha parar de chegar, o watchdog do systemd reinicia o monitor.
        avisar_systemd WATCHDOG=1 --status="CPU ${cpu}% | memória ${memoria}% | disco ${disco}% | API ${api}"
    done
}

case "${1:-}" in
    --uma-vez) uma_vez ;;
    "") monitorar ;;
    *) echo "uso: $0 [--uma-vez]" >&2; exit 2 ;;
esac
