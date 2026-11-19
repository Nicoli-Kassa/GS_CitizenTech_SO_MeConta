#!/usr/bin/env bash
# =============================================================================
# Teste de falha do servidor Me Conta
#
# Provoca falhas de verdade e confere se o servidor se recupera sozinho:
#   api              mata a API com kill -9            -> o systemd sobe de novo
#   api-travada      congela a API (SIGSTOP)           -> o monitor vê o /health falhar e reinicia a API
#   monitor          mata o monitor com kill -9        -> o systemd sobe de novo
#   monitor-travado  congela o monitor (SIGSTOP)       -> o watchdog do systemd reinicia (leva ~60 s)
#   cpu              CPU em 100% por 60 s              -> ALERTA de CPU e depois NORMAL
#   memoria          ocupa ~90% da memória por 60 s    -> ALERTA de memória e depois NORMAL
#   disco            enche o disco até ~85%            -> ALERTA de disco e depois NORMAL (arquivo é apagado)
#   verificar        só confere se tudo está no ar (use depois de um "sudo reboot")
#
# Uso: sudo bash linux/ferramentas/teste-de-falha.sh [teste ...]   (sem argumento: todos, menos monitor-travado)
# Resultado: na tela e em /var/log/meconta/teste-de-falha.log
# =============================================================================
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }

LOG_DE_ALERTAS="/var/log/meconta/alertas.log"
LOG_DO_TESTE="/var/log/meconta/teste-de-falha.log"
URL_DE_SAUDE="http://127.0.0.1/health"
ARQUIVO_DE_TESTE_DO_DISCO="/var/tmp/meconta-teste-disco.bin"
# shellcheck source=/dev/null
source /etc/meconta/monitor.conf 2> /dev/null || true
LIMITE_DISCO="${LIMITE_DISCO:-80}"
LIMITE_MEMORIA="${LIMITE_MEMORIA:-80}"

VERDE=$'\e[1;32m'; VERMELHO=$'\e[1;31m'; AZUL=$'\e[1;34m'; SEM_COR=$'\e[0m'
[[ -t 1 ]] || { VERDE=""; VERMELHO=""; AZUL=""; SEM_COR=""; }

declare -a RESULTADOS=()

agora() { date '+%H:%M:%S'; }
dizer() { echo "  [$(agora)] $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" >> "$LOG_DO_TESTE"; }
cabecalho() { echo; echo "${AZUL}### Teste: $1${SEM_COR}"; dizer "INICIO $1"; }
resultado() {
    # $1 = nome, $2 = PASSOU|FALHOU, $3 = detalhe
    local cor="$VERDE"; [[ "$2" == "FALHOU" ]] && cor="$VERMELHO"
    echo "  ${cor}$2${SEM_COR} - $3"
    dizer "$2 $1: $3"
    RESULTADOS+=("$(printf '%-16s %-7s %s' "$1" "$2" "$3")")
}

api_responde() { curl -fsS -m 3 "$URL_DE_SAUDE" > /dev/null 2>&1; }
pid_de() { systemctl show -p MainPID --value "$1"; }

# Espera até $2 segundos por uma linha nova no log de alertas que case com o padrão $1.
esperar_evento() {
    local padrao="$1" limite="$2" linhas_antes="$3" inicio=$SECONDS
    while ((SECONDS - inicio < limite)); do
        if tail -n +"$((linhas_antes + 1))" "$LOG_DE_ALERTAS" 2> /dev/null | grep -qE "$padrao"; then
            tail -n +"$((linhas_antes + 1))" "$LOG_DE_ALERTAS" | grep -E "$padrao" | tail -n1 | sed 's/^/    /'
            return 0
        fi
        sleep 1
    done
    return 1
}
linhas_do_log() { wc -l < "$LOG_DE_ALERTAS" 2> /dev/null || echo 0; }

# Espera um serviço voltar com um PID diferente do antigo. Devolve os segundos que levou.
esperar_novo_pid() {
    local servico="$1" pid_antigo="$2" limite="$3" inicio=$SECONDS pid
    while ((SECONDS - inicio < limite)); do
        pid="$(pid_de "$servico")"
        if [[ "$pid" != "0" && "$pid" != "$pid_antigo" ]] && systemctl is-active --quiet "$servico"; then
            echo $((SECONDS - inicio))
            return 0
        fi
        sleep 1
    done
    return 1
}

