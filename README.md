# ⚡ HoxManager - VPN Management System

[English version below]

HoxManager é uma suíte de gerenciamento profissional para servidores VPN de alto desempenho, oferecendo um ambiente otimizado para redes de baixa latência e administração eficiente de usuários.

## ✨ Diferenciais e Funcionalidades

- **Multiplexação Universal de Protocolos**: Permite que **qualquer porta** configurada no sistema funcione como um ponto de entrada universal. O software identifica automaticamente o protocolo (SSH, XHTTP, SOCKS, Xray Nativo) e realiza o roteamento sem conflitos. Isso elimina a necessidade de múltiplas VPS ou de dedicar portas específicas para cada serviço.
- **Ghost-XHTTP Engine**: Camada de transporte baseada em HTTP otimizada para streaming de dados estável em ambientes de rede complexos.
- **Native UDP Gateway**: Processamento UDP dedicado (Porta 7300) otimizado para jogos mobile e aplicações de baixa latência.
- **Gestão de Portas Flexível**: Adicione ou remova portas ouvintes a qualquer momento. Todas as portas abertas suportam todos os protocolos simultaneamente.
- **CLI Avançada**: Interface completa para gestão de usuários, edição de perfis e controle de serviços.

## 🚀 Instalação

Os nós remotos podem ser configurados usando o instalador automatizado:

```bash
curl -L https://raw.githubusercontent.com/wellborgmann/HoxManager/main/installer -o installer && chmod +x installer && ./installer
```

---


# ⚡ HoxManager - VPN Management System (English)

HoxManager is a professional management suite for high-performance VPN servers, providing an optimized environment for low-latency networking and efficient user administration.

## ✨ Core Features

- **Universal Protocol Multiplexing**: Any configured port on the system acts as a universal entry point. The software automatically identifies the protocol (SSH, XHTTP, SOCKS, Native Xray) and routes the traffic without conflicts. This eliminates the need for multiple VPS instances or dedicated ports for each service.
- **XHTTP Engine**: High-performance HTTP-based transport layer designed for stable data streaming.
- **Native UDP Gateway**: Dedicated UDP processing (Port 7300) optimized for mobile gaming and low-latency applications.
- **Flexible Port Management**: Add or remove listening ports at any time. Every open port supports all protocols simultaneously through active sniffing.
- **Advanced CLI**: Full-featured command-line interface for user management, profile editing, and service control.

## 🚀 Installation

Remote nodes can be set up using the automated installer:

```bash
curl -L https://raw.githubusercontent.com/wellborgmann/HoxManager/main/installer -o installer && chmod +x installer && ./installer
```

Once installed, management can be performed via the `hox` command in the terminal.

---
Developed by **HoxTunnel Team**.
