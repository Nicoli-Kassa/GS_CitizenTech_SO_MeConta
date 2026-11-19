#!/usr/bin/env bash
# Funções usadas por todas as etapas do provisionamento.
# Este arquivo não roda sozinho: ele é carregado com "source" pelo provisionar.sh.

# shellcheck disable=SC2034  # usadas pelas etapas que carregam este arquivo
PASTA_DE_LOGS="/var/log/meconta"
LOG_DO_PROVISIONAMENTO="${PASTA_DE_LOGS}/provisionamento.log"
PASTA_DE_CONFIGURACAO="/etc/meconta"
PASTA_DA_APLICACAO="/opt/meconta"
PASTA_DE_DADOS="/var/lib/meconta"

# Quem está rodando o script: o usuário real por trás do sudo (vai para o log de auditoria).
QUEM="${SUDO_USER:-$(whoami)}"

COR_AZUL=$'\e[1;34m'; COR_VERDE=$'\e[1;32m'; COR_AMARELA=$'\e[1;33m'; COR_VERMELHA=$'\e[1;31m'; SEM_COR=$'\e[0m'
[[ -t 1 ]] || { COR_AZUL=""; COR_VERDE=""; COR_AMARELA=""; COR_VERMELHA=""; SEM_COR=""; }

# Grava uma linha no log do provisionamento: data, usuário, etapa e mensagem.
registrar() {
    local nivel="$1"; shift
    mkdir -p "$PASTA_DE_LOGS"
    printf '%s | %-5s | usuario=%s | etapa=%s | %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S %z')" "$nivel" "$QUEM" "${ETAPA_ATUAL:-geral}" "$*" >> "$LOG_DO_PROVISIONAMENTO"
}

titulo() { ETAPA_ATUAL="$1"; echo; echo "${COR_AZUL}== $1: $2 ==${SEM_COR}"; registrar INICIO "$2"; }
passo()  { echo "  -> $*"; registrar INFO "$*"; }
ok()     { echo "  ${COR_VERDE}OK${SEM_COR} $*"; registrar OK "$*"; }
aviso()  { echo "  ${COR_AMARELA}AVISO${SEM_COR} $*"; registrar AVISO "$*"; }
falhar() { echo "  ${COR_VERMELHA}ERRO${SEM_COR} $*" >&2; registrar ERRO "$*"; exit 1; }

exigir_root() {
    [[ $EUID -eq 0 ]] || falhar "Rode com sudo: sudo bash $0"
}

# Instala um arquivo do repositório no sistema só se ele mudou. Devolve 0 se mudou, 1 se já estava igual.
instalar_arquivo() {
    local origem="$1" destino="$2" modo="${3:-0644}" dono="${4:-root:root}"
    if [[ -f "$destino" ]] && cmp -s "$origem" "$destino"; then
        return 1
    fi
    install -D -m "$modo" -o "${dono%%:*}" -g "${dono##*:}" "$origem" "$destino"
    passo "arquivo instalado: $destino"
    return 0
}

# Troca os marcadores {{VARIAVEL}} de um modelo pelos valores do meconta.conf e grava em um arquivo temporário.
preencher_modelo() {
    local modelo="$1" saida
    saida="$(mktemp)"
    cp "$modelo" "$saida"
    local variavel
    for variavel in NOME_DO_SERVIDOR DOMINIO_INTERNO NOME_PUBLICO PORTA_INTERNA_DA_API USUARIO_DO_SERVICO; do
        sed -i "s|{{${variavel}}}|${!variavel}|g" "$saida"
    done
    echo "$saida"
}

pacote_instalado() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

instalar_pacotes() {
    local faltando=()
    local pacote
    for pacote in "$@"; do
        pacote_instalado "$pacote" || faltando+=("$pacote")
    done
    if ((${#faltando[@]} > 0)); then
        passo "instalando: ${faltando[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${faltando[@]}" > /dev/null
    fi
}
