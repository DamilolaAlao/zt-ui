# Security Policy

## Reporting A Vulnerability

Please do not open a public issue for security-sensitive problems.

Preferred path:

- Use the repository host's private vulnerability reporting feature when it is available.

Fallback path:

- Open a minimal public issue requesting a private reporting channel, and do not include exploit details, secrets, payloads, or reproduction steps there.

When you do reach a private channel, include:

- a description of the problem,
- reproduction steps or proof of concept,
- the affected files or runtime surface,
- and any suggested mitigation if you have one.

## Response Expectations

- We will acknowledge receipt as quickly as practical.
- We will assess impact and reproduce the issue.
- We will coordinate a fix before public disclosure when appropriate.

## Scope

Security-sensitive areas currently include:

- the WASM export surface,
- browser-side decoding of command, text, and point buffers,
- input forwarding and event handling,
- future native or desktop host integrations.

## Maintainer Note

Before announcing a broad public release, configure a real private reporting destination on the repository host and update this file if project-specific contact details become available.
