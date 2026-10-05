# Security

Do not disclose browser cookies, private video URLs, recovery phrases or API keys in public issues. Redact user-identifying local paths from logs.

For suspected vulnerabilities, use the repository hosting provider's private vulnerability reporting feature if enabled; otherwise contact the repository owner privately before disclosing exploit details. Do not post session secrets to demonstrate a problem.

The app runs local engine binaries and intentionally disables shell interpolation, user configuration files, plugins and remote components. Verify the runtime hashes and download replacement engines only from reviewed upstream sources. Full-device compromise, untrusted local executable replacements and force-kill/power-loss cleanup are outside the prototype's guarantees.
