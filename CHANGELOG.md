# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **oath CLI** (`bin/oath`): Status visualization tool with subcommands — `status`, `audit`, `config`, `phase`, `demo`, `help`, `version`
- **oath demo**: Runs all commands with generated sample data for quick evaluation without real state files
- **32 oath-status tests**: Unit tests covering all CLI subcommands and display formatting

### Changed

- **settings.json simplified**: Only custom (non-default) values stored; defaults provided by code
- **Skill renamed**: `lam-orchestrate` → `orchestrate`
- **Test count**: 272 → 304 (241 unit + 63 integration)

### Fixed

- Phase 1 audit report: 16 Info-level items resolved (sourced annotations, variable naming, date compatibility notes)
- `oath phase` escape sequence rendered as literal `\033[1m` instead of bold text

## [0.1.0] - 2026-02-23

### Added

- **Trust Engine**: Domain-based trust score accumulation with asymmetric update (success/failure), time decay, and warmup after hibernation
- **Risk Category Mapper**: Classifies tool calls into low/medium/high/critical with compound command analysis (pipes, semicolons, &&)
- **Tool Profile Engine**: Phase-based access control (PLANNING/BUILDING/AUDITING) with structural enforcement via hooks
- **Audit Trail Logger**: JSONL audit logging with sensitive value masking, flock-protected writes
- **Model Router**: Recommends Opus/Sonnet/Haiku based on task complexity and trust level (Phase 1: record-only)
- **Session Bootstrap**: Automatic state initialization, v1-to-v2 migration, time decay on session start
- **Installer/Uninstaller**: Registers hooks in Claude Code settings.json with idempotent install and selective uninstall
- **272 tests**: 209 unit tests + 63 integration tests (bats-core)
- **Fail-safe design**: All errors default to block (never fail-open)
- **Atomic writes**: All state file updates use tmp+mv pattern (ADR-0003)

### Security

- Critical tool calls (curl/wget with URLs, API keys in commands) are always blocked
- Phase restrictions enforced structurally through hooks, not prompt instructions
- `initial_score > 0.5` rejected by configuration validation
- Direct trust score override forbidden by schema
