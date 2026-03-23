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
CYAN='\033[0;36m'
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
URL="https://openrouter.ai/api/v1/chat/completions"
TASKS_DIR="./tasks"

# --- СПИСОК МОДЕЛЕЙ ДЛЯ СРАВНЕНИЯ ---
# Ты можешь менять эти модели на актуальные из списка OpenRouter
declare -a MODELS=(
    "qwen/qwen-2.5-coder-32b-instruct"      # 1. Слабая/Дешевая (быстрая)
    "z-ai/glm-5-turbo"                      # 2. Средняя (баланс)
    "anthropic/claude-3.5-sonnet"           # 3. Сильная/Дорогая (умная)
)
declare -a MODEL_LABELS=(
    "Слабая (Qwen 2.5 Coder)"
    "Средняя (GLM 5 Turbo)"
    "Сильная (Claude 3.5 Sonnet)"
)

echo -e "${BLUE}🤖 УНИВЕРСАЛЬНЫЙ AI ТЕСТЕР${NC}"
echo "========================================"

# --- ШАГ 1: ВЫБОР МОДЕЛИ ИЛИ РЕЖИМ СРАВНЕНИЯ ---
echo -e "${YELLOW}1. Выбор режима работы:${NC}"
echo "   1) Тест одной конкретной модели"
echo "   2) Сравнение всех 3-х моделей (Слабая vs Средняя vs Сильная)"
echo -n "Ваш выбор (1-2): "
read mode_choice

SELECTED_MODEL=""
MODEL_NAME_DISPLAY=""

if [ "$mode_choice" == "1" ]; then
    echo -e "\n${YELLOW}Выберите модель:${NC}"
    for i in "${!MODELS[@]}"; do
        echo "   $((i+1))) ${MODEL_LABELS[$i]}"
    done
    echo -n "Номер модели (1-${#MODELS[@]}): "
    read model_idx
    
    if ! [[ "$model_idx" =~ ^[0-9]+$ ]] || [ "$model_idx" -lt 1 ] || [ "$model_idx" -gt "${#MODELS[@]}" ]; then
        echo -e "${RED}❌ Неверный номер.${NC}"; exit 1
    fi
    SELECTED_MODEL="${MODELS[$((model_idx-1))]}"
    MODEL_NAME_DISPLAY="${MODEL_LABELS[$((model_idx-1))]}"
    echo -e "${GREEN}✅ Выбрана модель: $MODEL_NAME_DISPLAY${NC}"
elif [ "$mode_choice" == "2" ]; then
    echo -e "${GREEN}✅ Режим сравнения: Будут протестированы все 3 модели.${NC}"
    SELECTED_MODEL="ALL"
else
    echo -e "${RED}❌ Неверный выбор.${NC}"; exit 1
fi

# --- ШАГ 2: ВЫБОР ТЕМПЕРАТУРЫ ---
echo -e "\n${YELLOW}2. Настройка температуры (Temperature):${NC}"
echo "   1) 0.0 (Строгая логика, детерминизм)"
echo "   2) 0.7 (Баланс, по умолчанию)"
echo "   3) 1.0 (Креатив, хаос)"
echo -n "Ваш выбор (1-3) [Enter для 0.7]: "
read temp_choice

case $temp_choice in
    1) TEMP="0.0" ;;
    2) TEMP="0.7" ;;
    3) TEMP="1.0" ;;
    *) TEMP="0.7" ;;
esac
echo -e "${GREEN}✅ Температура установлена: $TEMP${NC}"

# --- ШАГ 3: ВЫБОР ЗАДАЧИ ---
echo -e "\n${YELLOW}3. Выбор задачи из папки tasks/:${NC}"
files=()
i=1
if [ ! -d "$TASKS_DIR" ]; then
    echo -e "${RED}❌ Папка $TASKS_DIR не найдена!${NC}"; exit 1
fi

