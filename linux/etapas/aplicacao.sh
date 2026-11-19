#!/usr/bin/env bash
# Etapa 4: aplicação web (API Me Conta + SQLite + nginx).
#
# Fluxo de publicação:
#   código do GitHub -> dotnet publish -> /opt/meconta/versoes/<data>-<commit> -> link /opt/meconta/app
# Cada publicação fica numa pasta própria. Se a versão nova não responder no /health, o link volta para a anterior.

PASTA_DO_CODIGO="${PASTA_DA_APLICACAO}/codigo"
PASTA_DAS_VERSOES="${PASTA_DA_APLICACAO}/versoes"
LINK_DA_VERSAO_ATUAL="${PASTA_DA_APLICACAO}/app"
ARQUIVO_DE_AMBIENTE="${PASTA_DE_CONFIGURACAO}/api.env"
PASTA_DO_PAINEL="/var/www/meconta-servidor"

etapa_aplicacao() {
    titulo "4/6 aplicacao" "API Me Conta, banco SQLite e nginx"
    CONFIG_MUDOU=0
    id "$USUARIO_DO_SERVICO" > /dev/null 2>&1 || falhar "rode antes a etapa seguranca (cria o usuário ${USUARIO_DO_SERVICO})"

    instalar_dotnet
    baixar_codigo
    publicar_api
    configurar_ambiente
    instalar_servico_da_api
    trocar_versao_e_reiniciar
    configurar_nginx
}

instalar_dotnet() {
    # O SDK vem do repositório oficial do Ubuntu 24.04 (pacote dotnet-sdk-10.0).
    instalar_pacotes dotnet-sdk-10.0
    ok ".NET SDK $(dotnet --version)"
}

baixar_codigo() {
    if [[ -d "${PASTA_DO_CODIGO}/.git" ]]; then
        passo "atualizando o código (${BRANCH})"
        git -C "$PASTA_DO_CODIGO" fetch --quiet --depth 1 origin "$BRANCH"
        git -C "$PASTA_DO_CODIGO" reset --quiet --hard FETCH_HEAD
    else
        passo "clonando ${REPOSITORIO}"
        git clone --quiet --depth 1 --branch "$BRANCH" "$REPOSITORIO" "$PASTA_DO_CODIGO"
    fi
    COMMIT="$(git -C "$PASTA_DO_CODIGO" rev-parse --short HEAD)"
    ok "código no commit ${COMMIT}: $(git -C "$PASTA_DO_CODIGO" log -1 --format=%s)"
}

publicar_api() {
    # Se a versão atual já é deste commit, não precisa compilar de novo.
    if [[ -L "$LINK_DA_VERSAO_ATUAL" && "$(readlink -f "$LINK_DA_VERSAO_ATUAL")" == *"-${COMMIT}" ]]; then
        NOVA_VERSAO="$(readlink -f "$LINK_DA_VERSAO_ATUAL")"
        MESMA_VERSAO=0
        ok "versão ${COMMIT} já publicada em ${NOVA_VERSAO}"
        return
    fi

    MESMA_VERSAO=1
    NOVA_VERSAO="${PASTA_DAS_VERSOES}/$(date +%Y%m%d-%H%M%S)-${COMMIT}"
    passo "compilando e publicando a API em ${NOVA_VERSAO} (leva alguns minutos na B1s)"
    export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
    dotnet publish "${PASTA_DO_CODIGO}/src/MeConta.Api/MeConta.Api.csproj" \
        -c Release -o "$NOVA_VERSAO" --nologo -v quiet -p:UseAppHost=true

    echo "$COMMIT" > "${NOVA_VERSAO}/VERSAO"
    # Os arquivos da aplicação são do root: o serviço só lê e executa, não consegue alterar o próprio código.
    chown -R root:"$USUARIO_DO_SERVICO" "$NOVA_VERSAO"
    chmod -R u=rwX,g=rX,o= "$NOVA_VERSAO"
    chmod 0750 "${NOVA_VERSAO}/MeConta.Api"
    ok "API publicada ($(du -sh "$NOVA_VERSAO" | cut -f1))"
}

# Configuração da API por variáveis de ambiente (nada de senha aqui; segredos ficam em ferramentas/guardar-segredo.sh).
configurar_ambiente() {
    local temporario
    temporario="$(mktemp)"
    cat > "$temporario" << EOF
# Gerado por linux/etapas/aplicacao.sh (Me Conta). Lido pelo serviço meconta-api.
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://127.0.0.1:${PORTA_INTERNA_DA_API}
DOTNET_CLI_TELEMETRY_OPTOUT=1
Banco__Provedor=Sqlite
ConnectionStrings__DefaultConnection=Data Source=${PASTA_DE_DADOS}/dados/meconta.db
Armazenamento__Pasta=${PASTA_DE_DADOS}/arquivos
Banco__DadosDeDemonstracao=${DADOS_DE_DEMONSTRACAO}
Banco__PaginasDoFiltroDePrivacidade=${PAGINAS_DO_FILTRO_DE_PRIVACIDADE}
EOF
    if instalar_arquivo "$temporario" "$ARQUIVO_DE_AMBIENTE" 0640 "root:${USUARIO_DO_SERVICO}"; then CONFIG_MUDOU=1; fi
    rm -f "$temporario"
    ok "configuração em ${ARQUIVO_DE_AMBIENTE} (0640, root:${USUARIO_DO_SERVICO}); banco SQLite em ${PASTA_DE_DADOS}/dados"
}

