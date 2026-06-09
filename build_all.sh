#!/bin/bash

# Script para compilar o servidor e o instalador protegido
# Uso: ./build_all.sh

echo "=========================================="
echo "      HOXTUNNEL - BUILD SYSTEM            "
echo "=========================================="

# 1. Ler Versão Central
VER=$(cat VERSION | xargs)
echo "Limpando e ativando versão: $VER"

# 2. Compilar o Servidor Principal (Protegido)
echo "[1/2] Compilando Servidor Principal..."
CGO_ENABLED=0 go build -ldflags="-s -w -X main.Version=$VER" -trimpath -o server server.go
if [ $? -eq 0 ]; then
    echo "  -> OK: arquivo 'server' gerado."
else
    echo "  -> ERRO ao compilar server.go"
    exit 1
fi

# 3. Atualizar hox.sh com a versão nova
echo "[*] Aplicando versão no script hox.sh..."
sed -i "s/VERSION=\"[0-9.]*\"/VERSION=\"$VER\"/" hox.sh

# 4. Compilar o Instalador (Protector)
echo "[2/2] Compilando Instalador (Protector)..."
CGO_ENABLED=0 go build -ldflags="-s -w -X main.VERSION=$VER" -trimpath -o installer protector.go
if [ $? -eq 0 ]; then
    echo "  -> OK: arquivo 'installer' gerado."
else
    echo "  -> ERRO ao compilar protector.go"
    exit 1
fi

echo ""
echo "=========================================="
echo "           BUILD CONCLUÍDO!               "
echo "=========================================="
echo "1. Envie os arquivos 'server', 'hox.sh' e 'installer' para o seu GitHub."
echo "2. Certifique-se de que o GITHUB_BASE_URL no protector.go aponte para o local correto."
echo "3. Seus clientes devem baixar apenas o 'installer'."
echo "=========================================="
