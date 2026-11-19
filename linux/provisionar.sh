#!/usr/bin/env bash
# =============================================================================
# Provisionamento do servidor Linux do Me Conta
#
# Prepara uma VM Ubuntu Server 24.04 recém-criada para rodar a API do Me Conta:
#   1. sistema       fuso horário, pacotes, swap
#   2. rede          hostname, /etc/hosts, IP fixo e DNS (netplan, com rollback)
#   3. seguranca     usuário do serviço, SSH só com chave, firewall (ufw)
#   4. aplicacao     .NET, build da API, serviço systemd, SQLite, nginx
#   5. monitoramento CPU, memória e disco com alertas, como serviço tolerante a falhas
#   6. auditoria     auditd, journald persistente, rotação de logs
#
# Uso:
#   sudo bash provisionar.sh                # todas as etapas, em ordem
#   sudo bash provisionar.sh aplicacao      # só uma etapa (ex.: para atualizar a API)
#   sudo bash provisionar.sh rede seguranca # algumas etapas
#
# Pode ser rodado de novo quantas vezes quiser: cada etapa só muda o que ainda não está certo.
# Tudo o que o script faz fica registrado em /var/log/meconta/provisionamento.log.
# =============================================================================
set -Eeuo pipefail

PASTA_DOS_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=meconta.conf
source "${PASTA_DOS_SCRIPTS}/meconta.conf"
# shellcheck source=etapas/comum.sh
source "${PASTA_DOS_SCRIPTS}/etapas/comum.sh"

trap 'registrar ERRO "falhou na linha ${LINENO}: ${BASH_COMMAND}"; echo "${COR_VERMELHA}Falhou na linha ${LINENO}: ${BASH_COMMAND}${SEM_COR}" >&2' ERR

ETAPAS_DISPONIVEIS=(sistema rede seguranca aplicacao monitoramento auditoria)

exigir_root
if (($# > 0)); then ETAPAS=("$@"); else ETAPAS=("${ETAPAS_DISPONIVEIS[@]}"); fi

for etapa in "${ETAPAS[@]}"; do
    [[ " ${ETAPAS_DISPONIVEIS[*]} " == *" ${etapa} "* ]] \
        || falhar "Etapa desconhecida: ${etapa}. Use: ${ETAPAS_DISPONIVEIS[*]}"
done

registrar INICIO "provisionamento iniciado (etapas: ${ETAPAS[*]})"
inicio=$(date +%s)

for etapa in "${ETAPAS[@]}"; do
    # shellcheck source=/dev/null
    source "${PASTA_DOS_SCRIPTS}/etapas/${etapa}.sh"
    "etapa_${etapa}"
done

ETAPA_ATUAL="geral"
registrar FIM "provisionamento concluído em $(( $(date +%s) - inicio )) s"
echo
echo "${COR_VERDE}Provisionamento concluído em $(( $(date +%s) - inicio )) s.${SEM_COR}"
echo "Resumo do servidor: sudo bash ${PASTA_DOS_SCRIPTS}/ferramentas/status.sh"
