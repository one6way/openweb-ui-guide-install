# Установка Open WebUI как Python приложения (без Docker)

## Требования

- CentOS 9
- Python 3.11
- Доступ к серверу с правами root или через sudo
- Минимум 2GB свободного места на диске

## Этап 1: Подготовка на машине с доступом в интернет

### 1.1. Установка системных зависимостей

На машине с интернетом (CentOS 9 или совместимый дистрибутив):

```bash
# Установка инструментов для скачивания
sudo dnf install -y python3.11 python3.11-pip python3.11-devel

# Установка системных зависимостей для компиляции пакетов
sudo dnf install -y gcc gcc-c++ libffi-devel openssl-devel make
```

### 1.2. Скачивание Python пакетов

```bash
# Создание директории для пакетов
mkdir -p ~/open-webui-packages
cd ~/open-webui-packages

# Создание виртуального окружения
python3.11 -m venv download-env
source download-env/bin/activate

# Обновление pip
pip install --upgrade pip setuptools wheel

# Установка open-webui для получения зависимостей
pip install open-webui

# Сохранение списка зависимостей
pip freeze > requirements.txt

# Скачивание всех пакетов
mkdir -p wheels
pip download -r requirements.txt -d wheels --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.11

# Если некоторые пакеты не имеют бинарных wheel, скачайте их тоже (исходники)
pip download -r requirements.txt -d wheels --no-binary=:all:

# Создание архива
cd ~
tar -czf open-webui-packages.tar.gz open-webui-packages/
```

### 1.3. Скачивание системных пакетов (опционально)

Если на целевом сервере нет системных пакетов:

```bash
# Установка yum-utils если нет
sudo dnf install -y yum-utils

# Скачивание системных пакетов
mkdir -p ~/centos-packages
cd ~/centos-packages
yumdownloader --resolve gcc gcc-c++ python3-devel libffi-devel openssl-devel make

# Создание архива
cd ~
tar -czf centos-packages.tar.gz centos-packages/
```

## Этап 2: Перенос файлов на целевой сервер

Перенесите следующие файлы на сервер:
- `open-webui-packages.tar.gz`
- `centos-packages.tar.gz` (если скачивали)

Способ переноса: USB, внутренняя сеть, SCP и т.д.

## Этап 3: Установка на целевом сервере

### 3.1. Установка системных зависимостей

```bash
# Распаковка системных пакетов (если переносили)
cd /tmp
tar -xzf /path/to/centos-packages.tar.gz
sudo dnf localinstall -y centos-packages/*.rpm

# Или если есть доступ к репозиториям
sudo dnf install -y gcc gcc-c++ python3-devel libffi-devel openssl-devel make
```

### 3.2. Распаковка Python пакетов

```bash
cd /opt
sudo tar -xzf /path/to/open-webui-packages.tar.gz

# Проверьте структуру после распаковки
ls -la

# Убедитесь что директория open-webui-packages находится в /opt
# Если она распаковалась в текущую директорию (/opt), все готово
# Если она в другом месте, переместите:
# sudo mv /другой/путь/open-webui-packages /opt/open-webui-packages

# Проверка что директория на месте
ls -la /opt/open-webui-packages/
```

### 3.3. Создание пользователя для сервиса

```bash
sudo useradd --system --no-create-home --shell /bin/false open-webui
```

### 3.4. Создание директорий

```bash
sudo mkdir -p /opt/open-webui
sudo mkdir -p /opt/open-webui/data
sudo chown open-webui:open-webui /opt/open-webui
sudo chown open-webui:open-webui /opt/open-webui/data
```

### 3.5. Создание виртуального окружения

```bash
cd /opt/open-webui
sudo -u open-webui python3.11 -m venv venv
```

### 3.6. Установка пакетов из локальных файлов

