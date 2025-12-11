# Добавление языковых моделей в Open WebUI

## Обзор

Open WebUI работает с моделями через Ollama или OpenAI-совместимые API. Для локального использования рекомендуется Ollama.

## Вариант 1: Использование Ollama (рекомендуется для офлайн)

### Установка Ollama на сервере

#### Скачивание Ollama на машине с интернетом

```bash
# Скачивание Ollama для Linux
cd ~
wget https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64

# Скачивание системного сервиса
wget https://raw.githubusercontent.com/ollama/ollama/main/systemd/ollama.service

# Создание архива
tar -czf ollama-offline.tar.gz ollama-linux-amd64 ollama.service
```

#### Установка Ollama на целевом сервере

```bash
# Распаковка
cd /tmp
tar -xzf /path/to/ollama-offline.tar.gz

# Установка Ollama
sudo mv ollama-linux-amd64 /usr/local/bin/ollama
sudo chmod +x /usr/local/bin/ollama

# Создание пользователя и директории
sudo useradd -r -s /bin/false -m -d /usr/share/ollama ollama
sudo mkdir -p /usr/share/ollama/.ollama
sudo chown -R ollama:ollama /usr/share/ollama

# Установка systemd сервиса
sudo mv ollama.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama

# Проверка
ollama --version
sudo systemctl status ollama
```

### Скачивание моделей на машине с интернетом

```bash
# Установка Ollama на машине с интернетом
curl -fsSL https://ollama.com/install.sh | sh

# Скачивание моделей (примеры)
ollama pull llama3.2:1b
ollama pull mistral:7b
ollama pull qwen2.5:7b

# Экспорт моделей
mkdir -p ~/ollama-models
ollama list

# Модели хранятся в ~/.ollama/models/
# Скопируйте всю директорию ~/.ollama/ на целевой сервер
# Или создайте архив:
cd ~
tar -czf ollama-models.tar.gz .ollama/
```

### Импорт моделей на целевом сервере

```bash
# Вариант 1: Копирование всей директории .ollama
sudo mkdir -p /usr/share/ollama
sudo tar -xzf /path/to/ollama-models.tar.gz -C /usr/share/ollama/
sudo chown -R ollama:ollama /usr/share/ollama/.ollama

# Вариант 2: Копирование только моделей
sudo mkdir -p /usr/share/ollama/.ollama/models
sudo cp -r /path/to/.ollama/models/* /usr/share/ollama/.ollama/models/
sudo chown -R ollama:ollama /usr/share/ollama/.ollama

# Перезапуск Ollama для применения изменений
sudo systemctl restart ollama

# Проверка
ollama list
```

### Настройка Open WebUI для работы с Ollama

#### Для Python установки

Отредактируйте `/opt/open-webui/start.sh`:

```bash
sudo nano /opt/open-webui/start.sh
```

Добавьте переменную окружения:

```bash
export OLLAMA_BASE_URL=http://localhost:11434
```

Или создайте файл конфигурации `/opt/open-webui/.env`:

```bash
sudo tee /opt/open-webui/.env > /dev/null <<'EOF'
OLLAMA_BASE_URL=http://localhost:11434
EOF
```

Обновите systemd сервис:

```bash
sudo nano /etc/systemd/system/open-webui.service
```

Добавьте в секцию [Service]:

```ini
EnvironmentFile=/opt/open-webui/.env
```

Перезапустите сервис:

```bash
sudo systemctl daemon-reload
sudo systemctl restart open-webui
```

#### Для Docker установки

Отредактируйте `/opt/open-webui-docker/docker-compose.yml`:

```bash
cd /opt/open-webui-docker
sudo nano docker-compose.yml
```

Измените `OLLAMA_BASE_URL`:

```yaml
environment:
  - OLLAMA_BASE_URL=http://host.docker.internal:11434
```

Или если Ollama в Docker сети:

```yaml
environment:
  - OLLAMA_BASE_URL=http://ollama:11434
```

Перезапустите:

```bash
sudo docker compose down
sudo docker compose up -d
```

## Вариант 2: Использование OpenAI-совместимых API

### Настройка через переменные окружения

#### Для Python установки

Добавьте в `/opt/open-webui/.env`:

```bash
OPENAI_API_KEY=your_api_key_here
OPENAI_API_BASE_URL=https://api.openai.com/v1
```

#### Для Docker установки

Добавьте в `docker-compose.yml`:

```yaml
environment:
  - OPENAI_API_KEY=your_api_key_here
  - OPENAI_API_BASE_URL=https://api.openai.com/v1
```

## Тестирование моделей

### Через веб-интерфейс

1. Откройте `http://IP_СЕРВЕРА:8080` в браузере
2. Войдите в систему (создайте аккаунт при первом запуске)
3. Перейдите в Settings (настройки) > Models (модели)
4. Выберите доступную модель из списка
5. Начните новый чат и выберите модель в интерфейсе чата

### Через API (для проверки)

```bash
# Проверка доступности Ollama
curl http://localhost:11434/api/tags

# Проверка доступности Open WebUI
curl http://localhost:8080/api/health
```

## Рекомендуемые модели для тестирования

### Легкие модели (для тестирования)

- `llama3.2:1b` - очень легкая, быстрая (около 1.3GB)
- `qwen2.5:0.5b` - минимальная модель (около 0.5GB)
- `phi3-mini` - компактная модель от Microsoft (около 2.3GB)

### Средние модели (баланс качества и скорости)

- `llama3.2:3b` - хороший баланс
- `mistral:7b` - качественная модель
- `qwen2.5:7b` - хорошая поддержка русского

### Команды для скачивания (на машине с интернетом)

```bash
ollama pull llama3.2:1b
ollama pull llama3.2:3b
ollama pull mistral:7b
ollama pull qwen2.5:7b
ollama pull phi3-mini
```

## Решение проблем

### Проблема: Модели не отображаются в Open WebUI

```bash
# Проверьте подключение к Ollama
curl http://localhost:11434/api/tags

# Проверьте переменную OLLAMA_BASE_URL
sudo systemctl status open-webui
sudo journalctl -u open-webui | grep OLLAMA

# Проверьте логи Open WebUI
sudo journalctl -u open-webui -n 50
```

### Проблема: Ollama не запускается

```bash
# Проверьте статус
sudo systemctl status ollama

# Проверьте логи
sudo journalctl -u ollama -f

# Проверьте права доступа
sudo chown -R ollama:ollama /usr/share/ollama
```

### Проблема: Модели не загружаются

```bash
# Проверьте наличие моделей
ollama list

# Проверьте место на диске
df -h /usr/share/ollama

# Проверьте права доступа к директории моделей
ls -la /usr/share/ollama/.ollama/models/
```
