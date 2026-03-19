# 🗺️ PortLabel

Portlabel is a lightweight CLI tool for Linux that lets you assign human-readable `.local` domain names to your self-hosted services — no more remembering IP addresses and port numbers.

---

## The Problem

You self-host n8n, Nextcloud, Vaultwarden, Jellyfin.  
You access them as `192.168.1.105:8080`, `192.168.1.105:8443`, `192.168.1.105:3012`.  
Every time. From memory.

Portlabel fixes that.

---

## What Portlabel Does

- Maps a name like `n8n` to a port like `8080`
- Gives it a clean `.local` address: `n8n.local`
- Writes the entry to `/etc/hosts` automatically
- Configures Caddy as a reverse proxy so the port stays hidden
- Enables TLS on every domain automatically via Caddy's internal CA
- Shows a branded offline page when a service isn't running
- Lets you toggle domains on and off without deleting them
- Manages everything through a simple interactive CLI menu

---

## What Portlabel Is and Isn't

Portlabel **is**:
- A local domain manager for self-hosted services
- A CLI-first tool built for Linux
- A hosts file manager with safe, scoped edits
- A Caddy reverse proxy configurator for clean `.local` URLs
- Lightweight — no dependencies beyond bash and Caddy

Portlabel **is not**:
- A public DNS tool
- A network-wide DNS resolver (use Pi-hole for that)
- A replacement for Caddy (it configures Caddy, not replaces it)
- A cloud tool — everything stays on your machine

---

## How It Works

When you add a domain, Portlabel does three things:

**1. Writes to `/etc/hosts`**

```
# portlabel-start — do not edit manually
127.0.0.1 n8n.local
127.0.0.1 nextcloud.local
# portlabel-end
```

Your OS checks this file before asking any DNS server, so `n8n.local` resolves locally instantly.

**2. Configures Caddy**

Since `/etc/hosts` maps names to IPs but not ports, Portlabel writes a Caddy config block that routes `n8n.local` → `localhost:8080`. TLS is enabled on every domain automatically using Caddy's internal certificate authority.

```
n8n.local {
    tls internal
    reverse_proxy localhost:8080
    handle_errors 502 503 {
        root * /etc/caddy/portlabel-fallback
        rewrite * /fallback.html
        file_server
    }
}
```

**3. Shows a fallback page when a service is offline**

If nothing is running on the assigned port, Portlabel serves a branded offline page instead of a blank browser error. Start your service and the page is replaced automatically.

**Your data stays in `~/.portlabel/domains.conf`**

```
n8n|8080|enabled
nextcloud|8443|enabled
vaultwarden|3012|disabled
```

This is the source of truth. The hosts file and Caddy config are outputs generated from it.

---

## Installation

```bash
git clone https://github.com/Pradeep-env/PortLabel.git
cd PortLabel
chmod +x install.sh
sudo ./install.sh
```

The installer handles everything:
- Installs Caddy if not already present
- Disables Caddy's default catch-all page
- Sets up the Portlabel Caddy config file
- Installs the fallback offline page
- Makes `portlabel` available as a system command

After install, run:

```bash
sudo portlabel
```

**Requirements:**
- Linux (Debian/Ubuntu/Arch — any distro)
- Bash 4.0+
- sudo access (required for `/etc/hosts` writes)

Caddy is installed automatically by the installer.

---

## Usage

Run the interactive menu:

```bash
sudo portlabel
```

```
Portlabel - Local Domain Manager
================================
1) Create
2) List
3) Modify
4) Delete
5) Toggle (enable / disable)
6) Exit

Select an option:
```

### Create

Adds a new `.local` domain and writes the entry immediately.

```
Enter service name: n8n
Enter port: 8080

✔ Created: n8n.local → localhost:8080
```

### List

Shows all registered domains and their current state.

```
Service        Port    Address           Status
─────────────────────────────────────────────────
n8n            8080    n8n.local         enabled
nextcloud      8443    nextcloud.local   enabled
vaultwarden    3012    vaultwarden.local disabled
```

### Modify

Updates the port for an existing domain.

```
Select domain to modify: n8n
New port [current: 8080]: 9090

✔ Updated: n8n.local → localhost:9090
```

### Delete

Removes a domain entry from hosts file, Caddy config, and the conf file.

```
Select domain to delete: vaultwarden

✔ Removed: vaultwarden.local
```

### Toggle

Enables or disables a domain without deleting it.
Disabling comments out the hosts entry and removes the Caddy route.

```
Select domain to toggle: nextcloud

✔ nextcloud.local is now disabled
```

Re-enable it any time by toggling again.

---

## TLS and the Browser Warning

Portlabel uses Caddy's internal TLS — a self-signed certificate issued by a local CA that Caddy manages automatically. On your first visit to any `.local` domain, Chrome will show a "Your connection is not private" warning.

Click **Advanced → Proceed to [domain].local** once. The warning won't appear again for that domain.

This is expected behavior for local self-signed certificates — your traffic is still encrypted.

**If Chrome isn't resolving `.local` domains at all**, disable its async DNS resolver:

```
chrome://flags/#enable-async-dns  →  set to Disabled
```

---

## Why `.local`?