teste_api() {
    cabecalho "API derrubada (kill -9)"
    local pid inicio segundos
    pid="$(pid_de meconta-api)"
    dizer "meconta-api rodando com PID ${pid}; enviando SIGKILL"
    inicio=$SECONDS
    kill -9 "$pid"
    if esperar_novo_pid meconta-api "$pid" 60 > /dev/null; then
        while ! api_responde && ((SECONDS - inicio < 90)); do sleep 1; done
        segundos=$((SECONDS - inicio))
        if api_responde; then
            resultado api PASSOU "systemd reiniciou a API (novo PID $(pid_de meconta-api)); /health de volta em ${segundos} s"
            return
        fi
    fi
    resultado api FALHOU "a API não voltou em 90 s"
}

teste_api_travada() {
    cabecalho "API travada (SIGSTOP: processo vivo, mas sem responder)"
    local pid linhas inicio
    pid="$(pid_de meconta-api)"
    linhas="$(linhas_do_log)"
    inicio=$SECONDS
    dizer "congelando meconta-api (PID ${pid}); o systemd não percebe, só o monitor (via /health)"
    kill -STOP "$pid"
    if esperar_evento 'ACAO +\| api' 120 "$linhas"; then
        dizer "monitor reiniciou a API; esperando o /health"
        while ! api_responde && ((SECONDS - inicio < 180)); do sleep 1; done
    fi
    if api_responde && [[ "$(pid_de meconta-api)" != "$pid" ]]; then
        resultado api-travada PASSOU "monitor detectou o /health falhando e reiniciou a API; de volta em $((SECONDS - inicio)) s"
    else
        kill -CONT "$pid" 2> /dev/null
        resultado api-travada FALHOU "a API não foi reiniciada em 180 s (processo descongelado)"
    fi
}

teste_monitor() {
    cabecalho "monitor derrubado (kill -9)"
    local pid segundos
    pid="$(pid_de meconta-monitor)"
    dizer "meconta-monitor rodando com PID ${pid}; enviando SIGKILL"
    kill -9 "$pid"
    if segundos="$(esperar_novo_pid meconta-monitor "$pid" 30)"; then
        resultado monitor PASSOU "systemd reiniciou o monitor em ${segundos} s (novo PID $(pid_de meconta-monitor))"
    else
        resultado monitor FALHOU "o monitor não voltou em 30 s"
    fi
}

teste_monitor_travado() {
    cabecalho "monitor travado (SIGSTOP: para de mandar sinal de vida ao systemd)"
    local pid segundos
    pid="$(pid_de meconta-monitor)"
    dizer "congelando meconta-monitor (PID ${pid}); o watchdog é de 60 s"
    kill -STOP "$pid"
    if segundos="$(esperar_novo_pid meconta-monitor "$pid" 120)"; then
        resultado monitor-travado PASSOU "watchdog do systemd matou e reiniciou o monitor em ${segundos} s"
        journalctl -u meconta-monitor --since "-3min" --no-pager | grep -i watchdog | tail -n1 | sed 's/^/    /'
    else
        kill -CONT "$pid" 2> /dev/null
        resultado monitor-travado FALHOU "o watchdog não reiniciou o monitor em 120 s"
    fi
}

# Gera carga e espera o ALERTA e depois o NORMAL do recurso.
teste_de_carga() {
    local nome="$1" recurso="$2"; shift 2
    local linhas
    linhas="$(linhas_do_log)"
    dizer "gerando carga: $*"
    "$@" > /dev/null 2>&1 &
    local pid_carga=$!
    if esperar_evento "ALERTA +\| ${recurso}" 90 "$linhas"; then
        linhas="$(linhas_do_log)"
        wait "$pid_carga" 2> /dev/null
        dizer "carga encerrada; esperando o recurso normalizar"
        if esperar_evento "NORMAL +\| ${recurso}" 90 "$linhas"; then
            resultado "$nome" PASSOU "ALERTA disparado acima do limite e NORMAL quando a carga acabou"
            return
        fi
        resultado "$nome" FALHOU "o ALERTA disparou, mas o NORMAL não chegou em 90 s"
        return
    fi
    kill "$pid_carga" 2> /dev/null
    resultado "$nome" FALHOU "nenhum ALERTA de ${recurso} em 90 s"
}

