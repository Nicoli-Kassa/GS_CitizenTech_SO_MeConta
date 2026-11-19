#!/usr/bin/env bash
# Etapa 1: sistema base (fuso horário, pacotes e swap).

etapa_sistema() {
    titulo "1/6 sistema" "fuso horário, pacotes e swap"

    # Fuso horário: os logs e os alertas ficam no horário de Brasília.
    if [[ "$(timedatectl show -p Timezone --value)" != "$FUSO_HORARIO" ]]; then
        timedatectl set-timezone "$FUSO_HORARIO"
    fi
    timedatectl set-ntp true
    ok "fuso horário: $(timedatectl show -p Timezone --value), relógio sincronizado por NTP"

    passo "atualizando a lista de pacotes"
    apt-get update -qq
    # Ferramentas usadas pelas outras etapas:
    #   curl/jq: chamadas HTTP e JSON | git: baixar o código | sqlite3: inspecionar o banco
    #   nginx: servidor web | ufw: firewall | auditd: auditoria | stress-ng: teste de falha
    instalar_pacotes curl jq git sqlite3 nginx ufw auditd stress-ng ca-certificates
    ok "pacotes base instalados"

    # Swap: a Standard_B1s tem só 1 GB de RAM; o swap evita que o build do .NET seja morto por falta de memória.
    if ! swapon --show=NAME --noheadings | grep -q '^/swapfile$'; then
        passo "criando /swapfile de ${TAMANHO_SWAP_GB} GB"
        fallocate -l "${TAMANHO_SWAP_GB}G" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile > /dev/null
        swapon /swapfile
    fi
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo 'vm.swappiness=10' > /etc/sysctl.d/60-meconta.conf
    sysctl -q -p /etc/sysctl.d/60-meconta.conf
    ok "swap ativo: $(swapon --show=SIZE --noheadings /swapfile | tr -d ' ')"

    install -d -m 0750 -o root -g adm "$PASTA_DE_LOGS"
    install -d -m 0755 "$PASTA_DE_CONFIGURACAO" "$PASTA_DA_APLICACAO"
    ok "pastas do Me Conta: $PASTA_DE_CONFIGURACAO, $PASTA_DA_APLICACAO, $PASTA_DE_LOGS"
}
