#!/usr/bin/env bash
# =============================================================================
# Guarda um segredo da API (ex.: a chave do Gemini) criptografado com o systemd-creds.
#
# Por que não usar variável de ambiente ou appsettings.json?
#   - variável de ambiente aparece em /proc/<pid>/environ, em "systemctl show" e em dumps;
#   - arquivo de configuração pode ir parar no Git ou num backup.
# Aqui o segredo fica cifrado em /etc/meconta/segredos/<NOME>.cred (chave da máquina e, se houver, do TPM).
# Só o systemd decifra, na hora de subir a API, e entrega num diretório em memória visível apenas ao serviço
# ($CREDENTIALS_DIRECTORY). A API lê esse diretório como configuração (um arquivo por chave).
#
# Uso:  sudo bash linux/ferramentas/guardar-segredo.sh Gemini__ChaveApi
#       (o valor é pedido sem aparecer na tela e não fica no histórico do terminal)
# O nome usa "__" no lugar de ":" (Gemini__ChaveApi = configuração Gemini:ChaveApi).
# =============================================================================
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }

NOME="${1:-}"
[[ "$NOME" =~ ^[A-Za-z0-9_]+$ ]] || { echo "uso: sudo bash $0 NOME (ex.: Gemini__ChaveApi)" >&2; exit 2; }

PASTA_DE_SEGREDOS="/etc/meconta/segredos"
PASTA_DO_DROPIN="/etc/systemd/system/meconta-api.service.d"
ARQUIVO="${PASTA_DE_SEGREDOS}/${NOME}.cred"

read -rsp "Valor de ${NOME} (não aparece na tela): " VALOR
echo
[[ -n "$VALOR" ]] || { echo "Valor vazio; nada foi gravado." >&2; exit 1; }

install -d -m 0700 -o root -g root "$PASTA_DE_SEGREDOS"
printf '%s' "$VALOR" | systemd-creds encrypt --name="$NOME" - "$ARQUIVO"
unset VALOR
chmod 0600 "$ARQUIVO"
echo "Segredo cifrado em ${ARQUIVO} ($(stat -c '%a %U:%G' "$ARQUIVO"))."

# Um LoadCredentialEncrypted= para cada segredo guardado.
install -d -m 0755 "$PASTA_DO_DROPIN"
{
    echo "# Gerado por linux/ferramentas/guardar-segredo.sh: segredos cifrados entregues à API pelo systemd."
    echo "[Service]"
    for credencial in "${PASTA_DE_SEGREDOS}"/*.cred; do
        echo "LoadCredentialEncrypted=$(basename "$credencial" .cred):${credencial}"
    done
} > "${PASTA_DO_DROPIN}/segredos.conf"

systemctl daemon-reload
systemctl restart meconta-api.service
echo "meconta-api reiniciada com $(grep -c '^LoadCredentialEncrypted' "${PASTA_DO_DROPIN}/segredos.conf") segredo(s)."
echo "Conferir (mostra só que o segredo existe, nunca o valor): sudo systemd-creds --system list"
logger -t meconta-segredos "segredo ${NOME} gravado/atualizado por ${SUDO_USER:-root}"