teste_cpu() {
    cabecalho "CPU em 100%"
    teste_de_carga cpu cpu stress-ng --cpu "$(nproc)" --cpu-load 100 --timeout 70s
}

teste_memoria() {
    cabecalho "memória acima do limite"
    # Ocupa o suficiente para ficar ~10 pontos acima do limite, sem esgotar a máquina.
    local total disponivel alvo bytes
    total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    disponivel="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
    alvo=$(((LIMITE_MEMORIA + 10) * total / 100))
    bytes=$(((alvo - (total - disponivel)) * 1024))
    if ((bytes <= 0)); then
        resultado memoria FALHOU "a memória já está acima do alvo; teste não executado"
        return
    fi
    teste_de_carga memoria memoria stress-ng --vm 1 --vm-bytes "$bytes" --vm-keep --timeout 70s
}

teste_disco() {
    cabecalho "disco acima do limite"
    local total usado alvo bytes linhas
    read -r total usado < <(df -P -B1 / | awk 'NR==2 {print $2, $3}')
    alvo=$(((LIMITE_DISCO + 5) * total / 100))
    bytes=$((alvo - usado))
    if ((bytes <= 0)); then
        resultado disco FALHOU "o disco já está acima do alvo; teste não executado"
        return
    fi
    linhas="$(linhas_do_log)"
    dizer "criando ${ARQUIVO_DE_TESTE_DO_DISCO} com $((bytes / 1024 / 1024)) MB (disco vai a ~$((LIMITE_DISCO + 5))%)"
    fallocate -l "$bytes" "$ARQUIVO_DE_TESTE_DO_DISCO"
    if esperar_evento 'ALERTA +\| disco' 90 "$linhas"; then
        linhas="$(linhas_do_log)"
        rm -f "$ARQUIVO_DE_TESTE_DO_DISCO"
        dizer "arquivo de teste apagado; esperando o disco normalizar"
        if esperar_evento 'NORMAL +\| disco' 60 "$linhas"; then
            resultado disco PASSOU "ALERTA de disco disparado e NORMAL depois de apagar o arquivo"
            return
        fi
    fi
    rm -f "$ARQUIVO_DE_TESTE_DO_DISCO"
    resultado disco FALHOU "o ciclo ALERTA/NORMAL de disco não aconteceu"
}

teste_verificar() {
    cabecalho "tudo no ar (depois de um reboot, por exemplo)"
    local servico falhas=0
    for servico in meconta-api meconta-monitor nginx auditd; do
        if systemctl is-active --quiet "$servico" && systemctl is-enabled --quiet "$servico"; then
            dizer "${servico}: ativo e habilitado no boot"
        else
            dizer "${servico}: $(systemctl is-active "$servico") / $(systemctl is-enabled "$servico")"
            falhas=$((falhas + 1))
        fi
    done
    api_responde || falhas=$((falhas + 1))
    if ((falhas == 0)); then
        resultado verificar PASSOU "4 serviços ativos e habilitados; /health responde; ligado desde $(uptime -s)"
    else
        resultado verificar FALHOU "${falhas} problema(s); veja: sudo bash linux/ferramentas/status.sh"
    fi
}

TESTES_PADRAO=(api api-travada monitor cpu memoria disco)
if (($# > 0)); then TESTES=("$@"); else TESTES=("${TESTES_PADRAO[@]}"); fi
dizer "==== teste de falha iniciado por ${SUDO_USER:-root}: ${TESTES[*]}"
api_responde || echo "  ${VERMELHO}Atenção: a API não está respondendo antes do teste.${SEM_COR}"

for teste in "${TESTES[@]}"; do
    case "$teste" in
        api) teste_api ;;
        api-travada) teste_api_travada ;;
        monitor) teste_monitor ;;
        monitor-travado) teste_monitor_travado ;;
        cpu) teste_cpu ;;
        memoria) teste_memoria ;;
        disco) teste_disco ;;
        verificar) teste_verificar ;;
        *) echo "Teste desconhecido: ${teste}" >&2; exit 2 ;;
    esac
done

echo
echo "${AZUL}### Resumo${SEM_COR}"
printf '  %s\n' "${RESULTADOS[@]}"
dizer "==== teste de falha concluído"
