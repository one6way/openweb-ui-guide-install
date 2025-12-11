# Расширенная конфигурация Open WebUI

## Аутентификация через LDAP

### Настройка LDAP сервера

Убедитесь что у вас есть:
- Адрес LDAP сервера
- Порт (389 для LDAP, 636 для LDAPS)
- DN для привязки (bind DN)
- Пароль для привязки
- База поиска (search base)
- Атрибут для имени пользователя (обычно `uid` или `cn`)

### Конфигурация Open WebUI для LDAP

#### Для Python установки

Создайте или отредактируйте `/opt/open-webui/.env`:

```bash
# Если файл .env не существует, создайте его
# Если существует, команда добавит настройки в конец файла
sudo tee -a /opt/open-webui/.env > /dev/null <<'EOF'
ENABLE_LDAP=true
LDAP_SERVER_LABEL=Corporate LDAP
LDAP_SERVER_HOST=ldap.example.com
LDAP_SERVER_PORT=389
LDAP_USE_TLS=false
LDAP_VALIDATE_CERT=false
LDAP_APP_DN=cn=admin,dc=example,dc=com
LDAP_APP_PASSWORD=your_ldap_password
LDAP_SEARCH_BASE=dc=example,dc=com
LDAP_ATTRIBUTE_FOR_USERNAME=uid
LDAP_ATTRIBUTE_FOR_MAIL=mail
LDAP_SEARCH_FILTER=(uid=%(user)s)
EOF
```

Для LDAPS (защищенное соединение):

```bash
LDAP_SERVER_PORT=636
LDAP_USE_TLS=true
LDAP_VALIDATE_CERT=true
```

Обновите systemd сервис для загрузки .env файла:

```bash
sudo nano /etc/systemd/system/open-webui.service
```

Добавьте в секцию [Service]:

```ini
EnvironmentFile=/opt/open-webui/.env
```

Перезапустите:

```bash
sudo systemctl daemon-reload
sudo systemctl restart open-webui
```

#### Для Docker установки

Отредактируйте `/opt/open-webui-docker/docker-compose.yml`:

```yaml
environment:
  - ENABLE_LDAP=true
  - LDAP_SERVER_LABEL=Corporate LDAP
  - LDAP_SERVER_HOST=ldap.example.com
  - LDAP_SERVER_PORT=389
  - LDAP_USE_TLS=false
  - LDAP_VALIDATE_CERT=false
  - LDAP_APP_DN=cn=admin,dc=example,dc=com
  - LDAP_APP_PASSWORD=your_ldap_password
  - LDAP_SEARCH_BASE=dc=example,dc=com
  - LDAP_ATTRIBUTE_FOR_USERNAME=uid
  - LDAP_ATTRIBUTE_FOR_MAIL=mail
  - LDAP_SEARCH_FILTER=(uid=%(user)s)
```

Перезапустите:

```bash
cd /opt/open-webui-docker
sudo docker compose down
sudo docker compose up -d
```

### Тестирование LDAP подключения

```bash
# Установка ldapsearch (если нужно)
sudo dnf install -y openldap-clients

# Тест подключения
ldapsearch -x -H ldap://ldap.example.com:389 -D "cn=admin,dc=example,dc=com" -w your_ldap_password -b "dc=example,dc=com" "(uid=testuser)"
```

## Аутентификация через Keycloak (OIDC/OAuth)

### Установка Keycloak

#### Скачивание Keycloak на машине с интернетом

```bash
cd ~
# Замените XX.X.X на актуальную версию, например 25.0.0
wget https://github.com/keycloak/keycloak/releases/latest/download/keycloak-XX.X.X.tar.gz
tar -xzf keycloak-XX.X.X.tar.gz
tar -czf keycloak-offline.tar.gz keycloak-XX.X.X/
```

#### Установка Keycloak на целевом сервере

```bash
# Распаковка (замените XX.X.X на версию из скачанного архива)
cd /opt
sudo tar -xzf /path/to/keycloak-offline.tar.gz
sudo mv keycloak-XX.X.X keycloak

# Создание пользователя
sudo useradd -r -s /bin/false keycloak
sudo chown -R keycloak:keycloak /opt/keycloak

# Настройка Keycloak
cd /opt/keycloak
sudo -u keycloak bin/kc.sh build
```

#### Настройка Keycloak Realm и Client

