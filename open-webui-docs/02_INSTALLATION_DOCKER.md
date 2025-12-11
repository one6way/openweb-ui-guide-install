# Установка Open WebUI с помощью Docker (офлайн)

## Требования

- CentOS 9
- Docker установлен
- Доступ к серверу с правами root или через sudo
- Минимум 3GB свободного места на диске

## Этап 1: Подготовка на машине с доступом в интернет

### 1.1. Установка Docker (если не установлен)

На машине с интернетом:

```bash
# Установка Docker
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Запуск Docker
sudo systemctl start docker
sudo systemctl enable docker
```

### 1.2. Скачивание Docker образов

```bash
# Скачивание образа Open WebUI
docker pull ghcr.io/open-webui/open-webui:main

# Сохранение образа в файл
mkdir -p ~/docker-images
docker save ghcr.io/open-webui/open-webui:main -o ~/docker-images/open-webui-main.tar

# Сжатие образа
gzip ~/docker-images/open-webui-main.tar

# Проверка размера
ls -lh ~/docker-images/
```

### 1.3. Создание docker-compose.yml

```bash
mkdir -p ~/open-webui-docker
cd ~/open-webui-docker

cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "8080:8080"
    volumes:
      - open-webui-data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:11434
      - WEBUI_SECRET_KEY=change_this_secret_key_in_production
      - WEBUI_NAME=Open WebUI
      - WEBUI_URL=http://IP_СЕРВЕРА:8080
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  open-webui-data:
    driver: local
EOF

# Примечание: Замените IP_СЕРВЕРА на реальный IP адрес сервера перед использованием

# Создание архива
cd ~
tar -czf open-webui-docker.tar.gz open-webui-docker/ docker-images/
```

## Этап 2: Перенос файлов на целевой сервер

Перенесите следующие файлы на сервер:
- `open-webui-docker.tar.gz`

## Этап 3: Установка на целевом сервере

### 3.1. Установка Docker (если не установлен)

```bash
# Если есть доступ к репозиториям
sudo dnf install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Или установка из локальных RPM пакетов (если скачали)
# sudo dnf localinstall -y docker-packages/*.rpm

# Запуск Docker
sudo systemctl start docker
sudo systemctl enable docker

# Проверка
sudo docker --version
```

### 3.2. Распаковка файлов

```bash
cd /opt
sudo tar -xzf /path/to/open-webui-docker.tar.gz

# Проверьте структуру после распаковки
ls -la

# Убедитесь что директории на месте:
# - open-webui-docker/ (или в поддиректории)
# - docker-images/ (или в поддиректории)

# Если они распаковались в текущую директорию (/opt), все готово
# Если они в другом месте, переместите:
# sudo mv /другой/путь/open-webui-docker /opt/open-webui-docker
# sudo mv /другой/путь/docker-images /opt/docker-images

# Проверка
ls -la /opt/open-webui-docker/
ls -la /opt/docker-images/
```

### 3.3. Загрузка Docker образа

```bash
# Распаковка и загрузка образа
gunzip -c /opt/docker-images/open-webui-main.tar.gz | sudo docker load

# Проверка загрузки
sudo docker images | grep open-webui
```

### 3.4. Настройка docker-compose.yml

```bash
cd /opt/open-webui-docker

# Генерация секретного ключа
SECRET_KEY=$(openssl rand -base64 32)

# Обновление docker-compose.yml с секретным ключом
sed -i "s/change_this_secret_key_in_production/$SECRET_KEY/" docker-compose.yml

# Замените IP_СЕРВЕРА на реальный IP адрес сервера
SERVER_IP=$(hostname -I | awk '{print $1}')
sed -i "s/IP_СЕРВЕРА/$SERVER_IP/" docker-compose.yml

# Проверка изменений
grep WEBUI_URL docker-compose.yml

# Если нужно изменить порт или другие настройки, отредактируйте docker-compose.yml
# nano docker-compose.yml
```

### 3.5. Запуск Open WebUI

```bash
cd /opt/open-webui-docker
sudo docker compose up -d

# Проверка статуса
sudo docker compose ps

# Просмотр логов
sudo docker compose logs -f
```

### 3.6. Настройка firewall

```bash
# Для firewalld
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Проверка
sudo firewall-cmd --list-ports
```

### 3.7. Создание systemd сервиса для автозапуска (опционально)

```bash
sudo tee /etc/systemd/system/docker-compose-open-webui.service > /dev/null <<'EOF'
[Unit]
Description=Open WebUI Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/open-webui-docker
ExecStart=/usr/bin/docker compose -f /opt/open-webui-docker/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f /opt/open-webui-docker/docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable docker-compose-open-webui
```

## Доступ к интерфейсу

Откройте в браузере: `http://IP_СЕРВЕРА:8080`

При первом запуске создайте администраторский аккаунт.

## Управление

```bash
cd /opt/open-webui-docker

# Запуск
sudo docker compose up -d

# Остановка
sudo docker compose down

# Перезапуск
sudo docker compose restart

# Просмотр логов
sudo docker compose logs -f
sudo docker compose logs --tail=100

# Статус
sudo docker compose ps
```

## Резервное копирование данных

```bash
# Создание бэкапа
cd /opt/open-webui-docker
# Имя volume формируется как: имя_директории_volume
VOLUME_NAME=$(docker compose config --volumes | head -1)
sudo docker run --rm -v ${VOLUME_NAME}:/data -v $(pwd):/backup alpine tar czf /backup/open-webui-backup-$(date +%Y%m%d).tar.gz -C /data .

# Восстановление из бэкапа (замените YYYYMMDD на дату бэкапа, например 20240101)
cd /opt/open-webui-docker
VOLUME_NAME=$(docker compose config --volumes | head -1)
sudo docker run --rm -v ${VOLUME_NAME}:/data -v $(pwd):/backup alpine sh -c "cd /data && tar xzf /backup/open-webui-backup-YYYYMMDD.tar.gz"
```

## Решение проблем

### Проблема: Контейнер не запускается

```bash
# Проверьте логи
sudo docker compose logs open-webui

# Проверьте конфигурацию
sudo docker compose config

# Проверьте образ
sudo docker images | grep open-webui
```

### Проблема: Порт занят

```bash
# Найдите процесс на порту 8080
sudo ss -tulpn | grep 8080

# Измените порт в docker-compose.yml
sudo nano docker-compose.yml
# Измените "8080:8080" на "НОВЫЙ_ПОРТ:8080"
sudo docker compose up -d
```

### Проблема: Проблемы с volumes

```bash
# Проверьте volumes
sudo docker volume ls

# Удаление volume (осторожно, удалит данные)
# Сначала определите имя volume
VOLUME_NAME=$(docker compose config --volumes | head -1)
sudo docker volume rm ${VOLUME_NAME}

# Пересоздание
sudo docker compose up -d
```
