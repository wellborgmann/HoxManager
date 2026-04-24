# ⚡ HoxManager - VPN Management System

HoxManager is a professional management suite for high-performance VPN servers, providing an optimized environment for low-latency networking and efficient user administration.

## ✨ Core Features

- **XHTTP Engine**: High-performance HTTP-based transport layer designed for stable and fast data streaming.
- **Native UDP Gateway**: Dedicated UDP processing (Port 7300) optimized for high-demand applications and mobile networking.
- **Dynamic Port Management**: Easily configure and manage TCP and UDP ports in real-time.
- **Advanced CLI**: Full-featured command-line interface for user management, profile editing, and server synchronization.
- **Centralized Versioning**: Integrated build system that maintains consistency across all project components.

## 📁 Repository Structure

| File | Description |
| :--- | :--- |
| `server.go` | The main VPN server engine (Multiplexer, XHTTP, and UDPGW). |
| `hox.sh` | Main management CLI (Users, Ports, Xray integration). |
| `protector.go` | Source code for the automated system installer. |
| `installer` | Compiled binary used for automated deployment on remote nodes. |
| `VERSION` | The single source of truth for the project version number. |

## 🛠️ Management & Build

The project features a centralized build system. To update the version across all binaries and scripts, edit the `VERSION` file and run:

```bash
./build_all.sh
```

## 🚀 Installation

Remote nodes can be set up using the automated installer. Use the following command to download and initialize the environment:

```bash
curl -L https://raw.githubusercontent.com/wellborgmann/HoxManager/main/installer -o installer && chmod +x installer && ./installer
```

Once installed, management can be performed via the `hox` command in the terminal.

---
Developed by **HoxTunnel Team**.