```bash
# Обновление pip
sudo -u open-webui /opt/open-webui/venv/bin/pip install --upgrade pip setuptools wheel

# Установка из локальных пакетов
# Убедитесь что директория с пакетами находится в /opt/open-webui-packages
# Если она в другом месте, укажите правильный путь
sudo -u open-webui /opt/open-webui/venv/bin/pip install --no-index --find-links /opt/open-webui-packages/wheels -r /opt/open-webui-packages/requirements.txt
```

### 3.7. Проверка установки

```bash
sudo -u open-webui /opt/open-webui/venv/bin/open-webui --version
```

### 3.8. Создание скрипта запуска

```bash
sudo tee /opt/open-webui/start.sh > /dev/null <<'EOF'
#!/bin/bash
cd /opt/open-webui
source venv/bin/activate

# Загрузка переменных окружения из .env файла (если существует)
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

export OPEN_WEBUI_DATA_DIR=${OPEN_WEBUI_DATA_DIR:-/opt/open-webui/data}
export OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT:-8080}
export OPEN_WEBUI_HOST=${OPEN_WEBUI_HOST:-0.0.0.0}

exec open-webui serve --host ${OPEN_WEBUI_HOST} --port ${OPEN_WEBUI_PORT}
EOF

sudo chmod +x /opt/open-webui/start.sh
sudo chown open-webui:open-webui /opt/open-webui/start.sh
```

### 3.9. Создание systemd сервиса

```bash
sudo tee /etc/systemd/system/open-webui.service > /dev/null <<'EOF'
[Unit]
Description=Open WebUI - User-friendly web interface for LLMs
After=network.target

[Service]
Type=simple
User=open-webui
Group=open-webui
WorkingDirectory=/opt/open-webui
Environment="PATH=/opt/open-webui/venv/bin"
EnvironmentFile=/opt/open-webui/.env
Environment="OPEN_WEBUI_DATA_DIR=/opt/open-webui/data"
Environment="OPEN_WEBUI_PORT=8080"
Environment="OPEN_WEBUI_HOST=0.0.0.0"
ExecStart=/opt/open-webui/start.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=open-webui

# Безопасность
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/open-webui/data

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузка systemd
sudo systemctl daemon-reload
sudo systemctl enable open-webui
sudo systemctl start open-webui
```

### 3.10. Настройка firewall

```bash
# Для firewalld
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Проверка
sudo firewall-cmd --list-ports
```

### 3.11. Проверка работы

```bash
# Статус сервиса
sudo systemctl status open-webui

# Логи
sudo journalctl -u open-webui -f

# Проверка порта
sudo ss -tulpn | grep 8080
```

## Доступ к интерфейсу

Откройте в браузере: `http://IP_СЕРВЕРА:8080`

При первом запуске создайте администраторский аккаунт.

## Управление сервисом

```bash
# Запуск
sudo systemctl start open-webui

# Остановка
sudo systemctl stop open-webui

# Перезапуск
sudo systemctl restart open-webui

# Статус
sudo systemctl status open-webui

# Логи
sudo journalctl -u open-webui -f
sudo journalctl -u open-webui -n 100
```

## Решение проблем

### Проблема: Сервис не запускается

```bash
# Проверьте логи
sudo journalctl -u open-webui -n 50

# Проверьте права доступа
sudo chown -R open-webui:open-webui /opt/open-webui

# Проверьте виртуальное окружение
sudo -u open-webui /opt/open-webui/venv/bin/python --version
```

### Проблема: Ошибки при установке пакетов

```bash
# Убедитесь что все системные зависимости установлены
sudo dnf install -y gcc gcc-c++ python3-devel libffi-devel openssl-devel make

# Попробуйте установить проблемный пакет отдельно
sudo -u open-webui /opt/open-webui/venv/bin/pip install --no-index --find-links /opt/open-webui-packages/wheels имя_пакета
```

### Проблема: Порт занят

```bash
# Найдите процесс на порту 8080
sudo lsof -i :8080

# Измените порт в /opt/open-webui/start.sh и /etc/systemd/system/open-webui.service
# Затем перезапустите сервис
sudo systemctl daemon-reload
sudo systemctl restart open-webui
```