`.local` is a reserved suffix for local network use. It will never conflict with a real public domain, and your OS handles it without any extra configuration.

Avoid using real domain names (like `n8n.com`) as local aliases — it would break your actual internet access to that site.

---

## Project Structure

```
portlabel/
├── portlabel.sh         # Main script
├── devmode.sh           # Developer mode — port reserve & service manager
├── install.sh           # Installs Portlabel and sets up Caddy
├── uninstall.sh         # Removes Portlabel and cleans up everything
├── fallback.html        # Offline page served when a service isn't running
├── README.md
└── docs/
    └── how-it-works.md  # Technical deep dive
```

---

## Roadmap

- [x] CLI interactive menu
- [x] Create, list, modify, delete, toggle
- [x] Hosts file scoped block management
- [x] Caddy reverse proxy auto-configuration
- [x] TLS on every domain via Caddy internal CA
- [x] Branded offline fallback page
- [x] Developer mode — port reserve, service generator, CORS reference
- [ ] Nginx support
- [ ] Import existing services from a config file
- [ ] GUI via Flask + Jinja (planned)

---

## Developer Mode

Portlabel includes a separate companion script — `devmode.sh` — built specifically for developers running multiple local projects simultaneously.

### The Problem It Solves

When you're developing a React frontend and a FastAPI backend at the same time, you're dealing with port conflicts, CORS configuration headaches, and the constant mental overhead of remembering which port belongs to which project. Devmode eliminates all of that.

### How It Works

Run it directly — it is not installed as a system command by design:

```bash
sudo ./devmode.sh
```

```
Portlabel Dev — Developer Mode
================================
1) Create    — reserve a port and register a dev project
2) List      — view all dev projects
3) Toggle    — enable or disable a project
4) Services  — start / stop / restart / logs
5) CORS info — view domain, port and CORS snippets
6) Delete    — remove a project and release its port
7) Exit
```

### Port Reservation

Devmode auto-assigns ports from the reserved range **30000–39999**. You never choose or remember a port number — you just name your project and get back a clean `.local` domain.

```
Project name : myapp
Stack        : React / Vite
Project path : /home/user/projects/myapp

✔ Reserved port: 30001
✔ Created: myapp.local → localhost:30001
```

This range is chosen deliberately — no self-hosted tool uses ports this high, so conflicts are impossible.

### Service File Generator

Devmode generates a systemd service file for your project so it starts automatically and can be managed like any system service. Supported stacks:

| Stack | Start command in service |
|---|---|
| React / Vite | `npm run dev -- --port PORT` |
| Next.js | `PORT=PORT npm run dev` |
| Flask | `python -m flask run --port PORT` |
| FastAPI | `uvicorn main:app --port PORT --reload` |
| Spring Boot | `java -jar app.jar --server.port=PORT` |
| Static HTML | `caddy file-server --listen :PORT` |

The service file is placed at `/etc/systemd/system/portlabel-name.service` and enabled on startup automatically.

Manage it anytime through the Services menu or directly:

```bash
sudo systemctl start   portlabel-myapp
sudo systemctl stop    portlabel-myapp
sudo systemctl restart portlabel-myapp
sudo journalctl -u portlabel-myapp -f
```

### Clean CORS — No Ports in Origins

Because every project gets a `.local` domain with no port exposed, your CORS config becomes simple and clean:

```python
# FastAPI
allow_origins=["https://myapp.local"]
```

```javascript
// Express
cors({ origin: "https://myapp.local" })
```

```java
// Spring Boot
@CrossOrigin(origins = "https://myapp.local")
```

No more `allow: *` as a workaround. No ports in origins. Works exactly like a production CORS config.

### API Calls from Frontend

Your frontend calls the backend by domain, no port needed:

```javascript
fetch("https://myapi.local/login")
fetch("https://myapi.local/users")
```

### Developer Tab on the Fallback Page

When a dev service is offline, the fallback page shows a **Developer** tab with:
- The systemctl command to start that specific service
- The journalctl command to tail its logs
- CORS snippets for FastAPI, Express, and Spring Boot — pre-filled with the actual domain
- The API base URL ready to copy

### Data Storage

Dev projects are stored in `~/.portlabel/dev.conf` alongside the main `domains.conf`. Dev domains also appear in the main Portlabel list with a `[dev]` tag so you always have one place to see all registered ports.

---

## Contributing

Contributions are welcome.

Guidelines:
- Shell script only for the core tool — keep it dependency-free
- Hosts file edits must stay scoped to the `portlabel-start / portlabel-end` block
- Caddy config changes must not break the fallback page behavior
- Devmode changes must not affect the main portlabel.sh behavior
- Open an issue before major changes

---

## Development Philosophy

- One tool, one job
- No dependencies beyond bash and Caddy
- Honest edits — the tool owns only what it creates
- Reversible by design — nothing Portlabel does can't be undone
- CLI first, GUI later

---

## Why Not Just Edit `/etc/hosts` Manually?

You can. But you'll also need to manually configure Caddy, write TLS blocks, set up fallback error pages, remember which ports map to which names, and carefully avoid breaking other entries. Portlabel handles all of that and gives you a single command to manage it.

---

## License

MIT
