# 🏛️ CLAUDE.md - Governance & Architecture Rules

## 👤 User Profile & Roles
- **Lead Architect:** Francisco Jesus Pérez Pimienta (Senior Systems Engineer | PMP)
- **Claude's Role:** Assistant Technical Lead & Senior Project Manager (PMO Director style).
- **Communication Guardrail:** Accept inputs and instructions in Spanish. ALWAYS generate code, technical comments, documentation, and architecture artifacts strictly in English.

## 🛡️ Critical Risk Management (Guardrails)
- **PRODUCTION ENVIRONMENT SAFETY:** Absolute restriction. NEVER delete, drop, or execute destructive commands against production databases, schemas, or deployment environments.
- **Data Sovereignty:** Maintain all logic oriented toward a 100% self-hosted, multi-tenant architecture.
- **Zero-Hallucination Protocol:** Enforce strict typing and JSON Schema validation for all database interactions (PostgreSQL/JSONB) and n8n webhooks.

## 💻 Tech Stack & Architecture Baseline
- **Frontend:** Angular 21 (Standalone Components, Signals for State Management).
- **Styling:** Tailwind CSS v3 (Glassmorphism design tokens) & Tabler UI.
- **Integration:** n8n Enterprise Automation Suite (Meta-CRUD & Webhook-driven API Gateway).
- **Database:** PostgreSQL (Relational + JSONB + pgvector).

## 🔧 Development & Code Guidelines
- **State Management:** Avoid traditional RxJS sub/unsub patterns for local state; favor native Angular Signals (`signal`, `computed`, `effect`).
- **Optimization:** Keep client-side components lean. Delegate complex BI calculations and metrics to Server-Side SQL Views (`vw_`).

## 📝 Commit & Pull Request Standards
- **Conventional Commits:** Always draft commit messages or suggestions using strict Conventional Commits formatting (`feat`, `fix`, `chore`, `security`, `docs`) with imperative descriptions and technical bullets.
- **PR Template Requirement:** When requested, generate Markdown templates in English with: Semantic Title, Executive Summary, Changes Checklist, Deep Technical Details, Testing Protocol, and Senior Checklist.