1. Запустите Keycloak:

```bash
sudo -u keycloak /opt/keycloak/bin/kc.sh start-dev --http-port=9090
```

2. Откройте `http://IP_СЕРВЕРА:9090`
3. Создайте администратора
4. Создайте новый Realm: `openwebui`
5. Создайте Client:
   - Client ID: `open-webui`
   - Client Protocol: `openid-connect`
   - Access Type: `confidential`
   - Valid Redirect URIs: `http://IP_СЕРВЕРА:8080/oauth/oidc/callback`
   - Сохраните Client Secret

### Конфигурация Open WebUI для Keycloak

#### Для Python установки

Добавьте в `/opt/open-webui/.env`:

```bash
sudo tee -a /opt/open-webui/.env > /dev/null <<'EOF'
ENABLE_OAUTH_SIGNUP=true
OAUTH_CLIENT_ID=open-webui
OAUTH_CLIENT_SECRET=your_client_secret_from_keycloak
OPENID_PROVIDER_URL=http://IP_СЕРВЕРА:9090/realms/openwebui/.well-known/openid-configuration
OAUTH_PROVIDER_NAME=Keycloak
OPENID_REDIRECT_URI=http://IP_СЕРВЕРА:8080/oauth/oidc/callback
EOF
```

Перезапустите:

```bash
sudo systemctl restart open-webui
```

#### Для Docker установки

Добавьте в `docker-compose.yml`:

```yaml
environment:
  - ENABLE_OAUTH_SIGNUP=true
  - OAUTH_CLIENT_ID=open-webui
  - OAUTH_CLIENT_SECRET=your_client_secret_from_keycloak
  - OPENID_PROVIDER_URL=http://IP_СЕРВЕРА:9090/realms/openwebui/.well-known/openid-configuration
  - OAUTH_PROVIDER_NAME=Keycloak
  - OPENID_REDIRECT_URI=http://IP_СЕРВЕРА:8080/oauth/oidc/callback
```

Перезапустите:

```bash
sudo docker compose restart
```

## Логирование активности пользователей

### Настройка логирования в Open WebUI

#### Для Python установки

Добавьте в `/opt/open-webui/.env`:

```bash
# Команда добавит настройки логирования в конец файла .env
sudo tee -a /opt/open-webui/.env > /dev/null <<'EOF'
GLOBAL_LOG_LEVEL=INFO
LOG_CHAT_HISTORY=true
LOG_USER_ACTIVITY=true
EOF
```

Примечание: Переменные `LOG_CHAT_HISTORY` и `LOG_USER_ACTIVITY` могут не поддерживаться в некоторых версиях Open WebUI. Основное логирование работает через `GLOBAL_LOG_LEVEL`.

Создайте директорию для логов:

```bash
sudo mkdir -p /var/log/open-webui
sudo chown open-webui:open-webui /var/log/open-webui
```

Обновите systemd сервис для логирования в файл:

```bash
sudo nano /etc/systemd/system/open-webui.service
```

Измените секцию [Service] (замените существующие строки StandardOutput и StandardError):

```ini
StandardOutput=append:/var/log/open-webui/app.log
StandardError=append:/var/log/open-webui/error.log
```

Примечание: В systemd версии < 240 может не поддерживаться `append:`. В этом случае используйте перенаправление через скрипт или оставьте `journal`.

Перезапустите:

```bash
sudo systemctl daemon-reload
sudo systemctl restart open-webui
```

#### Для Docker установки

Добавьте volume для логов в `docker-compose.yml`:

```yaml
services:
  open-webui:
    volumes:
      - open-webui-data:/app/backend/data
      - ./logs:/var/log/open-webui
    environment:
      - GLOBAL_LOG_LEVEL=INFO
      - LOG_CHAT_HISTORY=true
      - LOG_USER_ACTIVITY=true
```

Создайте директорию:

```bash
mkdir -p /opt/open-webui-docker/logs
```

### Настройка ротации логов

Создайте `/etc/logrotate.d/open-webui`:

```bash
sudo tee /etc/logrotate.d/open-webui > /dev/null <<'EOF'
/var/log/open-webui/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 open-webui open-webui
    sharedscripts
    postrotate
        systemctl reload open-webui > /dev/null 2>&1 || true
    endscript
}
EOF
```

### Мониторинг активности через systemd journal

