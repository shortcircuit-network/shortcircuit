# Research Spike: MASQUE 0-RTT Transport for Nebula

## Status: PARKED (March 8, 2026)
This spike explored wrapping Nebula UDP traffic in QUIC (MASQUE) to achieve 0-RTT connection resumption and bypass ISP throttling.

## Technical Architecture
- **Lighthouse (DO SFO3):** MASQUE proxy server (built from quic-go) listening on UDP 443.
- **Client (macOS):** 'masque-bridge' binary listening on 127.0.0.1:4243.
- **Encapsulation:** Nebula -> Local UDP -> MASQUE Bridge -> QUIC/UDP 443 -> Lighthouse.

## Artifacts Staged
- **Source:** 'scripts/masque-bridge.go' (Custom minimal bridge).
- **Binaries:** 'bin/masque-bridge' (Linux AMD64), 'files/nebula/masque-client-*' (macOS AMD64/ARM64).
- **Lighthouse:** Static 'masque-server' binary at '/usr/local/bin/' on the DO SFO3 droplet.

## Findings
- **Discovery:** Standard Nebula P2P already identifies local network paths (5ms latency) without MASQUE assistance.
- **Latency:** Trans-Pacific pings stabilized at 103.8ms with zero jitter (0.23ms) using raw Nebula.
- **Blockers:** macOS background process management (launchd/brew) and Go 1.25 toolchain requirements made automated deployment high-friction for PoC stage.

## Revisit Conditions
Revisit this spike if trans-Pacific DRBD traffic experiences "Handshake Storms" or if ISPs begin throttling high-volume UDP 4242 traffic during Bitcoin/Doge archival syncs.

## Addendum: TCP vs UDP Nuance (March 8, 2026)
- **Performance:** TCP transport hit is minimal (~2-5ms jitter) because 103ms is propagation-bound.
- **Compatibility:** TCP/443 is preferred for roaming personal devices to ensure ISP traversal.
- **Constraint:** Head-of-line blocking is acceptable for control planes but disqualified for production storage (K3s).
