#!/usr/bin/env bash
# Etapa 3: segurança (usuário do serviço, SSH e firewall).

ARQUIVO_SSH="/etc/ssh/sshd_config.d/10-meconta.conf"

etapa_seguranca() {
    titulo "3/6 seguranca" "usuário do serviço, SSH e firewall"
    criar_usuario_do_servico
    endurecer_ssh
    configurar_firewall
}

# A API roda com um usuário próprio, sem senha e sem shell: se alguém explorar a aplicação,
# não ganha acesso de administrador nem consegue logar na máquina.
criar_usuario_do_servico() {
    if ! id "$USUARIO_DO_SERVICO" > /dev/null 2>&1; then
        useradd --system --home-dir "$PASTA_DE_DADOS" --shell /usr/sbin/nologin \
            --comment "Me Conta API" "$USUARIO_DO_SERVICO"
        passo "usuário de sistema ${USUARIO_DO_SERVICO} criado"
    fi
    # Dados da API: só o próprio serviço lê e escreve.
    install -d -m 0750 -o "$USUARIO_DO_SERVICO" -g "$USUARIO_DO_SERVICO" \
        "$PASTA_DE_DADOS" "${PASTA_DE_DADOS}/dados" "${PASTA_DE_DADOS}/arquivos"
    # Configuração: root escreve, o grupo do serviço só lê, os outros não veem nada.
    chown root:"$USUARIO_DO_SERVICO" "$PASTA_DE_CONFIGURACAO"
    chmod 0750 "$PASTA_DE_CONFIGURACAO"
    ok "usuário ${USUARIO_DO_SERVICO} ($(id "$USUARIO_DO_SERVICO")), shell nologin; dados em ${PASTA_DE_DADOS} (0750)"
}

endurecer_ssh() {
    local temporario
    temporario="$(mktemp)"
    # O OpenSSH usa o primeiro valor que encontrar; por isso o arquivo começa com "10-", antes do 50-cloudimg do Azure.
    cat > "$temporario" << EOF
# Gerado por linux/etapas/seguranca.sh (Me Conta)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    # Só a conta de administrador pode entrar por SSH.
    if [[ "$QUEM" != "root" ]]; then
        echo "AllowUsers ${QUEM}" >> "$temporario"
    fi

    if instalar_arquivo "$temporario" "$ARQUIVO_SSH" 0644; then
        if sshd -t; then
            systemctl try-reload-or-restart ssh
        else
            rm -f "$ARQUIVO_SSH"
            falhar "configuração do SSH inválida; arquivo removido para não perder o acesso"
        fi
    fi
    rm -f "$temporario"
    local quem_entra="qualquer usuário com chave"
    [[ "$QUEM" != "root" ]] && quem_entra="só o usuário ${QUEM}"
    ok "SSH: só chave pública, sem root, no máximo 3 tentativas, ${quem_entra}"
}

configurar_firewall() {
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    # SSH com limite: o ufw bloqueia um IP que tentar 6 conexões em 30 segundos.
    ufw limit OpenSSH > /dev/null
    local porta
    for porta in $PORTAS_LIBERADAS; do
        ufw allow "$porta" > /dev/null
    done
    ufw logging low > /dev/null
    ufw --force enable > /dev/null
    ok "firewall ativo: entrada bloqueada, exceto SSH (com limite) e ${PORTAS_LIBERADAS}"
    ufw status verbose | sed 's/^/     /'
}
