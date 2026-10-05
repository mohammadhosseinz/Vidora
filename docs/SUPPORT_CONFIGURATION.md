# Support configuration

Maintainer guide. For donation options, see [Support Vidora](SUPPORT.md).

`assets/support.json` stores public configuration. The bundled `donationUrl` points to the public support page in this repository. Update it if the repository moves or you publish a different HTTPS support page. The `wallets` list uses `currency`, `network`, `address`; never add recovery phrases, passwords, API keys or private keys.

Windows/Linux read an optional `support.json` next to the executable; restart after editing. macOS uses the bundled asset to preserve the app signature, so configure it before building/signing. The installer preserves an existing external configuration. Empty 0.1.4 settings and the stock USDT-only 0.1.5 settings migrate to the new bundled defaults; explicit custom lists remain unchanged. `{"disabled":true}` disables support.

The app only displays/copies an address or opens a public page. It never connects a wallet, sends funds, signs transactions or verifies payments. Memo/tag-based deposit destinations are not supported by the current wallet cards.

The Sponsor button uses `.github/FUNDING.yml` with a custom URL. It links to the public support page; payments do not go through GitHub Sponsors. The page and QR images must be on the default branch before the link is usable.

The receiving addresses were supplied by the project owner as exchange deposit addresses. Ownership, receipt, minimum deposit, address lifetime and exchange availability have not been independently verified. Confirm these with the receiving exchange before public distribution. QR images encode the address only, not the currency, network or payment amount.
