#!/usr/bin/env bash
set -Eeuo pipefail

TEST_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
canonical="${TEST_REPO_ROOT}/skills/deploy-prividium"

for discovered in \
  "${TEST_REPO_ROOT}/.agents/skills/deploy-prividium" \
  "${TEST_REPO_ROOT}/.claude/skills/deploy-prividium"; do
  [[ -L "$discovered" ]]
  [[ "$(cd "$discovered" && pwd -P)" == "$canonical" ]]
done

grep -Fxq 'name: deploy-prividium' "${canonical}/SKILL.md"
grep -Fq '$deploy-prividium' "${canonical}/SKILL.md"
grep -Fq '/deploy-prividium' "${canonical}/SKILL.md"
grep -Fq 'allow_implicit_invocation: false' "${canonical}/agents/openai.yaml"

printf 'Agent skill discovery validation passed\n'
