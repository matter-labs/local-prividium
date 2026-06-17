# Service Auth Seed Data

This directory contains seed data for local service authentication.

## Overview

The `seed-webhook-service.sql` script seeds the database with the local webhook service account used during development.

## Seeded Service

The seed script creates one service in the `services` table:

| Field       | Value                                                                 |
| ----------- | --------------------------------------------------------------------- |
| ID          | `svc_local_webhook_001`                                               |
| Name        | `Local Webhook Service`                                               |
| Public Key  | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`                          |
| Description | `Seeded local development service account for zksync-webhook-service` |

## Public Key Source

This public key is derived from the local signer key configured for the webhook container in `docker-compose-deps.yaml`.

## Notes

- The script is idempotent. It uses `ON CONFLICT (public_key) DO UPDATE` to keep one canonical local webhook service.
- The script assumes migrations have already run and the `services` table exists.