for file in "$TASKS_DIR"/*.txt; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        files+=("$filename")
        echo "   $i) $filename"
        ((i++))
    fi
done

if [ ${#files[@]} -eq 0 ]; then
    echo -e "${RED}❌ Нет файлов .txt в $TASKS_DIR${NC}"; exit 1
fi

echo -n "Номер задачи (1-${#files[@]}): "
read task_choice
if ! [[ "$task_choice" =~ ^[0-9]+$ ]] || [ "$task_choice" -lt 1 ] || [ "$task_choice" -gt "${#files[@]}" ]; then
    echo -e "${RED}❌ Неверный номер.${NC}"; exit 1
fi

selected_file="${TASKS_DIR}/${files[$((task_choice-1))]}"
TASK=$(cat "$selected_file")
echo -e "${GREEN}✅ Загружена задача: ${files[$((task_choice-1))]}${NC}"
echo "----------------------------------------"

# --- ФУНКЦИЯ ЗАПРОСА С ЗАМЕРОМ ВРЕМЕНИ ---
# --- ФУНКЦИЯ ЗАПРОСА С ЗАМЕРОМ ВРЕМЕНИ И ПОЛНЫМ ВЫВОДОМ ---
run_model_test() {
    local model=$1
    local label=$2
    local start_time=$(date +%s.%N)

    echo -e "\n${CYAN}🚀 ЗАПУСК: $label${NC}"
    echo "Модель: $model | Temp: $TEMP"
    echo "----------------------------------------"

    # Экранирование
    escaped_content=$(printf '%s' "$TASK" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | tr -d '\r')
    JSON_BODY="{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"$escaped_content\"}], \"temperature\": $TEMP}"

    # Запрос (получаем сырой ответ)
    RESPONSE=$(curl -s -w "\n%{time_total}" -X POST "$URL" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -H "HTTP-Referer: http://localhost" \
      -d "$JSON_BODY")

    # Разделяем тело ответа и время (последняя строка)
    RESPONSE_BODY=$(echo "$RESPONSE" | head -n -1)
    TIME_TAKEN=$(echo "$RESPONSE" | tail -n 1)

    # Парсинг контента и токенов
    CONTENT=""
    TOKENS=""
    
    if command -v jq &> /dev/null; then
        CONTENT=$(echo "$RESPONSE_BODY" | jq -r '.choices[0].message.content // "Ошибка парсинга"')
        TOKENS=$(echo "$RESPONSE_BODY" | jq -r '.usage.total_tokens // "N/A"')
    else
        # Резервный вариант без jq (может быть менее надежным для сложного текста)
        CONTENT=$(echo "$RESPONSE_BODY" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\n/\n/g' | sed 's/\\"/"/g')
        TOKENS=$(echo "$RESPONSE_BODY" | grep -o '"total_tokens":[0-9]*' | cut -d':' -f2)
        [ -z "$TOKENS" ] && TOKENS="N/A"
    fi

    # === ГЛАВНЫЙ БЛОК: ВЫВОД ОТВЕТА МОДЕЛИ ===
    echo -e "\n${YELLOW}💬 ОТВЕТ МОДЕЛИ (Размышления и результат):${NC}"
    echo "=================================================="
    if [ -n "$CONTENT" ] && [ "$CONTENT" != "Ошибка парсинга" ]; then
        # Выводим текст как есть, сохраняя переносы строк
        echo -e "$CONTENT"
    else
        echo -e "${RED}⚠️ Не удалось получить текст ответа.${NC}"
        echo "Проверьте raw ответ ниже:"
        echo "$RESPONSE_BODY"
    fi
    echo "=================================================="
    # ======================================================

    # Блок статистики
    echo -e "\n${GREEN}📊 ТЕХНИЧЕСКАЯ СТАТИСТИКА:${NC}"
    echo "   ⏱ Время ответа: ${TIME_TAKEN} сек."
    echo "   💰 Потрачено токенов: ${TOKENS}"
    echo "   🤖 Модель: $model"
    echo ""
}

# --- ОСНОВНОЙ ЗАПУСК ---
echo -e "\n${BLUE}🏁 НАЧАЛО ТЕСТИРОВАНИЯ${NC}"

if [ "$SELECTED_MODEL" == "ALL" ]; then
    # Режим сравнения: гоняем цикл по всем моделям
    for i in "${!MODELS[@]}"; do
        run_model_test "${MODELS[$i]}" "${MODEL_LABELS[$i]}"
    done
    echo -e "\n${GREEN}✅ Сравнение завершено! Проанализируйте время, токены и качество ответов выше.${NC}"
else
    # Режим одной модели
    run_model_test "$SELECTED_MODEL" "$MODEL_NAME_DISPLAY"
    echo -e "\n${GREEN}✅ Тест завершен!${NC}"
fi