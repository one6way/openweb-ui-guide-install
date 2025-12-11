# Настройка DNS для Open WebUI

## Обзор

После установки Open WebUI доступен по IP адресу. Для удобства использования можно настроить DNS имя.

## Вариант 1: Локальный DNS (для внутренней сети)

### Установка и настройка BIND (DNS сервер)

#### Установка BIND

```bash
sudo dnf install -y bind bind-utils
```

#### Конфигурация BIND

Создайте зону для вашего домена. Например, для домена `internal.local`:

```bash
sudo nano /etc/named.conf
```

Добавьте в секцию `options`:

```conf
listen-on port 53 { 127.0.0.1; 192.168.1.0/24; };
allow-query { localhost; 192.168.1.0/24; };
```

Добавьте зону в конец файла:

```conf
zone "internal.local" IN {
    type master;
    file "internal.local.zone";
    allow-update { none; };
};
```

#### Создание файла зоны

```bash
sudo nano /var/named/internal.local.zone
```

Содержимое:

```zone
$TTL 86400
@   IN  SOA     ns1.internal.local. admin.internal.local. (
                    2024010101  ; Serial
                    3600        ; Refresh
                    1800        ; Retry
                    604800      ; Expire
                    86400       ; Minimum TTL
)
@       IN  NS      ns1.internal.local.
ns1     IN  A       192.168.1.10
openwebui   IN  A   192.168.1.10
```

Где `192.168.1.10` - IP адрес вашего сервера.

#### Запуск BIND

```bash
sudo systemctl start named
sudo systemctl enable named
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload
```

#### Настройка клиентов

На клиентских машинах укажите DNS сервер:

```bash
# В /etc/resolv.conf
nameserver 192.168.1.10
search internal.local
```

Или через NetworkManager:

```bash
sudo nmcli connection modify "connection-name" ipv4.dns "192.168.1.10"
sudo nmcli connection modify "connection-name" ipv4.dns-search "internal.local"
sudo nmcli connection down "connection-name"
sudo nmcli connection up "connection-name"
```

### Проверка DNS

```bash
# С сервера
nslookup openwebui.internal.local

# С клиента
ping openwebui.internal.local
```

## Вариант 2: Использование /etc/hosts (простой вариант)

### На сервере

```bash
sudo nano /etc/hosts
```

Добавьте:

```
192.168.1.10    openwebui.internal.local
```

### На клиентских машинах

Добавьте ту же строку в `/etc/hosts` (Linux/Mac) или `C:\Windows\System32\drivers\etc\hosts` (Windows).

## Вариант 3: Интеграция с существующим DNS сервером

### Добавление A записи в существующий DNS

Если у вас уже есть DNS сервер (Active Directory, другой BIND сервер и т.д.):

1. Войдите на DNS сервер
2. Добавьте A запись:
   - Имя: `openwebui` (или любое другое)
   - Тип: `A`
   - Значение: IP адрес сервера (например, `192.168.1.10`)
   - TTL: `3600`

### Пример для Active Directory DNS

1. Откройте DNS Manager
2. Перейдите в Forward Lookup Zones > ваш домен
3. Создайте новую A запись:
   - Name: `openwebui`
   - IP address: `192.168.1.10`

## Настройка Open WebUI для работы с доменным именем

### Обновление WEBUI_URL

#### Для Python установки

Отредактируйте `/opt/open-webui/.env`:

```bash
sudo nano /opt/open-webui/.env
```

Измените:

```bash
WEBUI_URL=http://openwebui.internal.local:8080
```

Или для HTTPS:

```bash
WEBUI_URL=https://openwebui.internal.local
```

Перезапустите:

```bash
sudo systemctl restart open-webui
```

#### Для Docker установки

Отредактируйте `docker-compose.yml`:

```yaml
environment:
  - WEBUI_URL=http://openwebui.internal.local:8080
```

Перезапустите:

```bash
sudo docker compose restart
```

## Настройка HTTPS через reverse proxy

### Установка nginx

```bash
sudo dnf install -y nginx certbot python3-certbot-nginx
```

### Конфигурация nginx

Создайте `/etc/nginx/conf.d/open-webui.conf`:

```nginx
server {
    listen 80;
    server_name openwebui.internal.local;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Таймауты для долгих запросов
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
    }
}
```

### Получение SSL сертификата (если есть доступ к интернету)

Примечание: Для работы certbot требуется доступ в интернет. Если сервер изолирован, используйте самоподписанный сертификат (см. ниже).

```bash
# Установка certbot (если еще не установлен)
sudo dnf install -y certbot python3-certbot-nginx

# Получение сертификата
sudo certbot --nginx -d openwebui.internal.local
```

### Использование самоподписанного сертификата (офлайн)

```bash
# Создание директории для сертификатов
sudo mkdir -p /etc/nginx/ssl

# Создание сертификата
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/openwebui.key \
    -out /etc/nginx/ssl/openwebui.crt \
    -subj "/CN=openwebui.internal.local"

# Установка прав доступа
sudo chmod 600 /etc/nginx/ssl/openwebui.key
sudo chmod 644 /etc/nginx/ssl/openwebui.crt
sudo chown root:root /etc/nginx/ssl/openwebui.*

# Обновление nginx конфигурации
sudo nano /etc/nginx/conf.d/open-webui.conf
```

Замените содержимое файла на:

```nginx
server {
    listen 443 ssl http2;
    server_name openwebui.internal.local;

    ssl_certificate /etc/nginx/ssl/openwebui.crt;
    ssl_certificate_key /etc/nginx/ssl/openwebui.key;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Таймауты для долгих запросов
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
    }
}

server {
    listen 80;
    server_name openwebui.internal.local;
    return 301 https://$server_name$request_uri;
}
```

### Запуск nginx

```bash
sudo systemctl start nginx
sudo systemctl enable nginx
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## Проверка конфигурации

### Проверка DNS разрешения

```bash
# С сервера
nslookup openwebui.internal.local
dig openwebui.internal.local

# С клиента
ping openwebui.internal.local
curl http://openwebui.internal.local:8080
```

### Проверка nginx

```bash
# Проверка конфигурации
sudo nginx -t

# Статус
sudo systemctl status nginx

# Логи
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Доступ к Open WebUI

После настройки DNS и nginx:

- HTTP: `http://openwebui.internal.local`
- HTTPS: `https://openwebui.internal.local`

## Решение проблем

### Проблема: DNS не разрешается

```bash
# Проверьте работу DNS сервера
sudo systemctl status named

# Проверьте конфигурацию
sudo named-checkconf
sudo named-checkzone internal.local /var/named/internal.local.zone

# Проверьте firewall
sudo firewall-cmd --list-all
```

### Проблема: nginx не проксирует запросы

```bash
# Проверьте конфигурацию
sudo nginx -t

# Проверьте логи
sudo tail -f /var/log/nginx/error.log

# Проверьте что Open WebUI слушает на порту 8080
sudo ss -tulpn | grep 8080
```
