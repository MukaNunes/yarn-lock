#!/usr/bin/env bash
# Resolve conflitos de merge restritos a package.json / yarn.lock.
#
# Estratégia:
#   - package.json: mantém a versão do branch que está sendo mergeado (HEAD/"ours"
#     no ponto em que este script roda), descartando apenas os trechos que
#     conflitam com o branch base.
#   - yarn.lock: nunca é "merge" de texto. É sempre regenerado do zero via
#     `yarn install`, a partir do package.json já resolvido, para garantir que
#     o lockfile final seja consistente (evita misturar resoluções de dois
#     lockfiles diferentes).
#
# Se QUALQUER outro arquivo além de package.json/yarn.lock estiver em conflito,
# o script aborta o merge e sai com erro, sem tocar em nada — o conflito deve
# ser resolvido manualmente.
#
# Uso: resolve-lockfile-conflict.sh <base-ref>
# Pré-condição: HEAD já está no branch da PR.

set -euo pipefail

BASE_REF="${1:?uso: resolve-lockfile-conflict.sh <base-ref>}"
ALLOWED_FILES=("package.json" "yarn.lock")

is_allowed() {
  local f="$1"
  for allowed in "${ALLOWED_FILES[@]}"; do
    [[ "$f" == "$allowed" ]] && return 0
  done
  return 1
}

if git merge --no-commit --no-ff "$BASE_REF"; then
  echo "Sem conflitos com $BASE_REF. Nada a fazer."
  exit 0
fi

mapfile -t CONFLICTED < <(git diff --name-only --diff-filter=U)

if [[ ${#CONFLICTED[@]} -eq 0 ]]; then
  echo "git merge falhou sem listar arquivos em conflito (estado inesperado)." >&2
  git merge --abort
  exit 2
fi

for f in "${CONFLICTED[@]}"; do
  if ! is_allowed "$f"; then
    echo "Conflito fora do escopo permitido: $f"
    echo "Abortando — requer resolução manual."
    git merge --abort
    exit 1
  fi
done

echo "Conflitos apenas em: ${CONFLICTED[*]} — resolvendo automaticamente."

for f in "${CONFLICTED[@]}"; do
  if [[ "$f" == "package.json" ]]; then
    git checkout --ours -- package.json
    git add package.json
  fi
done

# yarn.lock é sempre regenerado (mesmo que só ele tenha conflitado), garantindo
# consistência com o package.json final.
rm -f yarn.lock
corepack enable
yarn install
git add yarn.lock

git commit -m "chore: resolve conflitos de package.json/yarn.lock com ${BASE_REF#origin/}"

echo "Conflitos resolvidos e commitados."
