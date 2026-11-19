#!/usr/bin/env bash
# Etapa 2: rede (hostname, /etc/hosts, IP fixo e DNS).
#
# No Azure, o IP privado vem do DHCP da plataforma. Fixamos o mesmo IP em dois lugares:
#   1. na NIC, pelo portal (Configurações de IP > Estático), feito antes de rodar este script;
#   2. dentro da VM, pelo netplan, feito aqui.
# Os dois precisam ser iguais. Por isso existe a trava IP_PRIVADO_FIXADO_NO_AZURE no meconta.conf
# e um rollback automático: se a rede não responder depois da troca, a configuração anterior volta em 120 s.

ARQUIVO_NETPLAN="/etc/netplan/60-meconta.yaml"
ARQUIVO_CLOUD_INIT="/etc/cloud/cloud.cfg.d/99-meconta.cfg"
ARQUIVO_CLOUD_INIT_REDE="/etc/cloud/cloud.cfg.d/99-meconta-rede.cfg"
ARQUIVO_DNS="/etc/systemd/resolved.conf.d/60-meconta.conf"

etapa_rede() {
    titulo "2/6 rede" "hostname, /etc/hosts, IP fixo e DNS"

    local interface gateway ip_com_prefixo ip_privado mac
    interface="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"
    gateway="$(ip -o -4 route show to default | awk '{print $3}' | head -n1)"
    ip_com_prefixo="$(ip -o -4 addr show dev "$interface" scope global | awk '{print $4}' | head -n1)"
    ip_privado="${ip_com_prefixo%/*}"
    [[ -n "$interface" && -n "$gateway" && -n "$ip_privado" ]] || falhar "não encontrei a interface de rede com rota padrão"
    mac="$(cat "/sys/class/net/${interface}/address")"
    ok "interface ${interface} (MAC ${mac}), IP ${ip_com_prefixo}, gateway ${gateway}"

    configurar_cloud_init
    configurar_hosts "$ip_privado"
    configurar_hostname
    configurar_dns
    configurar_ip_fixo "$interface" "$mac" "$ip_com_prefixo" "$gateway"
    conferir_rede "$gateway"
}

# O cloud-init do Azure reescreve hostname e /etc/hosts a cada boot. Pedimos para ele preservar o que configuramos.
configurar_cloud_init() {
    local temporario
    temporario="$(mktemp)"
    cat > "$temporario" << 'EOF'
# Gerado por linux/etapas/rede.sh (Me Conta): o hostname e o /etc/hosts são definidos pelo provisionamento.
preserve_hostname: true
manage_etc_hosts: false
EOF
    instalar_arquivo "$temporario" "$ARQUIVO_CLOUD_INIT" 0644 || true
    rm -f "$temporario"
    ok "cloud-init não sobrescreve mais hostname e /etc/hosts"
}

# Bloco próprio no /etc/hosts, entre marcadores, para poder ser refeito sem duplicar linhas.
configurar_hosts() {
    local ip_privado="$1" bloco
    bloco="# >>> meconta (gerado por linux/etapas/rede.sh)
${ip_privado}  ${NOME_DO_SERVIDOR}.${DOMINIO_INTERNO} ${NOME_DO_SERVIDOR}
127.0.0.1  api.${DOMINIO_INTERNO}
# <<< meconta"
    sed -i '/^# >>> meconta/,/^# <<< meconta/d' /etc/hosts
    # Remove a linha antiga do hostname criada pelo cloud-init (127.0.1.1 nome-antigo), se houver.
    sed -i '/^127\.0\.1\.1[[:space:]]/d' /etc/hosts
    printf '%s\n' "$bloco" >> /etc/hosts
    ok "/etc/hosts: ${NOME_DO_SERVIDOR}.${DOMINIO_INTERNO} -> ${ip_privado}; api.${DOMINIO_INTERNO} -> 127.0.0.1"
}

configurar_hostname() {
    if [[ "$(hostnamectl --static)" != "$NOME_DO_SERVIDOR" ]]; then
        passo "hostname: $(hostnamectl --static) -> ${NOME_DO_SERVIDOR}"
        hostnamectl set-hostname "$NOME_DO_SERVIDOR"
    fi
    ok "hostname: $(hostname) | FQDN: $(hostname -f 2>/dev/null || echo '?')"
}

# DNS pelo systemd-resolved: servidores globais para todas as consultas (Domains=~.) e o domínio interno como busca.
configurar_dns() {
    local temporario
    temporario="$(mktemp)"
    cat > "$temporario" << EOF
# Gerado por linux/etapas/rede.sh (Me Conta)
[Resolve]
DNS=${SERVIDORES_DNS}
Domains=${DOMINIO_INTERNO} ~.
Cache=yes
EOF
    if instalar_arquivo "$temporario" "$ARQUIVO_DNS" 0644; then
        systemctl restart systemd-resolved
    fi
    rm -f "$temporario"
    ok "DNS: ${SERVIDORES_DNS} (busca no domínio ${DOMINIO_INTERNO})"
}

