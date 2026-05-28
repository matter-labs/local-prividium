# Wallet Auth Seed Data

This directory contains seed data for crypto-native authentication testing.

## Overview

The `seed-wallet-auth.sql` script seeds the database with test users for development and E2E testing.

## Test Users

The seed script creates users with their associated wallets. All wallet addresses are derived from the E2E test mnemonic
(`test test test test test test test test test test test junk`).

### Crypto-native Users (accounts #0-#2)

| User    | Display Name | Wallet Address                               | Roles |
| ------- | ------------ | -------------------------------------------- | ----- |
| Admin   | Admin User   | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | admin |
| Regular | Regular User | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | user  |
| Test    | Test User    | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | user  |

### OIDC Users (accounts #3-#5)

These match the Keycloak users in `dev/keycloak/realm-export.json`:

| User    | Email             | OIDC Sub                               | Wallet Address                               | Roles |
| ------- | ----------------- | -------------------------------------- | -------------------------------------------- | ----- |
| Admin   | `admin@local.dev` | `00000000-0000-0000-0000-000000000001` | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | admin |
| Regular | `user@local.dev`  | `00000000-0000-0000-0000-000000000002` | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | user  |
| Test    | `test@local.dev`  | `00000000-0000-0000-0000-000000000003` | `0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc` | user  |

## Notes

- The script is idempotent - it uses `ON CONFLICT DO NOTHING` clauses so it can be run multiple times safely
- The script assumes migrations have already been run and tables exist
