#!/bin/bash
set -e

echo "Starting TastyIgniter entrypoint script..."

# First-run application setup
if [ ! -f '/var/www/html/public/index.php' ]; then
    echo "Setting up TastyIgniter application... (first start)"

    # Clear existing files EXCEPT the persistent media volume
    # (now safe because media is mounted at different location)
    rm -rf /var/www/html/*

    # Copy application files
    cp -a /usr/src/tastyigniter/. /var/www/html/

    # Create .env file with proper values
    if [ -f "/var/www/html/.env.example" ]; then
        echo "Creating .env file..."
        cp /var/www/html/.env.example /var/www/html/.env

        # Set basic configuration
        sed -i 's/APP_ENV=production/APP_ENV=production/g' /var/www/html/.env
        sed -i 's/APP_DEBUG=true/APP_DEBUG=true/g' /var/www/html/.env
        sed -i 's/APP_URL=http:\/\/localhost/APP_URL=http:\/\/localhost/g' /var/www/html/.env

        # Set database config if provided
        if [ -n "${DB_HOST}" ]; then
            sed -i "s/DB_HOST=.*/DB_HOST=${DB_HOST}/g" /var/www/html/.env
        fi
        if [ -n "${DB_PORT}" ]; then
            sed -i "s/DB_PORT=.*/DB_PORT=${DB_PORT}/g" /var/www/html/.env
        fi
        if [ -n "${DB_DATABASE}" ]; then
            sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/g" /var/www/html/.env
        fi
        if [ -n "${DB_USERNAME}" ]; then
            sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/g" /var/www/html/.env
        fi
        if [ -n "${DB_PASSWORD}" ]; then
            sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/g" /var/www/html/.env
        fi
    fi

    # Set proper permissions
    echo "Setting file permissions..."
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html/storage
    chmod -R 755 /var/www/html/bootstrap/cache

    # Generate key and run installation
    cd /var/www/html/
    php artisan key:generate --force

    # Run installation if database is configured
    if [ -n "${DB_HOST}" ] && [ -n "${DB_DATABASE}" ] && [ -n "${DB_USERNAME}" ]; then
        echo "Waiting for database to be ready..."
        max_retries=30
        try=0
        until php -r "new PDO('mysql:host=${DB_HOST};dbname=${DB_DATABASE}', '${DB_USERNAME}', '${DB_PASSWORD}');" 2>/dev/null; do
            try=$((try+1))
            if [ $try -ge $max_retries ]; then
                echo "Database not reachable after $max_retries attempts. Continuing without database setup."
                break
            fi
            echo "Retrying database connection ($try/$max_retries)..."
            sleep 2
        done

        echo "Running TastyIgniter installation..."
        php artisan igniter:install --no-interaction
    else
        echo "Database environment variables not set. Manual setup will be required."
    fi
fi

# Configure Apache
echo "Setting correct DocumentRoot..."
sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/html/public|g' /etc/apache2/sites-available/000-default.conf
echo '<Directory "/var/www/html/public">' > /etc/apache2/conf-available/public-dir.conf
echo '    AllowOverride All' >> /etc/apache2/conf-available/public-dir.conf
echo '    Require all granted' >> /etc/apache2/conf-available/public-dir.conf
echo '</Directory>' >> /etc/apache2/conf-available/public-dir.conf
a2enconf public-dir

# ================== PERSISTENT MEDIA SETUP ==================
# (Runs on EVERY startup)
echo "Configuring persistent media storage..."

# 1. Create symlink from app location to persistent volume
#    - Remove if exists as directory (first run after migration)
#    - Skip if already a symlink
mkdir -p /var/www/html/storage/app/public
if [ -d "/var/www/html/storage/app/public/media" ]; then
    rm -rf /var/www/html/storage/app/public/media
fi
if [ ! -L "/var/www/html/storage/app/public/media" ]; then
    ln -sf /var/www/persistent-media /var/www/html/storage/app/public/media
fi

# 2. Create required media directories in PERSISTENT location
MEDIA_DIRS=(
    "/var/www/persistent-media/uploads"
    "/var/www/persistent-media/attachments"
)

for dir in "${MEDIA_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "Creating media directory: $dir"
        mkdir -p "$dir"
    fi
    chown www-data:www-data "$dir"
    chmod 777 "$dir"
done
# ================== END PERSISTENT MEDIA SETUP ==================

# Make storage directory writable during runtime
chmod -R 777 /var/www/html/storage
chmod -R 777 /var/www/html/bootstrap/cache

echo "Starting Apache..."
exec "$@"