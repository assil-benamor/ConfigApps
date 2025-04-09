#!/bin/bash

# Ensure the script runs non-interactively
export DEBIAN_FRONTEND=noninteractive

# Configurable variables
GITHUB_REPO="https://github.com/assil-benamor/ShinyAppTest.git"
DOMAIN_NAME="test4.assilbenamor.com"  # Change this to your domain
CERTBOT_EMAIL="massilbenamor@gmail.com"         # Email for Certbot
USE_CERTBOT=0                                  # Set to 1 to use Certbot, 0 to skip

# Log file
LOG_FILE="/tmp/firstboot.log"

# Capture start time in seconds since epoch
START_TIME=$(date +%s)

# Log script start time
echo "Setup script started at $(date)" >> "$LOG_FILE"

# 1/ Update and install dependencies
apt-get update
apt-get upgrade -y
apt-get install -y \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libtiff5-dev \
    libpng-dev \
    libjpeg-dev \
    libglu-dev \
    zlib1g-dev \
    gdebi-core \
    git

# 2/ Install R
apt update -qq
apt install -y --no-install-recommends software-properties-common dirmngr
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
apt install -y --no-install-recommends r-base

# 3/ Install R packages (excluding httr, rvest, readODS)
sudo su - -c "R -e \"install.packages(c('shiny', 'shinyjs', 'dplyr', 'DT', 'writexl'), repos='http://cran.rstudio.com/', dependencies=TRUE, Ncpus=2)\""

# 4/ Install Shiny Server
wget -q https://download3.rstudio.org/ubuntu-20.04/x86_64/shiny-server-1.5.23.1030-amd64.deb
gdebi -n shiny-server-1.5.23.1030-amd64.deb

# 5/ Allow traffic on port 3838
ufw allow 3838

# 6/ Create a folder for the Shiny app
mkdir -p /srv/shiny-server/myapp
chown -R shiny:shiny /srv/shiny-server/myapp

# 7/ Fetch files from GitHub repo and move them to the app directory
git clone "$GITHUB_REPO" /tmp/shinyapp_repo
mv /tmp/shinyapp_repo/* /srv/shiny-server/myapp/
rm -rf /tmp/shinyapp_repo
chown -R shiny:shiny /srv/shiny-server/myapp
chmod -R 755 /srv/shiny-server/myapp

# 8/ Install and run Nginx
apt-get update
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx
ufw allow 80  # Allow HTTP traffic
ufw allow 443 # Allow HTTPS traffic

# 9/ Configure Nginx for the domain
cat << EOF > /etc/nginx/sites-available/sanctionchecker.conf
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://127.0.0.1:3838/;
        proxy_redirect http://127.0.0.1:3838/ \$scheme://\$host/;

        # Ensures Shiny's websockets and reactive log streaming work properly:
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 20d;
        
        # Pass additional headers
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
    }
}
EOF

# 10/ Enable the new Nginx configuration
rm -f /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/sanctionchecker.conf /etc/nginx/sites-enabled/
systemctl reload nginx

# 11/ Install Certbot (only if USE_CERTBOT is 1)
if [ "$USE_CERTBOT" -eq 1 ]; then
    apt-get install -y certbot python3-certbot-nginx
fi

# 12/ Obtain and install SSL certificate (only if USE_CERTBOT is 1)
if [ "$USE_CERTBOT" -eq 1 ]; then
    certbot --nginx \
        -d "$DOMAIN_NAME" \
        --non-interactive \
        --agree-tos \
        -m "$CERTBOT_EMAIL"
fi

# Capture end time in seconds since epoch
END_TIME=$(date +%s)

# Calculate runtime in seconds
RUNTIME=$((END_TIME - START_TIME))

# Convert runtime to human-readable format (minutes and seconds)
MINUTES=$((RUNTIME / 60))
SECONDS=$((RUNTIME % 60))

# Log completion and runtime
echo "Setup script completed at $(date)" >> "$LOG_FILE"
echo "Total runtime: $RUNTIME seconds ($MINUTES minutes and $SECONDS seconds)" >> "$LOG_FILE"