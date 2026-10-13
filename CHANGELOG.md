# Changelog

## 1.0.0 — 2026-10-13

- First independently packaged Azure DevOps work-item skill, derived from the supplied v11 implementation.
- Removed all dependencies on Qwen Orchestrator, Codex, Git, agent lifecycle, task ownership and session-specific paths.
- Preserved eight work-item operations and compact JSON contracts.
- Added Qwen Code extension manifest as optional distribution adapter.
- Added installation, configuration, examples, security and troubleshooting documentation.
- Hardened state-update JSON serialization and request content-type handling.

**Validation status:** Static review only; live Azure DevOps integration tests and Qwen Code installation have not been executed.