```bash
# Все логи Open WebUI
sudo journalctl -u open-webui -f

# Логи с фильтром по пользователю
sudo journalctl -u open-webui | grep "username"

# Логи за последний час
sudo journalctl -u open-webui --since "1 hour ago"

# Экспорт логов в файл
sudo journalctl -u open-webui --since "2024-01-01" > /tmp/open-webui-logs.txt
```

### Настройка внешнего логирования (опционально)

Примечание: Open WebUI использует стандартное логирование Python. Для интеграции с внешними системами логирования (ELK, Loki и т.д.) используйте стандартные инструменты:
- Для systemd: настройте journald для отправки в централизованную систему
- Для Docker: используйте драйверы логирования Docker (fluentd, syslog и т.д.)
- Для файловых логов: используйте filebeat, logstash или аналогичные инструменты

## Настройка ролей и прав доступа

### Создание пользовательских ролей

Через веб-интерфейс:
1. Войдите как администратор
2. Перейдите в Settings > Users & Roles
3. Создайте новую роль
4. Настройте права доступа

### Ограничение доступа к моделям

Добавьте в `.env` или `docker-compose.yml`:

```bash
DEFAULT_USER_ROLE=user
ENABLE_SIGNUP=false
```

Примечание: Ограничение доступа к моделям настраивается через веб-интерфейс в разделе Settings > Models, где администратор может назначить доступ к моделям для разных ролей пользователей.

## Настройка базы данных

### Использование PostgreSQL вместо SQLite

#### Установка PostgreSQL

```bash
sudo dnf install -y postgresql-server postgresql
sudo postgresql-setup --initdb
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

#### Создание базы данных

```bash
sudo -u postgres psql
CREATE DATABASE openwebui;
CREATE USER openwebui WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE openwebui TO openwebui;
\q
```

#### Настройка Open WebUI

Для Python установки, добавьте в `.env`:

```bash
DATABASE_URL=postgresql://openwebui:your_password@localhost:5432/openwebui
```

Для Docker установки, добавьте в `docker-compose.yml`:

```yaml
services:
  open-webui:
    environment:
      - DATABASE_URL=postgresql://openwebui:your_password@postgres:5432/openwebui
    depends_on:
      - postgres

  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: openwebui
      POSTGRES_USER: openwebui
      POSTGRES_PASSWORD: your_password
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  open-webui-data:
  postgres-data:
```

## Безопасность

### Настройка HTTPS (через reverse proxy)

Рекомендуется использовать nginx или traefik как reverse proxy.

#### Установка nginx

```bash
sudo dnf install -y nginx
```

#### Конфигурация nginx

Создайте `/etc/nginx/conf.d/open-webui.conf`:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Перезапустите nginx:

```bash
sudo systemctl restart nginx
sudo systemctl enable nginx
```

### Ограничение доступа по IP

Добавьте в nginx конфигурацию:

```nginx
allow 192.168.1.0/24;
allow 10.0.0.0/8;
deny all;
```

## Резервное копирование

### Автоматический бэкап данных

Создайте скрипт `/usr/local/bin/backup-open-webui.sh`:

```bash
#!/bin/bash
BACKUP_DIR="/backup/open-webui"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Определение типа установки
if [ -d "/opt/open-webui/data" ]; then
    # Python установка
    sudo tar -czf $BACKUP_DIR/data-$DATE.tar.gz /opt/open-webui/data
elif [ -d "/opt/open-webui-docker" ]; then
    # Docker установка
    cd /opt/open-webui-docker
    VOLUME_NAME=$(docker compose config --volumes | head -1)
    sudo docker run --rm -v ${VOLUME_NAME}:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/data-$DATE.tar.gz -C /data .
else
    echo "Ошибка: Open WebUI не найден"
    exit 1
fi

# Удаление старых бэкапов (старше 30 дней)
find $BACKUP_DIR -name "data-*.tar.gz" -mtime +30 -delete

echo "Бэкап создан: $BACKUP_DIR/data-$DATE.tar.gz"
```

Сделайте скрипт исполняемым:

```bash
sudo chmod +x /usr/local/bin/backup-open-webui.sh
```

Создайте cron задачу:

```bash
sudo crontab -e
```

Добавьте:

```
0 2 * * * /usr/local/bin/backup-open-webui.sh
```
