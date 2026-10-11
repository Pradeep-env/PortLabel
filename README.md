# PortLabel

> Map local port numbers to human-readable `.local` domains instantly.

PortLabel is a lightweight local reverse-proxy manager for developers and self-hosters. It bridges `/etc/hosts` and Caddy to eliminate messy port numbers (e.g. `localhost:8080`, `localhost:5678`) in favor of clean URLs like `http://n8n.local` and `http://grafana.local`.

---

## Features

- **Zero-Fuss Domains:** Instantly route `http://<service>.local` to any localhost port.
- **Dual Interface:** Full-featured interactive terminal menu (`CLI`) + modern dark-mode web dashboard.
- **Smart Fallback Engine:** If an upstream service stops, Caddy intercepts `502`/`503` errors and serves a live auto-reconnect fallback status page.
- **Port Conflict & Health Detection:** Real-time port listening checks in both the CLI and web dashboard.
- **Zero Heavy Dependencies:** Python standard library (`http.server`) and Bash core.

---

## Installation

Clone the repository and run the installer with root privileges:

```bash
git clone https://github.com/Pradeep-env/PortLabel.git
cd PortLabel
chmod +x install.sh uninstall.sh bin/portlabel
sudo ./install.sh
```

What install.sh Does:
1) Detects or installs the Caddy web server across common package managers (apt, pacman, dnf).

2) Disables default catch-all blocks and links portlabel.caddy into /etc/caddy/Caddyfile.

3) Installs the core engine, storage routines, and CLI executable to /usr/local/bin/portlabel.

4) Installs the custom offline fallback page to /etc/caddy/portlabel-fallback/fallback.html.

5) Starts the web dashboard background service (portlabel-web.service) on port 2999.

6) Automatically reserves and maps http://portlabel.local to the web dashboard.

---

## Usage

### nteractive CLI Menu

Run without arguments to launch the terminal dashboard:

```bash
sudo portlabel
```

```text
  ██████╗  ██████╗ ██████╗ ████████╗██╗      █████╗ ██████╗ ███████╗██╗     
  ██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔══██╗██╔════╝██║     
  ██████╔╝██║   ██║██████╔╝   ██║   ██║     ███████║██████╔╝█████╗  ██║     
  ██╔═══╝ ██║   ██║██╔══██╗   ██║   ██║     ██╔══██║██╔══██╗██╔══╝  ██║     
  ██║     ╚██████╔╝██║  ██║   ██║   ███████╗██║  ██║██████╔╝███████╗███████╗
  ╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝

  Local Domain Manager — assign .local names to your self-hosted services

  Main Menu
    1) Add       — create a new .local domain
    2) List      — view all registered domains
    3) Update    — change a service port
    4) Toggle    — enable or disable a domain
    5) Remove    — delete a domain
    6) Exit
```

## 2. Direct Subcommands

| Action | Command | Description |
|---|---|---|
| Add Mapping | `sudo portlabel add <name> <port>` | Create a new `.local` domain route |
| List Routes | `portlabel list` | View all registered domains, ports, and statuses |
| Update Port | `sudo portlabel update <name> <port>` | Change the target port for an existing domain |
| Toggle Status | `sudo portlabel toggle <name>` | Enable or disable a domain without deleting it |
| Remove | `sudo portlabel remove <name>` | Delete a domain mapping and purge the Caddy rule |
| Sync | `sudo portlabel sync` | Force rewrite `/etc/hosts` and Caddy configs |

### Examples

```bash
# Map n8n running on port 5678 to http://n8n.local
sudo portlabel add n8n 5678

# Map Nextcloud on port 8080 to http://nextcloud.local
sudo portlabel add nextcloud 8080

# Temporarily disable a route
sudo portlabel toggle nextcloud

# Check status
portlabel list
```

## Web Dashboard

Once installed, the web dashboard is live at:

- [http://portlabel.local](http://portlabel.local) (or direct IP: [http://localhost:2999](http://localhost:2999))

### Capabilities

- View live, real-time connectivity status (**Active / Offline**) for every port.
- Add new local mappings on the fly with an inline form.
- Activate or silence specific routes with single-click toggle switches.
- Confirm deletions and synchronize Caddy instantly.

## Project Architecture

```text
PortLabel/
├── bin/
│   └── portlabel             # CLI router & interactive menu entry point
├── core/
│   ├── engine.sh             # /etc/hosts & Caddy reload sync engine
│   └── storage.sh            # Flat-file database abstraction (/etc/portlabel)
├── web/
│   ├── app.py                # Zero-dependency Python HTTP API server
│   └── templates/
│       └── index.html        # Responsive dark-theme dashboard UI
├── assets/
│   └── fallback.html         # Custom 502/503 service-offline error page
├── install.sh                # End-to-end multi-distro installer & systemd setup
├── uninstall.sh              # Clean removal of configs, services, and symlinks
└── README.md
```

## Browser & DNS Troubleshooting

If you add a domain (e.g., `http://test.local`) and your browser shows a DNS resolution error or forces an unwanted HTTPS redirect:

### Clear Browser DNS Cache (Chrome / Brave / Edge)

Open `brave://net-internals/#dns` (or `chrome://net-internals/#dns`) and click **Clear host cache**.

### Clear HSTS Security Policies

If you visited the domain using HTTPS earlier, the browser may remember an HSTS policy.

Go to `chrome://net-internals/#hsts`, scroll to **Delete domain security policies**, enter `test.local`, and click **Delete**.

### Disable Secure DNS Interception

Go to **Browser Settings → Security** → disable **Use secure DNS** (or switch to OS default) so the browser respects `/etc/hosts`.

## Uninstallation

To cleanly remove PortLabel, all linked files, background services, and Caddy configurations:

```bash
sudo ./uninstall.sh
```