# Security policy

## Supported version

Security fixes are applied to the latest release listed on the repository's
Releases page. Softer is a local research prototype, not a monitored service,
medical device, crisis service, or clinically validated product.

## Reporting a vulnerability

Use the repository owner's private contact channel or GitHub private
vulnerability reporting if it is available. Do not put personal wellbeing
information, profile data, encryption keys, or an exploitable proof of concept
in a public issue.

Include the affected version, macOS version, reproduction steps using synthetic
data, expected behavior, and observed behavior. For an immediate safety or
mental-health crisis, contact local emergency services or an appropriate crisis
resource; this repository is not an emergency channel.

## Security boundary

Softer stores saved profiles locally using AES-GCM with key material in the
macOS Keychain. It has no account, backend, analytics SDK, downloaded model, or
required runtime network service. See `docs/threat_model.md` and
`docs/safety_privacy.md` for the explicit boundary and known limitations.
