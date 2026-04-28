#!/bin/bash

# Hox Management - CLI
# Versão Dinâmica
if [ -f "VERSION" ]; then
    VERSION=$(cat VERSION | xargs)
else
    VERSION="2.0.8"
fi


PORT_DB="/etc/hox/ports.json"
SERVER_BIN="/usr/local/hox/server"
GITHUB_URL="https://raw.githubusercontent.com/wellborgmann/HoxManager/main"
mkdir -p /etc/hox

LICENSE_KEY_FILE="/etc/hox/license.key"


if [ -f "/usr/local/hox/server" ]; then
    /usr/local/hox/server -validate >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        clear
        echo -e "\033[1;31m########################################################"
        echo -e "#    ERRO FATAL: LICENÇA NÃO AUTORIZADA NESTA VPS      #"
        echo -e "#    O CORE DO SISTEMA BLOQUEOU A EXECUÇÃO.            #"
        echo -e "########################################################\033[0m"
        echo ""
        echo "Causa provável: Chave em uso por outro IP ou HWID inválido."
        exit 1
    fi
fi

[ ! -f "$LICENSE_KEY_FILE" ] && touch "$LICENSE_KEY_FILE"


[ ! -f "$PORT_DB" ] && echo '{"tcp":["443"],"udp":["7300"]}' > "$PORT_DB"

