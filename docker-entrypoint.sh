#!/bin/bash
# filepath: docker-entrypoint.sh
set -e

echo "Starting TastyIgniter entrypoint script..."

if [ ! -f '/var/www/html/public/index.php' ]; then
    echo "Setting up TastyIgniter application..."

    # Clear existing files
    rm -rf /var/www/html/*

    # Copy application files to web root
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

# Make storage directory writable during runtime
chmod -R 777 /var/www/html/storage
chmod -R 777 /var/www/html/bootstrap/cache

echo "Starting Apache..."
exec "$@"