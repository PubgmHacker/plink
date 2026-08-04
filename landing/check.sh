#!/usr/bin/env bash
# Разовая проверка: какой из OpenAI-совместимых провайдеров принимает ключ.
#
# Ключ здесь раньше лежал прямо в тексте и попал в историю публичного репозитория
# (коммит 774887b). Тот ключ нужно считать скомпрометированным и отозвать у
# провайдера — удаление из файла его не отзывает. Теперь читаем из окружения:
#   LLM_KEY=sk-... ./check.sh
set -euo pipefail

KEY="${LLM_KEY:-}"
if [ -z "$KEY" ]; then
  echo "Задайте ключ через окружение: LLM_KEY=sk-... $0" >&2
  exit 1
fi

URLS=(
  "https://api.openai.com/v1"
  "https://api.deepseek.com/v1"
  "https://api.groq.com/openai/v1"
  "https://api.together.xyz/v1"
  "https://api.mistral.ai/v1"
  "https://api.moonshot.cn/v1"
  "https://openrouter.ai/api/v1"
  "https://api.x.ai/v1"
  "https://api.fireworks.ai/inference/v1"
  "https://api.siliconflow.cn/v1"
  "https://api.cerebras.ai/v1"
  "https://api.novita.ai/v3/openai"
)

for u in "${URLS[@]}"; do
  code=$(curl -s -o /tmp/out.json -w "%{http_code}" "$u/models" -H "Authorization: Bearer $KEY")
  echo "$code  $u"
  if [ "$code" = "200" ]; then
    echo "    ✅ РАБОТАЕТ"
    head -c 400 /tmp/out.json
    echo
  fi
done
