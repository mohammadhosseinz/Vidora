# Support Vidora

Support is optional; application features remain free. The dialog contains independent cards and copy buttons for these owner-provided receiving addresses:

| Currency | Network | Public address |
| --- | --- | --- |
| USDT | BSC / BEP20 only | `0x9a350193884756c2ff75e58847d8eff5441c27bf` |
| TRX | TRON — TRX only | `TBiSUJuPZfLAJ9VHiQuGpNVPzsEYixgp13` |

Do not send USDT to the TRX address or use Ethereum/TRON for the BSC address. Exchange screenshots also warn against smart-contract deposits for the USDT receiving page. Verify minimum deposit, address validity and deposit availability with the receiving exchange. No real donation/ownership verification has been performed by the developer.

`assets/support.json` stores public configuration. Set `donationUrl` to an actual HTTPS donation page if you create one. The `wallets` list uses `currency`, `network`, `address`; never add recovery phrases, passwords, API keys or private keys.

Windows/Linux read an optional `support.json` next to the executable; restart after editing. macOS uses the bundled asset to preserve the app signature, so configure it before building/signing. The installer preserves an existing external configuration. Empty 0.1.4 settings and the stock USDT-only 0.1.5 settings migrate to the new bundled defaults; explicit custom lists remain unchanged. `{"disabled":true}` disables support.

The app only displays/copies an address or opens a public page. It never connects a wallet, sends funds, signs transactions or verifies payments. Memo/tag-based deposit destinations are not supported by the current wallet cards.
