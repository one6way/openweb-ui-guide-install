#!/usr/bin/env sh

# Портативная проверка TLS-сертификатов для запуска прямо на сервере.
# - Читает цели из файла (по умолчанию: targets.txt)
# - Для каждого host:port получает листовой сертификат через openssl
# - Считает оставшиеся дни и отправляет письмо, если ниже порога
#
# Требования: openssl, date (желательно GNU coreutils), awk, sed
# Опционально: mailx или mail для отправки писем

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# Значения по умолчанию (можно переопределить через ENV или флаги CLI)
TARGETS_FILE="${TARGETS_FILE:-$SCRIPT_DIR/targets.txt}"
ALERT_DAYS_DEFAULT="${ALERT_DAYS_DEFAULT:-30}"
# По умолчанию локальная доставка: в системный почтовый ящик пользователя (читается через `mailx`)
MAILBOX_USER_DEFAULT="$(id -un 2>/dev/null || echo root)"
MAIL_TO="${MAIL_TO:-$MAILBOX_USER_DEFAULT}"
MAIL_FROM="${MAIL_FROM:-cert-checker@$(hostname -f 2>/dev/null || hostname)}"
MAIL_SUBJECT_PREFIX="${MAIL_SUBJECT_PREFIX:-[TLS-CERT]}"
# Если true — принудительно использовать локальную доставку через sendmail и адрес без домена
MAIL_LOCAL_ONLY="${MAIL_LOCAL_ONLY:-true}"
QUIET="false"

usage() {
  cat <<EOF
Использование: $0 [-f targets_file] [-d alert_days] [-q]

Опции:
  -f FILE   Путь к файлу целей (по умолчанию: $TARGETS_FILE)
  -d DAYS   Порог оповещения в днях (по умолчанию: $ALERT_DAYS_DEFAULT)
  -q        Тихий режим (только ошибки/алерты)

Переменные окружения:
  TARGETS_FILE, ALERT_DAYS_DEFAULT, MAIL_TO, MAIL_FROM, MAIL_SUBJECT_PREFIX, MAIL_LOCAL_ONLY

Формат файла целей:
  - По одной записи на строку; строки с '#' — комментарии; пустые строки игнорируются
  - Формат: host[:port][,sni=example.com][,days=NN]
    Примеры:
      example.com
      example.com:443
      10.0.0.5:8443,sni=service.example.com
      api.example.com:443,days=15

Коды выхода:
  0 — успех; 1 — есть срабатывания или ошибки
EOF
}

log() {
  if [ "$QUIET" != "true" ]; then
    echo "$@"
  fi
}

warn() {
  printf "%s\n" "$@" 1>&2
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

send_mail() {
  subject="$1"
  to_addr="$2"
  from_addr="$3"
  body="$4"

  # Предпочесть локальную доставку через sendmail, если MAIL_LOCAL_ONLY=true
  if [ "$MAIL_LOCAL_ONLY" = "true" ] && [ -x /usr/sbin/sendmail ]; then
    {
      printf "From: %s\n" "$from_addr"
      printf "To: %s\n" "$to_addr"
      printf "Subject: %s\n" "$subject"
      printf "Content-Type: text/plain; charset=UTF-8\n\n"
      printf "%s\n" "$body"
    } | /usr/sbin/sendmail -t || return 1
    return 0
  fi

  # Иначе пробовать mailx, затем mail, затем sendmail
  if have_cmd mailx; then
    printf "%s" "$body" | mailx -a "From: $from_addr" -s "$subject" "$to_addr" || return 1
    return 0
  fi
  if have_cmd mail; then
    printf "%s" "$body" | mail -a "From: $from_addr" -s "$subject" "$to_addr" || return 1
    return 0
  fi
  if [ -x /usr/sbin/sendmail ]; then
    {
      printf "From: %s\n" "$from_addr"
      printf "To: %s\n" "$to_addr"
      printf "Subject: %s\n" "$subject"
      printf "Content-Type: text/plain; charset=UTF-8\n\n"
      printf "%s\n" "$body"
    } | /usr/sbin/sendmail -t || return 1
    return 0
  fi
  warn "Нет почтового клиента (sendmail/mailx/mail) для отправки оповещений"
  return 1
}

parse_kv() {
  key="$1"; shift
  echo "$@" | awk -v k="$key" -F',' '{
    for (i=1;i<=NF;i++) {
      split($i,a,"=")
      if (a[1]==k) { print a[2]; exit }
    }
  }'
}

parse_hostport() {
  # вход: host:port или host
  in="$1"
  host=$(printf "%s" "$in" | awk -F',' '{print $1}' | awk -F':' '{print $1}')
  port=$(printf "%s" "$in" | awk -F',' '{print $1}' | awk -F':' '{print $2}')
  if [ -z "$port" ]; then port=443; fi
  printf "%s %s\n" "$host" "$port"
}

