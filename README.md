# PAN-OS Config Backup (XML API) — Bash Script

This script exports a full Palo Alto Networks PAN-OS configuration backup (`running-config.xml`) via the PAN-OS XML API and stores it with a timestamped filename. It also performs retention cleanup (delete backups older than a defined age) while keeping at least the last **N** backups.

## Features

- Export **running configuration** via PAN-OS XML API
- Timestamped filenames (sortable): `YYYY-MM-DD_HH-MM-SS_running-config.xml`
- Retention cleanup by age (**minutes / hours / days**)
- Keep at least the last **N** backups (`KEEP_LAST`)
- Safe cleanup: retention runs **only if export succeeded**
- Pretty shell output with optional colors (auto/on/off)

## Requirements

- `bash` (macOS default bash 3.2 is supported)
- `curl`
- `stat` (built-in on macOS/Linux)
- Network access to the firewall **management interface** (HTTPS/443)
- PAN-OS XML API enabled for your admin / management profile

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-user>/<your-repo>.git
   cd <your-repo>
   ```

2. Create an API key file (single line, no XML tags):
   ```bash
   echo "YOUR_API_KEY" > key_192.168.0.11.key
   chmod 600 key_192.168.0.11.key
   ```

   **Important:** Never commit your API key file.

3. Make the script executable:
   ```bash
   chmod +x config_export.sh
   ```

## Configuration

Edit these variables at the top of `config_export.sh`:

```bash
FW="https://192.168.0.11"
KEY_FILE="./key_192.168.0.11.key"
BACKUP_DIR="./backups"

RETENTION_UNIT="days"     # minutes|hours|days
RETENTION_VALUE=14
KEEP_LAST=10              # keep at least last N backups

COLOR="auto"              # auto|on|off  (NO_COLOR=1 disables)
```

### Color output

- `COLOR="auto"`: colors only when output is a terminal (TTY)
- `COLOR="on"`: force colors
- `COLOR="off"`: disable colors
- `NO_COLOR=1`: disables colors regardless of `COLOR`

Example:
```bash
NO_COLOR=1 ./config_export.sh
```

## Usage

Run the script:
```bash
./config_export.sh
```

Example output:
```
✅ SAVED   ./backups/2026-01-29_10-05-01_running-config.xml
ℹ️  INFO    OS=Darwin | retention=14 days | keep_last=10 | color=auto
🧹 DELETED 2 file(s)
  - ./backups/2026-01-10_09-00-00_running-config.xml
  - ./backups/2026-01-10_09-05-00_running-config.xml
```

## Retention behavior

A file is deleted only if:

1. It matches the pattern: `*_running-config.xml`
2. It is **older** than `RETENTION_VALUE` in `RETENTION_UNIT`
3. It is **not** within the newest `KEEP_LAST` backups
4. The current export completed successfully (no API error response)

## Security notes

- **Do not commit** API keys, passwords, or configuration backups.
- Consider using a dedicated read-only admin role/profile for API access if possible.
- Store secrets using a secrets manager (recommended) rather than plain files.
- If a secret ever leaks into Git history, rotate it immediately.

## Troubleshooting

### Saved file contains `<response status="error">`

The API returned an error response. Typical causes:

- XML API not allowed in the admin profile
- Wrong management IP / you are hitting a data interface
- Network ACLs or management interface restrictions
- Invalid/expired API key

Inspect the output file:
```bash
head -n 20 ./backups/<file>.xml
```

### API key generation (optional)

You can generate a key via XML API:
```bash
curl -skG "https://FIREWALL-MGMT-IP/api/"   --data-urlencode "type=keygen"   --data-urlencode "user=admin"   --data-urlencode "password=YOUR_PASSWORD"
```

## License
Copyright 2026 Alexander Graefe

Licensed under the **Apache License, Version 2.0**.

See the `LICENSE` file for details.

---

**Disclaimer:** This project is not affiliated with Palo Alto Networks.
