#!/usr/bin/env bash
# Etapa 5: monitoramento de CPU, memória e disco, rodando como serviço tolerante a falhas.

etapa_monitoramento() {
    titulo "5/6 monitoramento" "meconta-monitor (CPU, memória, disco e saúde da API)"
    local mudou=1 temporario

    instalar_arquivo "${PASTA_DOS_SCRIPTS}/monitor/meconta-monitor.sh" /usr/local/sbin/meconta-monitor 0755 && mudou=0

    temporario="$(mktemp)"
    cat > "$temporario" << EOF
# Gerado por linux/etapas/monitoramento.sh a partir do meconta.conf.
# Depois de editar: systemctl reload meconta-monitor
LIMITE_CPU=${LIMITE_CPU}
LIMITE_MEMORIA=${LIMITE_MEMORIA}
LIMITE_DISCO=${LIMITE_DISCO}
INTERVALO_SEGUNDOS=${INTERVALO_SEGUNDOS}
LEITURAS_PARA_ALERTAR=${LEITURAS_PARA_ALERTAR}
FALHAS_DE_SAUDE_PARA_REINICIAR=${FALHAS_DE_SAUDE_PARA_REINICIAR}
URL_DE_SAUDE="http://127.0.0.1:${PORTA_INTERNA_DA_API}/health"
ALERTA_WEBHOOK="${ALERTA_WEBHOOK}"
EOF
    instalar_arquivo "$temporario" "${PASTA_DE_CONFIGURACAO}/monitor.conf" 0640 root:root && mudou=0
    rm -f "$temporario"

    instalar_arquivo "${PASTA_DOS_SCRIPTS}/arquivos/meconta-monitor.service" /etc/systemd/system/meconta-monitor.service 0644 && mudou=0
    systemctl daemon-reload
    systemctl enable --quiet meconta-monitor.service
    if ((mudou == 0)) || ! systemctl is-active --quiet meconta-monitor.service; then
        systemctl restart meconta-monitor.service
    fi

    # Espera a primeira medição chegar ao status.json.

    for _ in $(seq 1 10); do
        [[ -s /run/meconta-monitor/status.json ]] && break
        sleep $((INTERVALO_SEGUNDOS / 5 + 1))
    done

    systemctl is-active --quiet meconta-monitor.service || falhar "meconta-monitor não está ativo (journalctl -u meconta-monitor)"
    ok "meconta-monitor ativo: $(systemctl show -p StatusText --value meconta-monitor.service)"
    ok "limites: CPU ${LIMITE_CPU}% | memória ${LIMITE_MEMORIA}% | disco ${LIMITE_DISCO}% | medição a cada ${INTERVALO_SEGUNDOS} s"
    ok "alertas em ${PASTA_DE_LOGS}/alertas.log; métricas em ${PASTA_DE_LOGS}/metricas.log; painel em http://${NOME_PUBLICO}/servidor/"
}