instalar_servico_da_api() {
    local modelo
    modelo="$(preencher_modelo "${PASTA_DOS_SCRIPTS}/arquivos/meconta-api.service")"
    if instalar_arquivo "$modelo" /etc/systemd/system/meconta-api.service 0644; then
        systemctl daemon-reload
        CONFIG_MUDOU=1
    fi
    rm -f "$modelo"
    systemctl enable --quiet meconta-api.service
    ok "serviço meconta-api instalado e habilitado no boot"
}

esperar_saude() {
    for _ in $(seq 1 45); do
        if curl -fsS -m 3 "http://127.0.0.1:${PORTA_INTERNA_DA_API}/health" > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

trocar_versao_e_reiniciar() {
    if ((MESMA_VERSAO == 0 && CONFIG_MUDOU == 0)) && systemctl is-active --quiet meconta-api.service && esperar_saude; then
        ok "API já está no ar com esta versão; nada a reiniciar"
        return
    fi
    local versao_anterior=""
    [[ -L "$LINK_DA_VERSAO_ATUAL" ]] && versao_anterior="$(readlink -f "$LINK_DA_VERSAO_ATUAL")"

    # Troca atômica do link: o serviço nunca vê uma pasta pela metade.
    ln -sfn "$NOVA_VERSAO" "${LINK_DA_VERSAO_ATUAL}.novo"
    mv -T "${LINK_DA_VERSAO_ATUAL}.novo" "$LINK_DA_VERSAO_ATUAL"

    passo "reiniciando meconta-api e esperando o /health"
    systemctl restart meconta-api.service
    if esperar_saude; then
        ok "API no ar: http://127.0.0.1:${PORTA_INTERNA_DA_API}/health = $(curl -fsS -m 3 "http://127.0.0.1:${PORTA_INTERNA_DA_API}/health")"
    else
        journalctl -u meconta-api -n 30 --no-pager >&2 || true
        if [[ -n "$versao_anterior" && "$versao_anterior" != "$NOVA_VERSAO" ]]; then
            aviso "a versão nova não respondeu; voltando para $(basename "$versao_anterior")"
            ln -sfn "$versao_anterior" "${LINK_DA_VERSAO_ATUAL}.novo"
            mv -T "${LINK_DA_VERSAO_ATUAL}.novo" "$LINK_DA_VERSAO_ATUAL"
            systemctl restart meconta-api.service
        fi
        falhar "a API não respondeu no /health em 90 s (veja: journalctl -u meconta-api)"
    fi

    # Guarda só as últimas versões publicadas.
    local antigas
    mapfile -t antigas < <(find "$PASTA_DAS_VERSOES" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +"$((VERSOES_GUARDADAS + 1))")
    if ((${#antigas[@]} > 0)); then
        rm -rf "${antigas[@]}"
        passo "versões antigas removidas: ${#antigas[@]}"
    fi
}

configurar_nginx() {
    local modelo mudou=1
    modelo="$(preencher_modelo "${PASTA_DOS_SCRIPTS}/arquivos/nginx-meconta.conf")"
    instalar_arquivo "$modelo" /etc/nginx/sites-available/meconta 0644 && mudou=0
    rm -f "$modelo"
    ln -sfn /etc/nginx/sites-available/meconta /etc/nginx/sites-enabled/meconta
    if [[ -e /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
        mudou=0
    fi
    install -d -m 0755 "$PASTA_DO_PAINEL"
    instalar_arquivo "${PASTA_DOS_SCRIPTS}/painel/index.html" "${PASTA_DO_PAINEL}/index.html" 0644 || true

    nginx -t -q || falhar "configuração do nginx inválida (nginx -t)"
    systemctl enable --quiet nginx
    if ((mudou == 0)); then systemctl reload nginx; fi
    ok "nginx publicando a API na porta 80 (http://${NOME_PUBLICO}/swagger/)"

    if curl -fsS -m 5 http://127.0.0.1/health > /dev/null; then
        ok "pelo nginx: http://127.0.0.1/health responde"
    else
        aviso "o nginx não conseguiu falar com a API (veja /var/log/nginx/meconta-erros.log)"
    fi
}