openssl_fetch_cert() {
  host="$1"; port="$2"; sni="$3"
  # Запрашиваем листовой сертификат и передаём его в x509
  # shellcheck disable=SC3037
  if [ -n "$sni" ]; then
    echo | openssl s_client -servername "$sni" -connect "$host:$port" -showcerts 2>/dev/null |
      awk 'BEGIN{incrt=0} /BEGIN CERTIFICATE/{incrt=1} incrt{print} /END CERTIFICATE/{exit}'
  else
    echo | openssl s_client -connect "$host:$port" -showcerts 2>/dev/null |
      awk 'BEGIN{incrt=0} /BEGIN CERTIFICATE/{incrt=1} incrt{print} /END CERTIFICATE/{exit}'
  fi
}

cert_enddate_epoch() {
  # Читает PEM-сертификат из stdin, выводит notAfter в секундах эпохи
  openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//' |
    while IFS= read -r line; do
      if date -d "$line" +%s >/dev/null 2>&1; then
        date -d "$line" +%s
      else
        # macOS/BSD fallback: try -j -f
        if date -j -f "%b %e %T %Y %Z" "$line" +%s 2>/dev/null; then
          date -j -f "%b %e %T %Y %Z" "$line" +%s
        else
          echo ""; exit 1
        fi
      fi
    done
}

calc_days_left() {
  end_epoch="$1"
  now_epoch=$(date +%s)
  if [ -z "$end_epoch" ]; then
    echo ""; return 1
  fi
  if [ "$end_epoch" -lt "$now_epoch" ]; then
    echo 0
    return 0
  fi
  seconds_left=$(( end_epoch - now_epoch ))
  days_left=$(( (seconds_left + 86399) / 86400 ))
  echo "$days_left"
}

alert_block=""
had_error=0

while getopts ":f:d:qh" opt; do
  case "$opt" in
    f) TARGETS_FILE="$OPTARG" ;;
    d) ALERT_DAYS_DEFAULT="$OPTARG" ;;
    q) QUIET="true" ;;
    h) usage; exit 0 ;;
    :) warn "Option -$OPTARG requires an argument"; usage; exit 1 ;;
    \?) warn "Unknown option: -$OPTARG"; usage; exit 1 ;;
  esac
done

if [ ! -r "$TARGETS_FILE" ]; then
  warn "Targets file not readable: $TARGETS_FILE"
  exit 1
fi

log "Using targets file: $TARGETS_FILE"
log "Default alert threshold: $ALERT_DAYS_DEFAULT days"

line_no=0
while IFS= read -r raw || [ -n "$raw" ]; do
  line_no=$(( line_no + 1 ))
  # Обрезка пробелов
  line=$(echo "$raw" | sed 's/^\s\+//;s/\s\+$//')
  # Пропуск комментариев и пустых строк
  case "$line" in
    "#"*|"") continue ;;
  esac

  base=$(echo "$line" | awk -F',' '{print $1}')
  kvs=$(echo "$line" | cut -s -d',' -f2-)
  set -- $(parse_hostport "$base")
  host="$1"; port="$2"
  sni="$(parse_kv sni "$kvs")"
  override_days="$(parse_kv days "$kvs")"
  threshold_days="${override_days:-$ALERT_DAYS_DEFAULT}"

  if [ -z "$sni" ]; then sni="$host"; fi

  log "Checking $host:$port (SNI=$sni, threshold=${threshold_days}d)"

  pem=$(openssl_fetch_cert "$host" "$port" "$sni" || true)
  if [ -z "$pem" ]; then
    had_error=1
    msg="ERROR: $host:$port (SNI=$sni) — failed to fetch certificate"
    warn "$msg"
    alert_block="$alert_block\n$msg"
    continue
  fi

  end_epoch=$(printf "%s" "$pem" | cert_enddate_epoch || true)
  if [ -z "$end_epoch" ]; then
    had_error=1
    msg="ERROR: $host:$port — could not parse cert end date"
    warn "$msg"
    alert_block="$alert_block\n$msg"
    continue
  fi

  days_left=$(calc_days_left "$end_epoch" || echo "")
  if [ -z "$days_left" ]; then
    had_error=1
    msg="ERROR: $host:$port — failed to compute days left"
    warn "$msg"
    alert_block="$alert_block\n$msg"
    continue
  fi

  not_after_readable=$(printf "%s" "$pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  subject=$(printf "%s" "$pem" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject=//')
  issuer=$(printf "%s" "$pem" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//')

  if [ "$days_left" -le "$threshold_days" ]; then
    had_error=1
    msg="ALERT: $host:$port — $days_left day(s) left (notAfter: $not_after_readable)\n  Subject: $subject\n  Issuer:  $issuer"
    warn "$msg"
    alert_block="$alert_block\n$msg"
  else
    log "OK: $host:$port — $days_left day(s) left (notAfter: $not_after_readable)"
  fi
done < "$TARGETS_FILE"

if [ -n "$alert_block" ]; then
  subject="$MAIL_SUBJECT_PREFIX Cert alerts on $(hostname)"
  body="Certificate status from $(hostname) at $(date -Is)\n$alert_block\n"
  # Try to send; do not fail hard if mailer missing
  send_mail "$subject" "$MAIL_TO" "$MAIL_FROM" "$body" || warn "Failed to send alert email"
fi

exit "$had_error"


