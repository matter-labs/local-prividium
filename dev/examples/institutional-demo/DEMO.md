# Intraday Repo Demo

Short-term collateralized lending market built on Prividium. Lenders create offers specifying loan terms (amount,
collateral, duration, fee). Borrowers accept offers by depositing collateral and receiving funds. Loans must be repaid
before the deadline (plus a 2-minute grace period) or lenders can claim the collateral.

## Start

```bash
docker compose --profile institutional-demo up -d
```

Wait for all services to start — init containers (deploy, seed) will run automatically in order.

> Chain data is not persisted between restarts. To run again, first reset the environment:
>
> ```bash
> docker compose --profile institutional-demo down -v
> ```

## Demo

### Prerequisites

- Two separate browsers or Chrome [profiles](https://support.google.com/chrome/answer/2364824) to simulate two users.
- [MetaMask](https://chromewebstore.google.com/detail/metamask/nkbihfbeogaeaoehlefnkodbefgpgknn) wallet extension
  installed in both browsers/profiles.

### Steps

1. **Setup MetaMask with demo accounts:**
   - **Browser 1 (user1):**
     - MetaMask → Account dropdown → `Add Wallet` → `Import an account`
     - Private key: `0x93dd39ca8b2666c9bf1cee643f18df4fef6ca96668302978675af1d717459706`
   - **Browser 2 (user2):**
     - MetaMask → Account dropdown → `Add Wallet` → `Import an account`
     - Private key: `0x6a657d9f98808f0d551411319b851b35e9ef6fca68f38ccc9b92871ec61e1efb`

2. **Login to Prividium User Panel:**
   - **Browser 1:** Open http://localhost:3001 → `Sign in with Keycloak` → `user1@local.dev` / `password`
   - **Browser 2:** Open http://localhost:3001 → `Sign in with Keycloak` → `user2@local.dev` / `password`

3. **Add Prividium chain to MetaMask:**
   - Go to http://localhost:3001/wallets → `Add Network to Wallet` → Confirm in MetaMask

4. **Login to the Intraday Repo App:**
   - Open http://localhost:3500 in both browsers
   - Login with Prividium (user1 in Browser 1, user2 in Browser 2)
   - Connect the corresponding MetaMask account

5. **Start using the app!**
   - Create lending offers, accept them, repay loans, and claim collateral if needed.

## Links

| Service              | URL                   |
| -------------------- | --------------------- |
| Intraday Repo App    | http://localhost:3500 |
| Prividium User Panel | http://localhost:3001 |
| Prividium Admin      | http://localhost:3000 |
| Block Explorer       | http://localhost:3010 |
| Keycloak             | http://localhost:5080 |

## Permissions

1. Login to Admin Panel (`admin@local.dev` / `password`) at http://localhost:3000
   - _Use a separate browser/profile or logout from demo user first via Prividium User Panel._
2. Go to `Contracts` page to view and manage permissions.