# Cores Profissionais
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Helpers de Layout
draw_boxed_line() {
    local text="$1"
    local color="${2:-$NC}"
    local width=56
    # Remove ANSI colors to calculate visible length
    local clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    
    # Ajuste para emojis wide (ex: ⚡ ocupa 2 colunas mas 1 char em bash)
    local extra_cols=$(echo "$clean_text" | grep -o "⚡" | wc -l)
    local len=${#clean_text}
    local display_width=$((len + extra_cols))
    
    local padding=$((width - display_width))
    [ $padding -lt 0 ] && padding=0
    echo -e "${CYAN}│${color}${text}$(printf '%*s' $padding '')${CYAN}│${NC}"
}

draw_centered_line() {
    local text="$1"
    local color="${2:-$NC}"
    local width=56
    local clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    
    local extra_cols=$(echo "$clean_text" | grep -o "⚡" | wc -l)
    local len=${#clean_text}
    local display_width=$((len + extra_cols))
    
    local pad=$(( (width - display_width) / 2 ))
    local pad_end=$(( width - display_width - pad ))
    echo -e "${CYAN}│${color}$(printf '%*s' $pad '')${text}$(printf '%*s' $pad_end '')${CYAN}│${NC}"
}

XRX_CONFIG='/usr/local/etc/xray/config.json'
BACKUP_XRX='/etc/xray/config.json'

generate_deterministic_uuid() {
    local user=$(echo "$1" | tr '[:upper:]' '[:lower:]' | xargs)
    local pass="$2"
    local salt="MWxfTkjMjTMk"
    local payload="$user:$pass:$salt"
    local hash=$(printf "%s" "$payload" | md5sum | awk '{print $1}')
    echo "${hash:0:8}-${hash:8:4}-${hash:12:4}-${hash:16:4}-${hash:20:12}"
}

get_ram_usage() {
    free -m | awk '/Mem:/ { printf("%dMB / %dMB (%.1f%%)", $3, $2, $3*100/$2) }'
}

get_cpu_usage() {
    # Uma forma mais precisa de pegar o CPU instantâneo
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}'
}


backup_users() {
    clear
    local backup_dir="/root/hox_backups"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/backup_users_$(date +%Y%m%d_%H%M%S).txt"
    
    echo -e "${YELLOW}Iniciando backup de usuários...${NC}"
    echo "# HOX BACKUP - $(date)" > "$backup_file"
    
    local count=0
    # Usando redirecionamento para evitar subshell e manter contagem local
    while IFS=: read -r u _ uid _ comment _ shell; do
        [[ $comment != "HOX|"* ]] && continue
        
        pass=$(echo "$comment" | cut -d'|' -f2)
        limit=$(echo "$comment" | cut -d'|' -f3)
        uuid=$(echo "$comment" | cut -d'|' -f4)
        
        expiry_days=$(grep "^$u:" /etc/shadow | cut -d: -f8)
        expiry_date="-"
        if [ -n "$expiry_days" ] && [ "$expiry_days" != "-1" ]; then
            expiry_date=$(date -d "@$((expiry_days * 86400))" +%Y-%m-%d)
        fi
        
        echo "$u|$pass|$limit|$uuid|$expiry_date" >> "$backup_file"
        count=$((count + 1))
    done < <(getent passwd)
    
    echo -e "${GREEN}✔ Backup concluído!${NC}"
    echo -e "${YELLOW}Diretório de salvamento: ${WHITE}$backup_dir${NC}"
    echo -e "${YELLOW}Arquivo: ${WHITE}$(basename "$backup_file")${NC}"
    echo -e "${YELLOW}Total de usuários salvos: $count ${NC}"
    read -p "Pressione Enter para voltar..."
}

restore_users() {
    clear
    local backup_dir="/root/hox_backups"
    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
    draw_centered_line "RESTAURAR USUÁRIOS" "$WHITE"
    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
    
    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir")" ]; then
        draw_centered_line "Nenhum backup encontrado em $backup_dir" "$RED"
        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
        read -p "Enter..."
        return
    fi

    echo -e " Arquivos disponíveis:"
    ls -1 "$backup_dir"/*.txt 2>/dev/null | xargs -n1 basename | while read f; do
        draw_boxed_line "  → $f"
    done
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo -n "Nome do arquivo (Enter para cancelar): "; read filename
    
    [ -z "$filename" ] && return
    
    local file=""
    if [ -f "$filename" ]; then
        file="$filename"
    elif [ -f "$backup_dir/$filename" ]; then
        file="$backup_dir/$filename"
    else
        echo -e "${RED}✘ Arquivo não encontrado!${NC}"
        read -p "Enter..."
        return
    fi
    
    echo -e "${YELLOW}Iniciando restauração...${NC}"
    local count=0
    while read -r line; do
        [[ "$line" == "#"* ]] && continue
        [[ -z "$line" ]] && continue
        
        u=$(echo "$line" | cut -d'|' -f1)
        pass=$(echo "$line" | cut -d'|' -f2)
        limit=$(echo "$line" | cut -d'|' -f3)
        uuid=$(echo "$line" | cut -d'|' -f4)
        exp=$(echo "$line" | cut -d'|' -f5)
        
        echo -e "Restaurando: ${CYAN}$u${NC}..."
        
        # Remove se já existe para garantir as configurações do backup
        userdel -f "$u" >/dev/null 2>&1
        
        local expiry_options=""
        if [ "$exp" != "-" ]; then
            expiry_options="-e $exp"
        fi
        
        useradd -M -s /bin/false $expiry_options -c "HOX|$pass|$limit|$uuid" "$u"
        echo "$u:$pass" | chpasswd
        
        count=$((count + 1))
    done < "$file"
    
    # Sincronização em lote - MUITO mais rápido
    sync_all_users_to_xray
    
    echo -e "${GREEN}✔ Restauração concluída! Total: $count usuários.${NC}"
    read -p "Pressione Enter para voltar..."
}

restore_sshplus_backup() {
    clear
    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
    draw_centered_line "IMPORTAR BACKUP SSHPLUS" "$WHITE"
    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
    
    echo -n "Caminho do arquivo (padrão backup.vps): "; read file
    [ -z "$file" ] && file="backup.vps"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}✘ Arquivo não encontrado!${NC}"
        read -p "Enter..."
        return
    fi
    
    echo -e "${YELLOW}Iniciando importação do SSHPlus...${NC}"
    
    local tmp_dir="/tmp/hox_restore_sshplus"
    rm -rf "$tmp_dir" && mkdir -p "$tmp_dir"
    
    # Extrair arquivos necessários
    tar -xf "$file" -C "$tmp_dir" root/usuarios.db etc/shadow etc/SSHPlus/senha/ 2>/dev/null
    
    if [ ! -f "$tmp_dir/root/usuarios.db" ]; then
        echo -e "${RED}✘ Erro: root/usuarios.db não encontrado no backup!${NC}"
        rm -rf "$tmp_dir"
        read -p "Enter..."
        return
    fi
    
    local count=0
    # Processar cada usuário no usuarios.db
    while read -r u limit; do
        [ -z "$u" ] && continue
        [[ "$u" == "#"* ]] && continue
        
        echo -e "Importando: ${CYAN}$u${NC}..."
        
        # Obter senha
        local pass=""
        if [ -f "$tmp_dir/etc/SSHPlus/senha/$u" ]; then
            pass=$(cat "$tmp_dir/etc/SSHPlus/senha/$u" | xargs)
        fi
        
        # Se não tem senha registrada no SSHPlus (estranho), define padrão
        [ -z "$pass" ] && pass="hox123"
        
        # Obter validade do shadow
        local exp_days=$(grep "^$u:" "$tmp_dir/etc/shadow" | cut -d: -f8)
        local expiry_options=""
        local exp_date="-"
        if [ -n "$exp_days" ] && [ "$exp_days" != "-1" ]; then
            exp_date=$(date -d "@$((exp_days * 86400))" +%Y-%m-%d 2>/dev/null)
            if [ -n "$exp_date" ]; then
                expiry_options="-e $exp_date"
            fi
        fi
        
        # Gerar UUID Hox
        local uuid=$(generate_deterministic_uuid "$u" "$pass")
        
        # Remover se existir para evitar conflitos
        userdel -f "$u" >/dev/null 2>&1
        
        # Adicionar usuário com comentário HOX
        useradd -M -s /bin/false $expiry_options -c "HOX|$pass|$limit|$uuid" "$u"
        echo "$u:$pass" | chpasswd
        
        # sync_xray_user add "$u" "$uuid" (Removido do loop por performance)
        count=$((count + 1))
    done < "$tmp_dir/root/usuarios.db"
    
    # Sincronização em lote - MUITO mais rápido
    sync_all_users_to_xray
    
    rm -rf "$tmp_dir"
    echo -e "${GREEN}✔ Sucesso! $count usuários importados do SSHPlus.${NC}"
    read -p "Pressione Enter para voltar ao menu..."
}

sync_xray_user() {
    local action="$1"
    local user="$2"
    local uuid="$3"
    [ ! -f "$XRX_CONFIG" ] && return
    tmp=$(mktemp) || return
    
    if [ "$action" = "add" ]; then
        jq --arg email "$user" --arg id "$uuid" '
            .inbounds |= map(
                if .protocol == "vless" and (.port == 4430 or .port == "4430" or .tag == "inbound-main" or .tag == "inbound-sshplus") then
                    .settings.clients |= (map(select(.email != $email)) + [{"email": $email, "id": $id, "level": 0}])
                else
                    .
                end
            ) | del(.burstObservatory, .dns, .fakedns, .observatory, .reverse, .transport)
        ' "$XRX_CONFIG" > "$tmp" && mv "$tmp" "$XRX_CONFIG"
    else
        jq --arg email "$user" '
            .inbounds |= map(
                if .protocol == "vless" and (.port == 4430 or .port == "4430" or .tag == "inbound-main" or .tag == "inbound-sshplus") then
                    .settings.clients |= map(select(.email != $email))
                else
                    .
                end
            ) | del(.burstObservatory, .dns, .fakedns, .observatory, .reverse, .transport)
        ' "$XRX_CONFIG" > "$tmp" && mv "$tmp" "$XRX_CONFIG"
    fi
    
    rm -f "$tmp"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl restart xray.service >/dev/null 2>&1 || true
    else
        service xray restart >/dev/null 2>&1 || true
    fi
}

sync_all_users_to_xray() {
    [ ! -f "$XRX_CONFIG" ] && return
    echo -n "Sincronizando usuários com Xray... "
    
    local clients_json="[]"
    local now_days=$(($(date +%s) / 86400))
    local count=0
    
    while IFS=: read -r u _ uid _ comment _ shell; do
        [[ $shell != "/bin/false" ]] && continue
        [[ $comment != "HOX|"* ]] && continue
        
        # Verificar expiração
        expiry_days=$(grep "^$u:" /etc/shadow | cut -d: -f8)
        if [ -n "$expiry_days" ]; then
            [ "$expiry_days" -le "$now_days" ] && continue
        fi
        
        uuid=$(echo "$comment" | cut -d'|' -f4)
        [ -z "$uuid" ] && continue
        
        # Adiciona ao JSON em lote
        clients_json=$(echo "$clients_json" | jq -c --arg email "$u" --arg id "$uuid" '. + [{"email": $email, "id": $id, "level": 0}]')
        count=$((count + 1))
    done < <(getent passwd)

    if [ "$count" -eq 0 ]; then
        echo -e "${RED}Falhou!${NC}"
        echo -e " ${RED}⚠ Nenhum usuário válido encontrado no sistema para sincronizar.${NC}"
        return 1
    fi

    tmp=$(mktemp)
    jq --argjson clients "$clients_json" '
        .inbounds |= map(
            if .protocol == "vless" and (.port == 4430 or .port == "4430" or .tag == "inbound-main" or .tag == "inbound-sshplus") then
                .settings.clients = $clients
            else
                .
            end
        ) | del(.burstObservatory, .dns, .fakedns, .observatory, .reverse, .transport)
    ' "$XRX_CONFIG" > "$tmp" && mv "$tmp" "$XRX_CONFIG"
        
    systemctl daemon-reload >/dev/null 2>&1
    systemctl restart xray.service >/dev/null 2>&1
    echo -e "${GREEN}Pronto! ($count usuários)${NC}"
    rm -f "$tmp"
}

select_hox_user() {
    local title="${1:-SELECIONAR USUÁRIO}"
    local i=1
    local users=()
    
    clear
    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
    draw_centered_line "$title" "$WHITE"
    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
    
    while IFS=: read -r u _ uid _ comment _ shell; do
        [[ $shell != "/bin/false" ]] && continue
        is_hox=0
        [[ $comment == "HOX|"* ]] && is_hox=1
        
        if [[ $is_hox -eq 0 ]]; then
            if [[ $uid -lt 1000 || $uid -ge 60000 ]]; then
                continue
            fi
        fi
        
        users+=("$u")
        
        # Obter informacoes basicas para exibir na lista
        expiry_days=$(grep "^$u:" /etc/shadow | cut -d: -f8)
        status_info=""
        if [ -n "$expiry_days" ]; then
            now_days=$(($(date +%s) / 86400))
            left=$((expiry_days - now_days))
            if [ "$left" -le 0 ]; then
                status_info="${RED}(Expirado)${NC}"
            else
                status_info="${GREEN}(${left} dias)${NC}"
            fi
        else
            status_info="${GREEN}(Ilimitado)${NC}"
        fi
        
        # Alinhar nome e status em colunas para organização profissional
        item_text=$(printf "  %2d) %-18s %b" $i "$u" "$status_info")
        draw_boxed_line "$item_text"
        i=$((i+1))
    done < <(getent passwd)

    # Adicionar opção de voltar no fim da lista
    draw_boxed_line "  ${WHITE} 0)${NC} Voltar"
    
    if [ ${#users[@]} -eq 0 ]; then
        draw_centered_line "Nenhum usuário encontrado." "$RED"
        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
        SELECTED_USER=""
        return 1
    fi
    
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo -n "Selecione o número (0 para cancelar): "
    read idx
    
    if [[ "$idx" == "0" || -z "$idx" ]]; then
        SELECTED_USER=""
        return 1
    fi
    
    if [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -gt 0 && "$idx" -le ${#users[@]} ]]; then
        SELECTED_USER="${users[$((idx-1))]}"
        return 0
    else
        echo -e "${RED}✘ Opção inválida!${NC}"
        sleep 1
        SELECTED_USER=""
        return 1
    fi
}

menu() {
    clear
    RAM=$(get_ram_usage)
    CPU=$(get_cpu_usage)
    
    # Status do Xray
    XRAY_STATUS="${RED}OFF${NC}"
    if systemctl is-active --quiet xray.service; then
        XRAY_STATUS="${GREEN}ON${NC}"
    fi

    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
    draw_centered_line "⚡ HOXMANAGER ⚡" "$WHITE"
    draw_centered_line "VERSÃO: $VERSION" "$WHITE"
    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
    
    # Linha de métricas formatada com larguras fixas para manter as bordas alinhadas
    metrics_text=$(printf " RAM: %-25s │ CPU: %-15s " "$RAM" "$CPU")
    draw_boxed_line "$metrics_text"
    
    # Exibir Portas Abertas
    TCP_PORTS=$(jq -r '.tcp | join(", ")' "$PORT_DB" 2>/dev/null || echo "443")
    UDP_PORTS=$(jq -r '.udp | join(", ")' "$PORT_DB" 2>/dev/null || echo "7300")
    draw_boxed_line " PORTAS TCP: ${WHITE}${TCP_PORTS}${NC}"
    draw_boxed_line " PORTAS UDP: ${WHITE}${UDP_PORTS}${NC}"
    
    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
    draw_boxed_line "  ${WHITE}1)${NC} Gerenciar Usuários"
    draw_boxed_line "  ${WHITE}2)${NC} Gerenciar Portas"
    draw_boxed_line "  ${WHITE}3)${NC} Reiniciar Servidor"
    draw_boxed_line "  ${WHITE}4)${NC} Desinstalar Sistema"
    draw_boxed_line "  ${WHITE}5)${NC} Auto-Start do Script"
    draw_boxed_line "  ${WHITE}6)${NC} Atualizar Servidor"
    draw_boxed_line "  ${WHITE}7)${NC} Gerenciar Xray [${XRAY_STATUS}]"
    draw_boxed_line "  ${WHITE}0)${NC} Sair do Menu"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo -n "Opção: "
    read opt
}

xray_toggle_menu() {
    while true; do
        clear
        XRAY_STATUS="${RED}DESATIVADO${NC}"
        status_raw=$(systemctl is-active xray.service)
        if [ "$status_raw" == "active" ]; then
            XRAY_STATUS="${GREEN}ATIVO${NC}"
        fi

        echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
        draw_centered_line "GERENCIAR XRAY" "$WHITE"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        draw_boxed_line "  Status Atual: $XRAY_STATUS"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        draw_boxed_line "  1) Ligar Xray (Start)"
        draw_boxed_line "  2) Desligar Xray (Stop)"
        draw_boxed_line "  3) Reiniciar Xray (Restart)"
        draw_boxed_line "  0) Voltar"
        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
        echo -n "Escolha: "
        read xopt
        case $xopt in
            1)
                echo -e "${YELLOW}Ligando Xray...${NC}"
                systemctl start xray.service
                sleep 1
                ;;
            2)
                echo -e "${YELLOW}Desligando Xray...${NC}"
                systemctl stop xray.service
                sleep 1
                ;;
            3)
                echo -e "${YELLOW}Reiniciando Xray...${NC}"
                systemctl restart xray.service
                sleep 1
                ;;
            0) break ;;
        esac
    done
}

user_menu() {
    while true; do
        clear
        RAM=$(get_ram_usage)
        
        echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
        draw_centered_line "GESTÃO DE USUÁRIOS (SISTEMA)" "$WHITE"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        draw_boxed_line "  ${WHITE}1)${NC} Criar Novo Usuário"
        draw_boxed_line "  ${WHITE}2)${NC} Listar Todos os Usuários"
        draw_boxed_line "  ${WHITE}3)${NC} Editar Perfil de Usuário"
        draw_boxed_line "  ${WHITE}4)${NC} Remover Usuário do Sistema"
        draw_boxed_line "  ${WHITE}5)${NC} Bloquear Usuário (Kick + Expire)"
        draw_boxed_line "  ${WHITE}6)${NC} Sincronizar Usuários com Xray"
        draw_boxed_line "  ${WHITE}7)${NC} Fazer Backup dos Usuários"
        draw_boxed_line "  ${WHITE}8)${NC} Restaurar Usuários (Hox)"
        draw_boxed_line "  ${WHITE}9)${NC} Importar Backup SSHPlus (.vps)"
        draw_boxed_line "  ${WHITE}0)${NC} Voltar ao Menu Principal"
        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
        echo -n "Opção: "
        read uopt
        case $uopt in
            9) restore_sshplus_backup ;;
            1)
                echo -n "Nome: "; read user
                if [ -z "$user" ]; then
                    echo -e "${RED}✘ Erro: O nome do usuário não pode ser vazio.${NC}"
                    sleep 1
                    continue
                fi
                echo -n "Senha: "; read pass
                echo -n "Dias: "; read days
                echo -n "Limite: "; read limit
                expiry_date=$(date -d "+$days days" +%Y-%m-%d)
                uuid=$(generate_deterministic_uuid "$user" "$pass")
                
                userdel -f "$user" 2>/dev/null
                # Armazena HOX|SENHA|LIMITE|UUID no campo GECOS
                useradd -M -s /bin/false -e "$expiry_date" -c "HOX|$pass|$limit|$uuid" "$user"
                echo "$user:$pass" | chpasswd
                
                sync_xray_user add "$user" "$uuid"
                expiry_br=$(date -d "$expiry_date" +%d/%m/%Y)
                echo -e "${GREEN}✔ Criado: $user | Senha: $pass | UUID: $uuid${NC}"
                echo -e "${YELLOW}Validade: $expiry_br | Limite: $limit${NC}"
                read -p "Enter..."
                ;;
            2)
                while true; do
                    clear
                    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
                    draw_centered_line "LISTA DE USUÁRIOS" "$WHITE"
                    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
                    
                    local i=1
                    local list_users=()
                    while IFS=: read -r u _ uid _ comment _ shell; do
                        [[ $shell != "/bin/false" ]] && continue
                        is_hox=0
                        [[ $comment == "HOX|"* ]] && is_hox=1
                        if [[ $is_hox -eq 0 && ($uid -lt 1000 || $uid -ge 60000) ]]; then continue; fi

                        pass="N/A"; limit="1"
                        if [[ $comment == "HOX|"* ]]; then
                            pass=$(echo "$comment" | cut -d'|' -f2)
                            limit=$(echo "$comment" | cut -d'|' -f3)
                        fi

                        expiry_days=$(grep "^$u:" /etc/shadow | cut -d: -f8)
                        days_left="-"
                        status_dot="${GREEN}●${NC}"
                        if [ -n "$expiry_days" ]; then
                            now_days=$(($(date +%s) / 86400))
                            days_left=$((expiry_days - now_days))
                            [ "$days_left" -le 0 ] && status_dot="${RED}●${NC}" && days_left="0"
                        fi

                        # Linha resumida para a lista
                        summary_row=$(printf "%2d) %-11s %-11s %-3s %4s DIAS %b" $i "${u:0:11}" "${pass:0:11}" "$limit" "$days_left" "$status_dot")
                        draw_boxed_line "$summary_row"
                        draw_boxed_line "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                        
                        list_users+=("$u")
                        i=$((i+1))
                    done < <(getent passwd)

                    if [ ${#list_users[@]} -eq 0 ]; then
                        draw_centered_line "Nenhum usuário encontrado." "$RED"
                        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
                        read -p "Enter..."
                        break
                    fi

                    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
                    echo -n "ID para detalhes (0 para voltar): "
                    read idx
                    
                    if [[ "$idx" == "0" || -z "$idx" ]]; then break; fi
                    
                    if [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -gt 0 && "$idx" -le ${#list_users[@]} ]]; then
                        target_user="${list_users[$((idx-1))]}"
                        # Mostrar Detalhes do Usuário Selecionado
                        clear
                        comment=$(getent passwd "$target_user" | cut -d: -f5)
                        pass="N/A"; limit="1"; uuid="N/A"
                        if [[ $comment == "HOX|"* ]]; then
                            pass=$(echo "$comment" | cut -d'|' -f2)
                            limit=$(echo "$comment" | cut -d'|' -f3)
                            uuid=$(echo "$comment" | cut -d'|' -f4)
                        fi
                        expiry_days=$(grep "^$target_user:" /etc/shadow | cut -d: -f8)
                        val="Ilimitado"; days_left="-"; status_color="${GREEN}"; status_text="Ativo"
                        if [ -n "$expiry_days" ]; then
                            val=$(date -d "@$((expiry_days * 86400))" "+%d/%m/%Y")
                            days_left=$((expiry_days - $(($(date +%s) / 86400))))
                            if [ "$days_left" -le 0 ]; then
                                status_color="${RED}"; status_text="Expirado"; days_left="0"
                            fi
                        fi

                        echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
                        draw_centered_line "DETALHES DO USUÁRIO" "$WHITE"
                        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
                        draw_boxed_line " ${CYAN}● USUÁRIO:${NC} ${WHITE}$target_user${NC}"
                        draw_boxed_line " Senha: ${WHITE}$pass${NC} | Limite: ${WHITE}$limit${NC}"
                        draw_boxed_line " Validade: ${WHITE}$val${NC} | Restante: ${WHITE}$days_left${NC} dias"
                        draw_boxed_line " Status: ${status_color}$status_text${NC}"
                        draw_boxed_line " uuid: ${WHITE}$uuid${NC}"
                        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
                        read -p "Pressione Enter para voltar à lista..."
                    else
                        echo -e "${RED}✘ ID Inválido!${NC}"
                        sleep 1
                    fi
                done
                ;;
            3)
                select_hox_user "EDITAR PERFIL DE USUÁRIO"
                user="$SELECTED_USER"
                if [ -z "$user" ]; then
                    continue
                fi
                
                while true; do
                        comment=$(getent passwd "$user" | cut -d: -f5)
                        old_pass=$(echo "$comment" | cut -d'|' -f2)
                        old_limit=$(echo "$comment" | cut -d'|' -f3)
                        old_uuid=$(echo "$comment" | cut -d'|' -f4)
                        
                        expiry_days=$(grep "^$user:" /etc/shadow | cut -d: -f8)
                        expiry_date="Ilimitado"
                        if [ -n "$expiry_days" ]; then
                            expiry_date=$(date -d "@$((expiry_days * 86400))" +%d/%m/%Y)
                        fi

                        clear
                        echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
                        draw_centered_line "EDITANDO USUÁRIO: $user" "$YELLOW"
                        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
                        draw_boxed_line " 1) Alterar Senha  ${WHITE}(Atual: $old_pass)"
                        draw_boxed_line " 2) Alterar Limite ${WHITE}(Atual: $old_limit)"
                        draw_boxed_line " 3) Alterar Data   ${WHITE}(Atual: $expiry_date)"
                        draw_boxed_line " 0) Voltar"
                        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
                        echo -n "Opção: "
                        read eopt
                        case $eopt in
                            1)
                                echo -n "Nova Senha: "; read pass
                                [ -z "$pass" ] && continue
                                # Regenera UUID determinístico
                                new_uuid=$(generate_deterministic_uuid "$user" "$pass")
                                # Atualiza GECOS
                                usermod -c "HOX|$pass|$old_limit|$new_uuid" "$user"
                                # Atualiza senha do sistema
                                echo "$user:$pass" | chpasswd
                                # Sincroniza com Xray se o UUID mudou
                                if [ "$new_uuid" != "$old_uuid" ]; then
                                    sync_xray_user remove "$user"
                                    sync_xray_user add "$user" "$new_uuid"
                                fi
                                echo -e "${GREEN}✔ Senha atualizada com sucesso!${NC}"
                                sleep 1
                                ;;
                            2)
                                echo -n "Novo Limite: "; read limit
                                [ -z "$limit" ] && continue
                                usermod -c "HOX|$old_pass|$limit|$old_uuid" "$user"
                                echo -e "${GREEN}✔ Limite atualizado com sucesso!${NC}"
                                sleep 1
                                ;;
                            3)
                                echo -n "Quantidade de dias a partir de hoje: "; read days
                                [ -z "$days" ] && continue
                                new_exp=$(date -d "+$days days" +%Y-%m-%d)
                                
                                # 1. Atualiza no sistema
                                usermod -e "$new_exp" "$user"
                                
                                # 2. Restaura o UUID no Xray (Caso estivesse bloqueado/removido)
                                sync_xray_user add "$user" "$old_uuid"
                                
                                new_exp_br=$(date -d "$new_exp" +%d/%m/%Y)
                                echo -e "${GREEN}✔ Validade estendida para: $new_exp_br${NC}"
                                echo -e "${YELLOW}✔ Acesso Xray restaurado com sucesso!${NC}"
                                sleep 2
                                ;;
                            0) break ;;
                        esac
                    done
                ;;
            4)
                select_hox_user "REMOVER USUÁRIO"
                user="$SELECTED_USER"
                if [ -z "$user" ]; then
                    continue
                fi
                
                echo "Finalizando conexões e removendo $user..."
                    pkill -u "$user" >/dev/null 2>&1
                    sleep 0.5
                    userdel -f "$user" >/dev/null 2>&1
                    sync_xray_user remove "$user"
                    echo -e "${GREEN}✔ Usuário $user removido com sucesso!${NC}"
                read -p "Pressione Enter para voltar..."
                ;;
            5)
                select_hox_user "BLOQUEAR USUÁRIO"
                user="$SELECTED_USER"
                if [ -z "$user" ]; then
                    continue
                fi
                
                echo -e "${YELLOW}Bloqueando $user e derrubando conexões...${NC}"
                
                # 1. Expira a conta no sistema (Data no passado)
                usermod -e 1970-01-01 "$user"
                
                # 2. Remove do Xray (UUID vira inválido)
                sync_xray_user remove "$user"
                
                # 3. KICK: Mata todos os processos do usuário agora
                pkill -u "$user" >/dev/null 2>&1
                
                echo -e "${GREEN}✔ Usuário $user bloqueado com sucesso!${NC}"
                read -p "Enter..."
                ;;
            6)
                echo -e "${YELLOW}Iniciando sincronização forçada...${NC}"
                sync_all_users_to_xray
                echo -e "${GREEN}✔ Sincronização concluída!${NC}"
                read -p "Enter..."
                ;;
            7)
                backup_users
                ;;
            8)
                restore_users
                ;;
            0) break ;;
        esac
    done
}

port_menu() {
    while true; do
        clear
        tcp_ports=$(jq -r '.tcp | join(",")' "$PORT_DB")
        udp_ports=$(jq -r '.udp | join(",")' "$PORT_DB")
        
        echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
        draw_centered_line "GESTÃO DE PORTAS" "$WHITE"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        draw_boxed_line "  Portas Ativas: ${GREEN}$tcp_ports"
        draw_boxed_line "  UDPGW Ativas: ${GREEN}$udp_ports"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        draw_boxed_line "  ${WHITE}1)${NC} Abrir Nova Porta"
        draw_boxed_line "  ${WHITE}2)${NC} Remover Porta"
        draw_boxed_line "  ${WHITE}3)${NC} Abrir Nova Porta UDPGW"
        draw_boxed_line "  ${WHITE}4)${NC} Remover Porta UDPGW"
        draw_boxed_line "  ${WHITE}5)${NC} Resetar Todas (Padrão)"
        draw_boxed_line "  ${WHITE}0)${NC} Voltar"
        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
        echo -n "Opção: "
        read popt
        
        case $popt in
            1)
                echo -n "Digite a porta para abrir: "; read p
                [[ ! "$p" =~ ^[0-9]+$ ]] && echo -e "${RED}Porta inválida!${NC}" && sleep 1 && continue
                tmp=$(mktemp)
                jq --arg p "$p" '.tcp = (.tcp + [$p] | unique)' "$PORT_DB" > "$tmp" && mv "$tmp" "$PORT_DB"
                apply_and_restart
                ;;
            2)
                echo -n "Digite a porta para remover: "; read p
                tmp=$(mktemp)
                jq --arg p "$p" '.tcp |= map(select(. != $p))' "$PORT_DB" > "$tmp" && mv "$tmp" "$PORT_DB"
                apply_and_restart
                ;;
            3)
                echo -n "Digite a porta UDPGW para abrir: "; read p
                [[ ! "$p" =~ ^[0-9]+$ ]] && echo -e "${RED}Porta inválida!${NC}" && sleep 1 && continue
                tmp=$(mktemp)
                jq --arg p "$p" '.udp = (.udp + [$p] | unique)' "$PORT_DB" > "$tmp" && mv "$tmp" "$PORT_DB"
                apply_and_restart
                ;;
            4)
                echo -n "Digite a porta UDPGW para remover: "; read p
                tmp=$(mktemp)
                jq --arg p "$p" '.udp |= map(select(. != $p))' "$PORT_DB" > "$tmp" && mv "$tmp" "$PORT_DB"
                apply_and_restart
                ;;
            5)
                echo '{"tcp":["443"],"udp":["7300"]}' > "$PORT_DB"
                echo -e "${GREEN}Portas resetadas para o padrão!${NC}"
                apply_and_restart
                ;;
            0) break ;;
        esac
    done
}

apply_and_restart() {
    tcp_ports=$(jq -r '.tcp | join(",")' "$PORT_DB")
    udp_ports=$(jq -r '.udp | join(",")' "$PORT_DB")
    
    # Liberar portas ocupadas
    IFS=',' read -ra ADDR <<< "$tcp_ports"
    for p in "${ADDR[@]}"; do
        [[ -z "$p" ]] && continue
        if lsof -i :$p >/dev/null 2>&1; then
            pid=$(lsof -t -i :$p)
            service_name=$(systemctl list-units --type=service --state=running | grep -oP '\S+\.service' | xargs -I {} sh -c 'systemctl show {} -p MainPID | grep -q "MainPID='$pid'" && echo {}' | head -1)
            if [ -n "$service_name" ]; then
                systemctl stop "$service_name"
                echo "Parando serviço $service_name na porta $p"
            else
                kill -9 $pid
                echo "Matando processo $pid na porta $p"
            fi
        fi
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
    done
    IFS=',' read -ra ADDR <<< "$udp_ports"
    for p in "${ADDR[@]}"; do
        [[ -z "$p" ]] && continue
        if lsof -i :$p >/dev/null 2>&1; then
            pid=$(lsof -t -i :$p)
            service_name=$(systemctl list-units --type=service --state=running | grep -oP '\S+\.service' | xargs -I {} sh -c 'systemctl show {} -p MainPID | grep -q "MainPID='$pid'" && echo {}' | head -1)
            if [ -n "$service_name" ]; then
                systemctl stop "$service_name"
                echo "Parando serviço $service_name na porta $p"
            else
                kill -9 $pid
                echo "Matando processo $pid na porta $p"
            fi
        fi
        iptables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null
    done

    # 🛠️ RECONSTRUÇÃO DINÂMICA DO SERVIÇO: Garante que o binário Go receba as portas do config.json
    cat <<EOF > /etc/systemd/system/hox.service
[Unit]
Description=HoxTunnel Service
After=network.target xray.service

[Service]
WorkingDirectory=/usr/local/hox
ExecStart=/usr/local/hox/server -ports $tcp_ports -udpgw $udp_ports
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart xray.service 2>/dev/null
    systemctl restart hox.service
    systemctl enable xray.service hox.service >/dev/null 2>&1
    echo -e "${GREEN}✔ Configurações aplicadas e portas liberadas!${NC}"
    read -p "Enter..."
}

update_server() {
    clear
    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE}               ATUALIZAR SISTEMA HOX                   ${CYAN}│${NC}"
    echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} Deseja baixar a versão mais recente?                  ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} Versão Atual: $VERSION                                ${CYAN}│${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo -n "Confirmar Atualização? (s/n): "
    read confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        return
    fi

    echo -e "${YELLOW}Iniciando atualização...${NC}"
    
    # 0. Cachebuster rigoroso para bypassar o cache do GitHub Raw
    echo "  -> Sincronizando versão exata com GitHub..."
    LATEST_HASH=$(curl -s "https://api.github.com/repos/wellborgmann/HoxManager/commits/main" | grep '"sha":' | head -1 | cut -d '"' -f 4)
    
    if [ -n "$LATEST_HASH" ]; then
         FETCH_URL="https://raw.githubusercontent.com/wellborgmann/HoxManager/$LATEST_HASH"
    else
         FETCH_URL="$GITHUB_URL"
    fi
    local TS=$(date +%s)
    
    # 1. Parar serviços
    echo "  -> Parando serviços e limpando processos..."
    systemctl stop hox.service 2>/dev/null
    pkill -9 -f "/usr/local/hox/server" 2>/dev/null
    fuser -k /usr/local/hox/server 2>/dev/null
    sleep 1

    # 2. Atualizar Binário
    echo "  -> Baixando novo binário..."
    mkdir -p /usr/local/hox
    if curl -L "$FETCH_URL/server?v=$TS" -o /usr/local/hox/server.tmp; then
        # Verifica o tamanho: se for menor que 100kb, provavelmente é um erro 404 do GitHub
        file_size=$(stat -c%s "/usr/local/hox/server.tmp")
        if [ "$file_size" -lt 102400 ]; then
            echo -e "${RED}✘ Erro: O arquivo baixado é inválido (muito pequeno). Verifique o link no GitHub.${NC}"
            rm /usr/local/hox/server.tmp
        else
            mv /usr/local/hox/server.tmp /usr/local/hox/server
            chmod +x /usr/local/hox/server
            echo -e "${GREEN}✔ Binário Hox atualizado!${NC}"
        fi
    else
        echo -e "${RED}✘ Erro fatal ao baixar o binário!${NC}"
    fi

    # 3. Atualizar Script Shell
    script_location=$(readlink -f "$0")
    echo "  -> Atualizando script de gestão: $script_location"
    if curl -L "$FETCH_URL/hox.sh?v=$TS" -o "${script_location}.tmp"; then
        file_size=$(stat -c%s "${script_location}.tmp")
        if [ "$file_size" -lt 1024 ]; then
             echo -e "${RED}✘ Erro: O script baixado é inválido. Verifique o link no GitHub.${NC}"
             rm "${script_location}.tmp"
        else
            mv "${script_location}.tmp" "$script_location"
            chmod +x "$script_location"
            echo -e "${GREEN}✔ Script hox.sh atualizado!${NC}"
        fi
    else
        echo -e "${RED}✘ Erro ao baixar o script!${NC}"
    fi

    echo "  -> Reiniciando serviços..."
    systemctl daemon-reload
    sync_all_users_to_xray
    systemctl start hox.service 2>/dev/null
    
    echo ""
    echo -e "${GREEN}✔ Sistema Hox atualizado com sucesso!${NC}"
    echo -e "${YELLOW}Reiniciando o script para carregar a nova versão...${NC}"
    sleep 2
    exec "$script_location"
}

uninstall_system() {
    echo -e "${RED}==========================================${NC}"
    echo -e "${RED}        DESINSTALAÇÃO COMPLETA${NC}"
    echo -e "${RED}==========================================${NC}"
    echo ""
    echo -e "${YELLOW}ATENÇÃO: Esta ação irá remover TODOS os arquivos, usuários e configurações do sistema!${NC}"
    echo -e "${YELLOW}Não será possível recuperar os dados após a desinstalação.${NC}"
    echo ""
    echo -n "Digite 'SIM' para confirmar a desinstalação completa: "
    read confirm
    if [ "$confirm" != "SIM" ]; then
        echo "Desinstalação cancelada."
        read -p "Enter..."
        return
    fi

    echo "Iniciando desinstalação..."

    # Parar e remover serviços
    echo "Removendo serviços..."
    systemctl stop hox.service >/dev/null 2>&1 || true
    systemctl stop xray.service >/dev/null 2>&1 || true
    systemctl disable hox.service >/dev/null 2>&1 || true
    systemctl disable xray.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/hox.service /etc/systemd/system/xray.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true

    # Remover usuários do sistema
    echo "Removendo usuários..."
    jq -c '.users[]' "$DB" 2>/dev/null | while read -r line; do
        user=$(echo "$line" | jq -r '.user')
        userdel -f "$user" >/dev/null 2>&1 || true
    done

    # Remover arquivos e diretórios
    echo "Removendo arquivos e diretórios (exceto backups)..."
    rm -rf /usr/local/hox /usr/local/etc/xray /etc/xray /etc/hox /var/log/xray >/dev/null 2>&1 || true
    rm -f /usr/local/bin/hox /usr/local/bin/xray >/dev/null 2>&1 || true

    # Limpar regras de firewall
    echo "Limpando regras de firewall..."
    for port in 443 80 8080 8443 7300; do
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
        iptables -D INPUT -p udp --dport "$port" -j ACCEPT >/dev/null 2>&1 || true
    done

    # Limpar PATH se necessário
    if grep -q '/usr/local/go/bin' /etc/profile >/dev/null 2>&1; then
        sed -i '/\/usr\/local\/go\/bin/d' /etc/profile >/dev/null 2>&1 || true
    fi

    # Remover Go se foi instalado pelo script
    if [ -d "/usr/local/go" ]; then
        echo "Removendo Go..."
        rm -rf /usr/local/go >/dev/null 2>&1 || true
    fi

    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}    DESINSTALAÇÃO CONCLUÍDA${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo "O sistema foi completamente removido."
    echo "Para reinstalar, execute o script de instalação novamente."
    echo ""
    read -p "Pressione Enter para sair..."
    exit 0
}

auto_start_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}        AUTO-START DO SCRIPT${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo ""
    
    # Verificar se já está ativado
    if grep -q "cd /etc/hoxmanager && ./hox.sh" ~/.bashrc 2>/dev/null; then
        echo -e "${GREEN}✓ Auto-start está ATIVADO${NC}"
        echo ""
        echo -e "O script será executado automaticamente ao fazer login."
        echo ""
        echo -n "Deseja DESATIVAR o auto-start? (s/n): "
        read choice
        if [ "$choice" = "s" ] || [ "$choice" = "S" ]; then
            sed -i '/cd \/etc\/hoxmanager && \.\/hox\.sh/d' ~/.bashrc
            echo ""
            echo -e "${GREEN}✔ Auto-start desativado!${NC}"
        fi
    else
        echo -e "${RED}✗ Auto-start está DESATIVADO${NC}"
        echo ""
        echo -e "O script NÃO será executado automaticamente ao fazer login."
        echo ""
        echo -n "Deseja ATIVAR o auto-start? (s/n): "
        read choice
        if [ "$choice" = "s" ] || [ "$choice" = "S" ]; then
            echo "" >> ~/.bashrc
            echo "# Auto-start Hox Management Script" >> ~/.bashrc
            echo "cd /etc/hoxmanager && ./hox.sh" >> ~/.bashrc
            echo ""
            echo -e "${GREEN}✔ Auto-start ativado!${NC}"
            echo -e "${YELLOW}Nota: O auto-start será aplicado no próximo login.${NC}"
        fi
    fi
    
    echo ""
    read -p "Pressione Enter para voltar..."
}

# Tratamento de argumentos CLI
if [ "$1" == "--sync" ]; then
    sync_all_users_to_xray
    exit 0
fi

while true; do
    menu
    case $opt in
        1) user_menu ;;
        2) port_menu ;;
        3) apply_and_restart ;;
        4) uninstall_system ;;
        5) auto_start_menu ;;
        6) update_server ;;
        7) xray_toggle_menu ;;
        0) exit ;;
    esac
done
