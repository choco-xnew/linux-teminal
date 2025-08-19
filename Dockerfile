FROM alpine:latest

# Install dependencies (similar to Ubuntu version)
RUN apk update && apk add --no-cache \
    sudo curl ffmpeg git nano python3 py3-pip \
    screen openssh unzip wget bash \
    musl-locales musl-locales-lang \
    nodejs npm

# Set locale (Alpine uses musl, so use LANG env directly)
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Configure SSH
RUN mkdir -p /run/sshd /var/run/sshd && \
    ssh-keygen -A && \
    echo 'Port 2222\n\
PermitRootLogin yes\n\
PasswordAuthentication yes\n\
ChallengeResponseAuthentication no\n\
X11Forwarding yes\n\
PrintMotd no\n\
AcceptEnv LANG LC_*\n\
Subsystem sftp /usr/lib/ssh/sftp-server\n\
ClientAliveInterval 60\n\
ClientAliveCountMax 3' > /etc/ssh/sshd_config && \
    echo 'root:kaal' | chpasswd

# Create a small web root
RUN mkdir -p /web && \
    echo '<h1>🚀 Alpine Docker VPS is running!</h1>' > /web/index.html

# Startup script (Serveo tunnel + Python server)
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Start SSH\n\
/usr/sbin/sshd -D &\n\
\n\
# Start Serveo tunnel and show connection info\n\
echo "Starting Serveo tunnel to serveo.net..."\n\
ssh -o StrictHostKeyChecking=no -R 0:localhost:2222 serveo.net -p 2222 > serveo.log 2>&1 &\n\
sleep 5\n\
\n\
# Display connection information\n\
echo -e "\n\033[1;36m=== SERVEO SSH CONNECTION INFO ===\033[0m"\n\
cat serveo.log | grep --color=always -E "Forwarding|$"\n\
echo -e "\n\033[1;36mConnect using:\033[0m"\n\
echo -e "\033[1;33mssh root@[serveo-address] -p [serveo-port]\033[0m"\n\
echo -e "\033[1;36mPassword: kaal\033[0m"\n\
echo -e "\033[1;36m================================\033[0m\n"\n\
\n\
# Start tiny Python HTTP server\n\
echo "Starting Python server on port 8000..."\n\
python3 -m http.server 8000 --directory /web &\n\
\n\
# Keep container running\n\
tail -f /dev/null' > /start.sh && \
    chmod +x /start.sh

# Expose SSH and HTTP ports
EXPOSE 22 8000

CMD ["/start.sh"]
