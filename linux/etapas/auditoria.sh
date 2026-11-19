#!/usr/bin/env bash
# Etapa 6: logs de auditoria (auditd, journald persistente e rotação dos logs).
#
# O que fica registrado, e onde:
#   /var/log/audit/audit.log           auditd: quem mexeu em contas, SSH, rede, firewall, config do Me Conta,
#                                      quem parou serviços e todo comando executado por uma pessoa
#   /var/log/meconta/provisionamento.log  cada ação dos scripts de provisionamento (data, usuário, etapa)
#   /var/log/meconta/alertas.log       alertas e ações automáticas do monitor
#   /var/log/meconta/metricas.log      cada medição do monitor
#   /var/log/nginx/meconta-acesso.log  cada requisição: IP, método, caminho, status, tempo
#   journalctl -u meconta-api          logs da API (persistentes entre reinícios)

etapa_auditoria() {
    titulo "6/6 auditoria" "auditd, journald persistente e rotação de logs"

    # Journal persistente: os logs dos serviços sobrevivem a um reboot (por padrão no Azure ficam só em memória).
    local temporario
    temporario="$(mktemp)"
    cat > "$temporario" << 'EOF'
# Gerado por linux/etapas/auditoria.sh (Me Conta)
[Journal]
Storage=persistent
SystemMaxUse=200M
EOF
    if instalar_arquivo "$temporario" /etc/systemd/journald.conf.d/60-meconta.conf 0644; then
        mkdir -p /var/log/journal
        systemd-tmpfiles --create --prefix /var/log/journal
        systemctl restart systemd-journald
    fi
    rm -f "$temporario"
    ok "journal persistente em /var/log/journal (até 200 MB)"

    # Regras do auditd. As pastas observadas precisam existir antes de carregar as regras.
    install -d -m 0700 -o root -g root "${PASTA_DE_CONFIGURACAO}/segredos"
    install -d -m 0755 "${PASTA_DA_APLICACAO}/versoes" /etc/systemd/system/meconta-api.service.d
    if instalar_arquivo "${PASTA_DOS_SCRIPTS}/arquivos/auditd-meconta.rules" /etc/audit/rules.d/60-meconta.rules 0640; then
        augenrules --load > /dev/null
    fi
    systemctl enable --quiet --now auditd
    ok "auditd ativo com $(auditctl -l | grep -cE -- '(-k |key=)') regras (chaves: $(auditctl -l | grep -oE -- '(-k |key=)[a-z-]+' | sed -E 's/(-k |key=)//' | sort -u | paste -sd, -))"

    # Rotação dos logs do Me Conta: um arquivo por dia, 14 dias guardados, compactados.
    temporario="$(mktemp)"
    cat > "$temporario" << 'EOF'
# Gerado por linux/etapas/auditoria.sh (Me Conta)
/var/log/meconta/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    dateext
}
EOF
    instalar_arquivo "$temporario" /etc/logrotate.d/meconta 0644 || true
    rm -f "$temporario"
    logrotate --debug /etc/logrotate.d/meconta > /dev/null 2>&1 || aviso "logrotate acusou problema em /etc/logrotate.d/meconta"
    ok "rotação diária dos logs em ${PASTA_DE_LOGS} (14 dias)"

    # Logs só para root e para o grupo adm (administradores), nunca para todos.
    chown -R root:adm "$PASTA_DE_LOGS"
    chmod 0750 "$PASTA_DE_LOGS"
    find "$PASTA_DE_LOGS" -type f -exec chmod 0640 {} +
    ok "permissões: ${PASTA_DE_LOGS} 0750 root:adm, arquivos 0640"
}
