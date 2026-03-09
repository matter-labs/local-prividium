# Webhook Service Account Seed Data

This directory contains seed data for local webhook and service-account authentication for local development.

## Overview

The `seed-service-account.sql` script seeds the database with a single local service account that is used to authenticate the webhook service.

## Seeded Service Account

| Field | Value |
| ----- | ----- |
| Service ID | `svc_seed_local_000001` |
| Name | `Local Seed Service` |
| Public Address | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| Private Key (Local Dev Only) | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |

## Notes

- The script is for local development only. The private key is a public test key
- The script is idempotent for repeated runs of the same seeded key (`ON CONFLICT (public_key) DO NOTHING`)
- The script assumes migrations have already been run and the `services` table exists
