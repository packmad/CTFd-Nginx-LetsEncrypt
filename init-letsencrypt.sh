#!/bin/bash
set -euo pipefail

if ! docker compose version >/dev/null 2>&1; then
  echo 'Error: docker compose is not installed.' >&2
  exit 1
fi

# # # # # # # # # # # # # # # # 
# CUSTOMIZABLE CONFIGURATION  #
# # # # # # # # # # # # # # # # 
email="simone.aonzo@eurecom.fr" # You may want to add a valid email address, just to be cool.
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits on LetsEncrypt.
domains=(introsec.s3.eurecom.fr) # Your CTFd domain(s), separated with space.
rsa_key_size=4096
data_path="./data/certbot"
tls_src="./tls"
primary_domain="${domains[0]}"

if [ ${#domains[@]} -gt 0 ]; then
    echo "Inserting the domain into nginx/app.conf..."
    sed -i "s/ctfd.siahaan.org/${primary_domain}/" "./data/nginx/app.conf"
else
    echo "Please enter at least 1 domain on 'domains' variable" >&2
    exit 1
fi

if [ -d "$data_path/conf/live/$primary_domain" ]; then
  read -p "Existing certificate data found for $primary_domain. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit 0
  fi
fi

tls_file_ok() {
  local file="$1"
  local marker="$2"
  [ -s "$file" ] && grep -q "$marker" "$file"
}

install_tls_params() {
  local dest_options="$data_path/conf/options-ssl-nginx.conf"
  local dest_dh="$data_path/conf/ssl-dhparams.pem"
  local src_options="$tls_src/options-ssl-nginx.conf"
  local src_dh="$tls_src/ssl-dhparams.pem"

  if ! tls_file_ok "$src_options" "ssl_protocols" || ! tls_file_ok "$src_dh" "BEGIN DH PARAMETERS"; then
    echo "Error: vendored TLS files missing or invalid under $tls_src" >&2
    exit 1
  fi

  mkdir -p "$data_path/conf" "$data_path/www" || true

  if tls_file_ok "$dest_options" "ssl_protocols" && tls_file_ok "$dest_dh" "BEGIN DH PARAMETERS"; then
    echo "### TLS parameters already present and valid."
    return 0
  fi

  echo "### Installing recommended TLS parameters from $tls_src ..."
  if cp "$src_options" "$dest_options" 2>/dev/null && cp "$src_dh" "$dest_dh" 2>/dev/null; then
    :
  else
    # data/certbot/conf is often root-owned after certbot runs
    docker compose run --rm --no-deps --entrypoint sh certbot -c \
      "cat > /etc/letsencrypt/options-ssl-nginx.conf" < "$src_options"
    docker compose run --rm --no-deps --entrypoint sh certbot -c \
      "cat > /etc/letsencrypt/ssl-dhparams.pem" < "$src_dh"
  fi

  if ! tls_file_ok "$dest_options" "ssl_protocols" || ! tls_file_ok "$dest_dh" "BEGIN DH PARAMETERS"; then
    echo "Error: failed to install valid TLS parameters into $data_path/conf" >&2
    exit 1
  fi
}

wait_for_service_healthy() {
  local service="$1"
  local timeout_s="${2:-180}"
  local elapsed=0
  echo "### Waiting for $service to become healthy (timeout ${timeout_s}s) ..."
  while [ "$elapsed" -lt "$timeout_s" ]; do
    local status
    status="$(docker compose ps --status running --format '{{.Health}}' "$service" 2>/dev/null || true)"
    if [ "$status" = "healthy" ]; then
      echo "### $service is healthy."
      return 0
    fi
    # Services without a healthcheck report an empty health field when running
    if [ -z "$status" ]; then
      if docker compose ps --status running --format '{{.Service}}' | grep -qx "$service"; then
        # Confirm healthcheck is defined; if not, treat running as ready
        if ! docker compose config | grep -A20 "^  ${service}:" | grep -q "healthcheck:"; then
          echo "### $service is running (no healthcheck)."
          return 0
        fi
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "Error: timed out waiting for $service to become healthy" >&2
  docker compose ps -a
  docker compose logs --tail 50 "$service" || true
  exit 1
}

install_tls_params

echo "### Creating dummy certificate for $primary_domain ..."
path="/etc/letsencrypt/live/$primary_domain"
docker compose run --rm --no-deps --entrypoint sh certbot -c "\
  mkdir -p '$path' && \
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1 \
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'"
echo

echo "### Starting database and cache ..."
docker compose up --force-recreate -d db cache
wait_for_service_healthy db
wait_for_service_healthy cache

echo "### Starting CTFd ..."
docker compose up --force-recreate -d ctfd
wait_for_service_healthy ctfd
echo

echo "### Starting nginx ..."
docker compose up --force-recreate -d nginx
echo

echo "### Deleting dummy certificate for $primary_domain ..."
docker compose run --rm --no-deps --entrypoint sh certbot -c "\
  rm -Rf /etc/letsencrypt/live/$primary_domain && \
  rm -Rf /etc/letsencrypt/archive/$primary_domain && \
  rm -Rf /etc/letsencrypt/renewal/$primary_domain.conf"
echo

echo "### Requesting Let's Encrypt certificate for ${domains[*]} ..."
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

staging_arg=""
if [ "$staging" != "0" ]; then staging_arg="--staging"; fi

docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Starting certbot renewer and reloading nginx ..."
docker compose up -d certbot
docker compose exec nginx nginx -s reload
echo "### Done."
