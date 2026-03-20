#!/bin/bash

# --- ЦВЕТА ДЛЯ КОНСОЛИ ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- ЗАГРУЗКА ПЕРЕМЕННЫХ ---
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}❌ Ошибка: Файл .env не найден!${NC}"
    exit 1
fi

API_KEY="$OPENROUTER_API_KEY"
MODEL="${MODEL_NAME:-z-ai/glm-5-turbo}"
URL="https://openrouter.ai/api/v1/chat/completions"
TASKS_DIR="./tasks"

# --- ФУНКЦИЯ ВЫБОРА ЗАДАЧИ ---
select_task() {
    echo -e "${YELLOW}📂 Доступные файлы с задачами:${NC}"
    
    # Массив для хранения имен файлов
    files=()
    i=1
    
    # Сканируем папку tasks
    if [ ! -d "$TASKS_DIR" ]; then
        echo -e "${RED}❌ Папка $TASKS_DIR не найдена! Создайте её и добавьте туда файлы .txt${NC}"
        exit 1
    fi

    # Читаем файлы .txt
    for file in "$TASKS_DIR"/*.txt; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            files+=("$filename")
            echo "   $i) $filename"
            ((i++))
        fi
    done

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}❌ В папке $TASKS_DIR нет файлов .txt${NC}"
        exit 1
    fi

    echo ""
    echo -n "Выберите номер задачи (1-${#files[@]}): "
    read choice

    # Проверка ввода
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#files[@]}" ]; then
        echo -e "${RED}❌ Неверный номер.${NC}"
        exit 1
    fi

    # Читаем содержимое выбранного файла
    selected_file="${TASKS_DIR}/${files[$((choice-1))]}"
    # Пробуем конвертировать из UTF-8 в WINDOWS-1251. Если iconv нет, пробуем cat.
    if command -v iconv &> /dev/null; then
        TASK=$(iconv -f UTF-8 -t WINDOWS-1251 "$selected_file" 2>/dev/null || cat "$selected_file")
    else
        TASK=$(cat "$selected_file")
    fi
    
    echo -e "${GREEN}✅ Загружена задача из: ${files[$((choice-1))]}${NC}"
    echo "----------------------------------------"
    echo "Текст задачи: $TASK"
    echo "----------------------------------------"
    echo ""
}

# --- ФУНКЦИЯ ОТПРАВКИ ЗАПРОСА ---
send_request() {
    local method_name=$1
    local prompt_content=$2

    echo -e "${YELLOW}▶️  ЗАПУСК: $method_name${NC}"
    
    # Формируем JSON. Внимание: если в задаче есть двойные кавычки, их нужно экранировать.
    # Для простоты заменяем двойные кавычки на одинарные внутри текста задачи перед отправкой,
    # либо используем более надежный способ через printf, но для базовых задач сойдет так:
    # Экранирование специальных символов для JSON
    escaped_content=$(echo "$prompt_content" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    JSON_BODY="{\"model\": \"$MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"$escaped_content\"}]}"

    RESPONSE=$(curl -s -X POST "$URL" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -H "HTTP-Referer: http://localhost" \
      -d "$JSON_BODY")

    # Извлечение ответа (попробуем найти поле content)
    # Если установлен jq, лучше: CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
    CONTENT=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\n/\n/g' | sed 's/\\"/"/g')

    if [ -z "$CONTENT" ]; then
        echo -e "${RED}⚠️ Не удалось получить ответ. Проверьте ключ или формат JSON.${NC}"
        echo "Raw response: $RESPONSE"
    else
        echo "$CONTENT"
    fi
    
    # Статистика токенов
    tokens=$(echo "$RESPONSE" | grep -o '"total_tokens":[0-9]*' | cut -d':' -f2)
    if [ -n "$tokens" ]; then
        echo -e "${GREEN}💰 Потрачено токенов: $tokens${NC}"
    fi
    echo ""
}

# --- ОСНОВНОЙ ПРОЦЕСС ---

# 1. Выбор задачи пользователем
select_task

# 2. Запуск 4 способов тестирования с выбранной задачей
# Обратите внимание: мы используем переменную $TASK, которую прочитали из файла

send_request "1. Прямой ответ" "$TASK Дай только краткий ответ без объяснений."

send_request "2. Пошаговое решение (Chain of Thought)" "$TASK Реши эту задачу пошагово. Сначала выпиши все условия, затем построй логическую цепочку, и только потом дай ответ."

send_request "3. Само-промптинг" "Я хочу решить задачу: '$TASK'. Сначала составь идеальный, детальный промпт для решения этой задачи, который заставит модель не ошибиться. Затем, используя этот составленный тобой промпт, реши задачу сам."

send_request "4. Группа экспертов" "Представь, что ты группа из трех экспертов: Аналитик, Инженер и Критик. Задача: '$TASK'. 1. Аналитик: Разбери условия формально. 2. Инженер: Построй схему решения. 3. Критик: Проверь выводы на ошибки. В конце выдай общее консенсусное решение."

echo -e "${GREEN}✅ Все тесты завершены!${NC}"