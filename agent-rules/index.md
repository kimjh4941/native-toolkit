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
- Implement feature (実装・テスト・確認): ./workflows/implement-feature/workflow.md
- Design sample app (サンプルアプリ計画作成): ./workflows/design-sample-app/workflow.md
- Implement sample app (サンプルアプリ実装): ./workflows/implement-sample-app/workflow.md
- Write manual (マニュアル作成): ./workflows/write-manual/workflow.md
- Verify manual (マニュアル整合検査): ./workflows/verify-manual/workflow.md
- Release (リリース): ./workflows/release/workflow.md
- Review implementation feature (機能実装レビュー): ./workflows/review-implementation-feature/workflow.md
- Review implementation sample app (サンプルアプリ実装レビュー): ./workflows/review-implementation-sample-app/workflow.md
- Review and refine (企画書・設計書レビュー): ./workflows/review-and-refine/workflow.md
- Commit message (コミットメッセージ生成): ./workflows/commit-msg/workflow.md

## Design documents

- Layout of `artifact/` (<os> / topics) and the topic list: ../artifact/README.md
- The workflows above write to `artifact/<os>/<feature>/<kind>/`, where `<os>` is `android`, `ios`, `macos` or `windows`. A step that looks for candidates before the OS is chosen searches `artifact/*/<feature>/<kind>/`. Documents under `artifact/topics/` are written by hand.

## Common policy

- For platform-specific implementation, apply the corresponding platform rule file.
- Write comment text in English.
- Write user-facing message text in English.
- When adding rules, update this index and place details in each rule file.
- Commit only through the commit-msg workflow (./workflows/commit-msg/workflow.md). Do not run `git commit` directly.

## Working with the user

- When the user has to decide, name the option you recommend and why in one line. Do not present a neutral list of choices.
- Do not offer to stop or pause at a milestone. Finish the step, report the result, and go on to the next one; the user says when to stop. Still ask before anything hard to reverse or outward-facing (commits, pushes, PRs, releases, messages to others).
- Choose the number of subagents or reviewers yourself from the work (distinct viewpoints, not volume), and state the choice in one line.
