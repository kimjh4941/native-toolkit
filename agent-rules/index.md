# AI Agent Shared Rules

This file is the shared entry point for all AI agents used in this repository.
All implementation rules are managed in this folder.

## Index

- Common implementation policy (Clean Architecture / TDD / Bridge): ./coding-rules/common.md
- Android coding rules: ./coding-rules/android.md
- iOS coding rules (Swift + Objective-C): ./coding-rules/ios.md

## Workflows

Canonical workflow definitions shared across all agents (Copilot, Claude, Codex).
Agent-specific wrappers in `.github/skills/` reference these files.

- Research a feature (企画書作成): ./workflows/research-feature/workflow.md
- Design implementation (実装設計書作成): ./workflows/design-implementation-feature/workflow.md
- Implement feature (実装・テスト・確認): ./workflows/implement-feature/workflow.md
- Design sample app (サンプルアプリ計画作成): ./workflows/design-sample-app/workflow.md
- Implement sample app (サンプルアプリ実装): ./workflows/implement-sample-app/workflow.md
- Write manual (マニュアル作成): ./workflows/write-manual/workflow.md
- Release (リリース): ./workflows/release/workflow.md
- Review implementation feature (機能実装レビュー): ./workflows/review-implementation-feature/workflow.md
- Review implementation sample app (サンプルアプリ実装レビュー): ./workflows/review-implementation-sample-app/workflow.md
- Review and refine (企画書・設計書レビュー): ./workflows/review-and-refine/workflow.md
- Commit message (コミットメッセージ生成): ./workflows/commit-msg/workflow.md

## Common policy

- For platform-specific implementation, apply the corresponding platform rule file.
- Write comment text in English.
- Write user-facing message text in English.
- When adding rules, update this index and place details in each rule file.
