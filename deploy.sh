#!/bin/bash
# deploy.sh - Envia e instala os arquivos na VPS sem passar pelo GitHub
# Uso: ./deploy.sh <IP_DA_VPS>

VPS_IP="$1"
VPS_USER="root"
RELAY_TARGET=""

# Parse arguments
shift
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --relay) RELAY_TARGET="$2"; shift ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$VPS_IP" ]; then
    echo "Erro: Forneça o IP da VPS."
    echo "Uso: ./deploy.sh 1.2.3.4 [--relay 1.2.3.4:80]"
    exit 1
fi

echo "=========================================="
echo "      INICIANDO DEPLOY AUTOMÁTICO         "
echo "=========================================="

# 1. Compilar localmente
echo "[1/3] Compilando arquivos locais..."
./build_all.sh
if [ $? -ne 0 ]; then
    echo "Erro na compilação!"
    exit 1
fi

# 2. Enviar arquivos para a pasta /tmp da VPS
echo "[2/3] Enviando arquivos para a VPS ($VPS_IP)..."
scp server hox.sh xray-config.json ${VPS_USER}@${VPS_IP}:/tmp/
if [ $? -ne 0 ]; then
    echo "Erro ao enviar arquivos via SCP!"
    exit 1
fi

# 3. Mover arquivos para os locais corretos e reiniciar serviços na VPS
echo "[3/3] Instalando e reiniciando serviços remotamente..."
ssh ${VPS_USER}@${VPS_IP} "RELAY_TARGET='${RELAY_TARGET}' bash -s" << 'EOF'
    # Parar serviços com segurança
    echo "  -> Parando serviços e garantindo limpeza..."
    systemctl stop hox xray 2>/dev/null
    
    # Mata qualquer processo que esteja usando o binário ou as portas
    fuser -k /usr/local/hox/server 2>/dev/null
    pkill -9 hox 2>/dev/null
    pkill -9 server 2>/dev/null
    
    # Remove o arquivo antigo para garantir que o 'mv' não falhe por estar em uso
    rm -f /usr/local/hox/server
    
    # Mover novos arquivos
    echo "  -> Atualizando binários e scripts..."
    if [ -f /tmp/server ]; then
        mv /tmp/server /usr/local/hox/server
    else
        echo "ERRO: Arquivo /tmp/server não encontrado!"
        exit 1
    fi
    
    [ -f /tmp/hox.sh ] && mv /tmp/hox.sh /usr/local/bin/hox
    [ -f /tmp/xray-config.json ] && mv /tmp/xray-config.json /usr/local/etc/xray/config.json
    
    # Ajustar permissões e sincronizar usuários
    chmod +x /usr/local/hox/server /usr/local/bin/hox
    
    # Mostrar versão do binário instalado para confirmar
    echo -n "  -> Versão instalada na VPS: "
    /usr/local/hox/server -version 2>/dev/null || echo "Desconhecida (Binário não suporta -version ou erro ao executar)"

    hox --sync
    
    # Reiniciar e verificar
    echo "  -> Verificando e atualizando portas do serviço..."
    tcp_ports=$(jq -r '.tcp | join(",")' /etc/hox/ports.json 2>/dev/null || echo "443")
    udp_ports=$(jq -r '.udp | join(",")' /etc/hox/ports.json 2>/dev/null || echo "7300")
    
    RELAY_CMD=""
    if [ -n "$RELAY_TARGET" ]; then
        RELAY_CMD="-relay $RELAY_TARGET"
        echo "  -> MODO RELAY ATIVO: Alvo $RELAY_TARGET"
    fi

    cat <<SVCEOF > /etc/systemd/system/hox.service
[Unit]
Description=HoxTunnel Service
After=network.target xray.service

[Service]
WorkingDirectory=/usr/local/hox
ExecStart=/usr/local/hox/server -ports $tcp_ports -udpgw $udp_ports $RELAY_CMD
Restart=always

[Install]
WantedBy=multi-user.target
SVCEOF

    echo "  -> Reiniciando serviços..."
    systemctl daemon-reload
    systemctl restart xray
    sleep 1
    systemctl restart hox
    
    echo ""
    echo "Verificação de Status:"
    systemctl is-active xray && echo "✓ Xray OK" || echo "✗ Xray FALHOU"
    systemctl is-active hox && echo "✓ Hox OK" || echo "✗ Hox FALHOU"
    echo ""
    echo "--- DEPLOY CONCLUÍDO COM SUCESSO! ---"
EOF
