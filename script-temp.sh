#!/bin/bash

# Принудительная кодировка для Windows/Git Bash
chcp 65001 > /dev/null 2>&1
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# --- ЦВЕТА ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- ЗАГРУЗКА .ENV ---
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

echo -e "${BLUE}🌡️  ЭКСПЕРИМЕНТ: TEMPERATURE TEST${NC}"
echo "Модель: $MODEL"
echo "----------------------------------------"

# --- ФУНКЦИЯ ВЫБОРА ЗАДАЧИ (как в основном скрипте) ---
select_task() {
    echo -e "${YELLOW}📂 Доступные файлы с задачами:${NC}"
    files=()
    i=1
    if [ ! -d "$TASKS_DIR" ]; then
        echo -e "${RED}❌ Папка $TASKS_DIR не найдена!${NC}"
        exit 1
    fi
    for file in "$TASKS_DIR"/*.txt; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            # Исключаем файлы, которые явно не подходят (опционально)
            files+=("$filename")
            echo "   $i) $filename"
            ((i++))
        fi
    done
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}❌ Нет файлов .txt в $TASKS_DIR${NC}"
        exit 1
    fi
    echo ""
    echo -n "Выберите номер задачи для теста температуры (1-${#files[@]}): "
    read choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#files[@]}" ]; then
        echo -e "${RED}❌ Неверный номер.${NC}"
        exit 1
    fi
    selected_file="${TASKS_DIR}/${files[$((choice-1))]}"
     Пробуем конвертировать из UTF-8 в WINDOWS-1251. Если iconv нет, пробуем cat.
    if command -v iconv &> /dev/null; then
        TASK=$(iconv -f UTF-8 -t WINDOWS-1251 "$selected_file" 2>/dev/null || cat "$selected_file")
    else
        TASK=$(cat "$selected_file")
    fi
    echo -e "${GREEN}✅ Выбрана задача: ${files[$((choice-1))]}${NC}"
    echo "----------------------------------------"
}

# --- ФУНКЦИЯ ЗАПРОСА С КОНКРЕТНОЙ ТЕМПЕРАТУРОЙ ---
run_temp_test() {
    local temp_val=$1
    local label=$2
    
    echo -e "${YELLOW}▶️  ЗАПУСК: $label (Temperature = $temp_val)${NC}"
    
    # Экранирование для JSON
    escaped_content=$(printf '%s' "$TASK" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | tr -d '\r')

    # Формируем JSON с параметром temperature
    JSON_BODY="{\"model\": \"$MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"$escaped_content\"}], \"temperature\": $temp_val}"

    RESPONSE=$(curl -s -X POST "$URL" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -H "HTTP-Referer: http://localhost" \
      -d "$JSON_BODY")

    # Проверка на ошибку API
    if echo "$RESPONSE" | grep -q '"error"'; then
        echo -e "${RED}⚠️ Ошибка API: $(echo "$RESPONSE" | grep -o '"message":"[^"]*"')${NC}"
        return
    fi

    # Извлечение ответа
    CONTENT=""
    if command -v jq &> /dev/null; then
        CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
    else
        CONTENT=$(echo "$RESPONSE" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\n/\n/g' | sed 's/\\"/"/g')
    fi

    if [ -n "$CONTENT" ]; then
        echo "$CONTENT"
    else
        echo -e "${RED}⚠️ Не удалось получить ответ.${NC}"
    fi
    
    # Статистика
    tokens=$(echo "$RESPONSE" | grep -o '"total_tokens":[0-9]*' | cut -d':' -f2)
    if [ -n "$tokens" ]; then
        echo -e "${GREEN}💰 Токенов: $tokens${NC}"
    fi
    echo ""
    echo "=================================================="
    echo ""
}

# --- ОСНОВНОЙ ПРОЦЕСС ---

# 1. Выбор задачи
select_task

echo ""
echo "🚀 Начинаем прогон с тремя значениями температуры..."
echo ""

# 2. Запуск тестов
# Температура 0.0 (Детерминизм)
run_temp_test "0.0" "Строгая логика"

# Температура 0.7 (Баланс)
run_temp_test "0.7" "Стандартный режим"

# Температура 1.2 (Креатив/Хаос)
run_temp_test "1.2" "Высокая креативность"

echo -e "${GREEN}✅ Эксперимент завершен!${NC}"
echo "Сравните ответы выше:"
echo "- При 0.0 ответ должен быть одинаковым при каждом запуске."
echo "- При 1.2 ответ может содержать выдуманные детали или ошибки логики."