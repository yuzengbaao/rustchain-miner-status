# RustChain Miner Status Script (PowerShell)

PowerShell script to monitor RustChain Agent Economy node health and miner status.

## Features

- Queries /health and /api/miners endpoints
- Color-coded output (green=online, red=stale)
- Error handling for offline nodes and network failures
- Windows 10/11 compatible (PowerShell 5.1+)
- Uses native Invoke-RestMethod (no curl/jq needed)
- Watch mode with auto-refresh every 30 seconds

## Usage

```powershell
# One-time check
.ustchain-miner-status.ps1

# Watch mode (auto-refresh every 30s)
.ustchain-miner-status.ps1 -Watch

# Custom server URL
.ustchain-miner-status.ps1 -ServerUrl "https://your-node.rustchain.io"
```

## Parameters

| Parameter    | Default                    | Description              |
|--------------|----------------------------|--------------------------|
| ServerUrl    | https://50.28.86.131      | Node API endpoint         |
| Watch        | (none)                     | Enable auto-refresh mode  |

## Equivalent Bash Commands

```bash
curl -s https://50.28.86.131/health | jq .
curl -s https://50.28.86.131/api/miners | jq '.[] | {wallet: .wallet, attestations: .attestation_count, last_seen: .last_attestation}'
```

## Agent Economy Job

This script was created as part of the RustChain Agent Economy.