configurar_ip_fixo() {
    local interface="$1" mac="$2" ip_com_prefixo="$3" gateway="$4"
    local ip_privado="${ip_com_prefixo%/*}"

    if [[ "$IP_ESTATICO" != "sim" ]]; then
        aviso "IP_ESTATICO=nao: o IP continua vindo do DHCP do Azure (${ip_com_prefixo})"
        return
    fi
    if [[ -z "$IP_PRIVADO_FIXADO_NO_AZURE" || "$IP_PRIVADO_FIXADO_NO_AZURE" != "$ip_privado" ]]; then
        aviso "IP fixo não aplicado: IP_PRIVADO_FIXADO_NO_AZURE='${IP_PRIVADO_FIXADO_NO_AZURE}' e o IP atual é ${ip_privado}."
        aviso "Deixe o IP como Estático na NIC do Azure, preencha IP_PRIVADO_FIXADO_NO_AZURE=\"${ip_privado}\" no meconta.conf e rode: sudo bash provisionar.sh rede"
        return
    fi

    local temporario
    temporario="$(mktemp)"
    cat > "$temporario" << EOF
# Gerado por linux/etapas/rede.sh (Me Conta): IP privado fixo, igual ao fixado na NIC do Azure.
# O DNS é configurado no systemd-resolved (/etc/systemd/resolved.conf.d/60-meconta.conf).
network:
  version: 2
  ethernets:
    ${interface}:
      match:
        macaddress: "${mac}"
      set-name: ${interface}
      dhcp4: false
      dhcp6: false
      addresses:
        - ${ip_com_prefixo}
      routes:
        - to: default
          via: ${gateway}
EOF
    if [[ -f "$ARQUIVO_NETPLAN" ]] && cmp -s "$temporario" "$ARQUIVO_NETPLAN"; then
        rm -f "$temporario"
        ok "IP fixo já configurado: ${ip_com_prefixo} via ${gateway}"
        return
    fi

    # Guarda a configuração atual para o rollback.
    local backup
    backup="${PASTA_DE_CONFIGURACAO}/backup/netplan-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup"
    cp -a /etc/netplan/. "$backup/"
    passo "backup do netplan atual em ${backup}"

    # Rollback automático: um timer do systemd, independente desta sessão SSH, restaura o backup em 120 s.
    # Se a rede responder depois da troca, o timer é cancelado logo abaixo.
    systemctl stop meconta-rede-rollback.timer 2> /dev/null || true
    systemctl reset-failed meconta-rede-rollback.service 2> /dev/null || true
    systemd-run --quiet --unit=meconta-rede-rollback --on-active=120 /bin/bash -c \
        "rm -f /etc/netplan/*.yaml ${ARQUIVO_CLOUD_INIT_REDE}; cp -a '${backup}/.' /etc/netplan/; netplan apply; logger -t meconta-rede 'rollback do netplan aplicado'"
    passo "rollback agendado para daqui a 120 s (cancelado se a rede responder)"

    # Aplica o IP fixo: tira a configuração DHCP gerada pelo cloud-init e impede que ele a recrie no próximo boot.
    rm -f /etc/netplan/50-cloud-init.yaml
    install -m 0600 "$temporario" "$ARQUIVO_NETPLAN"
    rm -f "$temporario"
    echo 'network: {config: disabled}' > "$ARQUIVO_CLOUD_INIT_REDE"
    netplan generate
    netplan apply

    # Confere a rede por até ~30 s (o DNS pode levar alguns segundos para voltar depois da troca).
    local rede_ok=1
    for _ in $(seq 1 10); do
        sleep 3
        if ping -c 1 -W 2 "$gateway" > /dev/null 2>&1 && getent hosts github.com > /dev/null; then
            rede_ok=0
            break
        fi
    done

    if ((rede_ok == 0)); then
        systemctl stop meconta-rede-rollback.timer
        ok "IP fixo aplicado: ${ip_com_prefixo} via ${gateway} (rollback cancelado)"
    else
        falhar "a rede não respondeu depois da troca; a configuração anterior volta sozinha em até 120 s"
    fi
}

conferir_rede() {
    local gateway="$1" ip_publico nome_resolvido
    if ping -c 1 -W 2 "$gateway" > /dev/null; then
        ok "gateway ${gateway} responde"
    else
        aviso "gateway ${gateway} não respondeu ao ping"
    fi
    if getent hosts "api.${DOMINIO_INTERNO}" > /dev/null; then
        ok "nome interno api.${DOMINIO_INTERNO} resolve"
    else
        aviso "nome interno api.${DOMINIO_INTERNO} não resolve"
    fi
    if resolvectl query --legend=no github.com > /dev/null 2>&1; then
        ok "DNS externo resolve (github.com)"
    else
        aviso "DNS externo não respondeu"
    fi

    # IP público: perguntado ao serviço de metadados do Azure (só responde de dentro da VM).
    ip_publico="$(curl -fsS -m 3 -H 'Metadata: true' \
        'http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2021-02-01&format=text' || true)"
    if [[ -n "$ip_publico" ]]; then
        ok "IP público (metadados do Azure): ${ip_publico}"
        echo "$ip_publico" > "${PASTA_DE_CONFIGURACAO}/ip-publico"
        nome_resolvido="$(getent hosts "$NOME_PUBLICO" | awk '{print $1}' | head -n1 || true)"
        if [[ "$nome_resolvido" == "$ip_publico" ]]; then
            ok "nome público ${NOME_PUBLICO} -> ${ip_publico}"
        else
            aviso "nome público ${NOME_PUBLICO} resolve para '${nome_resolvido}', esperado ${ip_publico} (confira o rótulo DNS no portal)"
        fi
    else
        aviso "não consegui ler o IP público nos metadados do Azure"
    fi
}
