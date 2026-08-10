#!/usr/bin/env bash
# Создаёт самоподписанный сертификат для подписи clipstack.
#
# Зачем: TCC (база разрешений macOS) привязывает выданный Универсальный доступ к
# designated requirement приложения. У ad-hoc подписи DR завязан на cdhash бинаря, поэтому
# каждая пересборка выглядит для системы как другое приложение и разрешение слетает.
# Сертификат даёт DR вида «этот bundle id + этот сертификат» — он переживает пересборки.
set -euo pipefail

CN="${1:-clipstack-dev}"
KEYCHAIN="${CLIPSTACK_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-certificate -c "$CN" >/dev/null 2>&1; then
	echo "Сертификат '$CN' уже в связке ключей. Нечего делать."
	security find-identity -v -p codesigning | grep "$CN" || true
	exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Расширения задаём конфигом, а не -addext: LibreSSL из /usr/bin его не всегда понимает,
# а скрипт должен работать и без homebrew-openssl в PATH.
cat >"$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3

[dn]
CN = $CN

[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> генерирую ключ и сертификат"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf"

# Явные PBE-алгоритмы: OpenSSL 3 по умолчанию шифрует p12 так, что security import
# его не читает. SHA1-3DES понимают обе стороны.
# Пароль обязательно НЕПУСТОЙ: с пустым OpenSSL 3 считает MAC способом, который security
# отвергает как «wrong password». Пароль одноразовый, живёт только внутри этого запуска —
# в связке ключей ключ лежит уже расшифрованным.
echo "==> пакую в PKCS#12"
P12PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -out "$WORK/bundle.p12" \
	-inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
	-passout "pass:$P12PASS"

echo "==> импорт в связку ключей"
# -T разрешает codesign пользоваться приватным ключом без отдельного запроса.
security import "$WORK/bundle.p12" -k "$KEYCHAIN" -P "$P12PASS" \
	-T /usr/bin/codesign -T /usr/bin/security

echo "==> помечаю доверенным для подписи кода"
# Без доверия codesign откажется брать сертификат. Здесь macOS покажет диалог с запросом
# пароля от учётки — это ожидаемо и делается один раз.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" || {
	echo "!! Не удалось пометить сертификат доверенным (нужен пароль в диалоге)."
	echo "   Повтори вручную:"
	echo "   security add-trusted-cert -r trustRoot -p codeSign -k \"$KEYCHAIN\" <файл сертификата>"
	exit 1
}

echo "==> проверка"
security find-identity -v -p codesigning | grep "$CN" \
	&& echo "Готово. Теперь Scripts/build-app.sh подпишет '$CN'."
