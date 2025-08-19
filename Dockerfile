FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies using apt
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    sudo curl ffmpeg git nano screen openssh-server unzip wget autossh \
    python3 python3-pip python3-venv \
    build-essential python3-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev \
    libxml2-dev libxslt-dev \
    tzdata \
    # Install Node.js (from NodeSource)
    ca-certificates gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_21.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up locale
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    # Set Python virtual environment path
    VENV_PATH="/opt/venv"

# Create and activate Python virtual environment
RUN python3 -m venv $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"

# Configure SSH for port 2222
RUN mkdir -p /run/sshd /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICzL3NsXdtsrwCtKU3anh+qKynaC3wRDg3oeVaHybWk8 admin@chocox911' > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    # Configure SSH server
    echo 'Port 2222' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PidFile /run/sshd.pid' >> /etc/ssh/sshd_config && \
    echo 'GatewayPorts yes' >> /etc/ssh/sshd_config && \
    echo 'ClientAliveInterval 30' >> /etc/ssh/sshd_config && \
    echo 'ClientAliveCountMax 3' >> /etc/ssh/sshd_config && \
    # Set root password
    echo 'root:choco' | chpasswd && \
    # Generate SSH host keys if they don't exist
    ssh-keygen -A

# Create web content
RUN mkdir -p /var/www && \
    echo "<html><body><h1>Python HTTP Server Working!</h1><p>Direct SSH access available</p></body></html>" > /var/www/index.html

# Copy requirements.txt if it exists (create a sample one if not)
RUN echo "Flask==2.3.3\nrequests==2.31.0\npillow==10.0.0" > /tmp/requirements.txt

# Install Python packages
RUN pip install --upgrade pip && \
    pip install -r /tmp/requirements.txt

# Create startup script with autossh tunneling
RUN printf '#!/bin/bash\n\
export PORT=${PORT:-8000}\n\
mkdir -p /root/.ssh\n\
chmod 700 /root/.ssh\n\
chmod 600 /root/.ssh/authorized_keys\n\
# Ensure SSH directory exists and has correct permissions\n\
mkdir -p /run/sshd\n\
chmod 755 /run/sshd\n\
# Start Python HTTP server\n\
cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
HTTP_PID=$!\n\
# Start SSH server with debug logging\n\
/usr/sbin/sshd -D -d -e &\n\
SSH_PID=$!\n\
# Wait a moment for SSH to start\n\
sleep 3\n\
# Autossh reverse SSH tunnel with fixed alias\n\
echo "Setting up autossh tunnel to serveo.net..."\n\
autossh -M 0 -o "StrictHostKeyChecking=no" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -R render:2222:localhost:2222 serveo.net &\n\
TUNNEL_PID=$!\n\
cat <<EOF\n\
======================================\n\
SERVICES STARTED SUCCESSFULLY!\n\
======================================\n\
HTTP Server: http://localhost:$PORT\n\
Python virtual environment: $VENV_PATH\n\
Node.js version: $(node -v)\n\
Python version: $(python3 --version)\n\
SSH Connection Details:\n\
- Connect directly to container IP:2222\n\
- OR via Serveo public tunnel:\n\
  ssh -p 2222 -J serveo.net root@render\n\
- Username: root\n\
- Password: choco\n\
- SSH Key: Termius key installed\n\
======================================\n\
EOF\n\
# Function to check if process is running\n\
is_process_running() {\n\
    kill -0 $1 2>/dev/null\n\
    return $?\n\
}\n\
cleanup() {\n\
    echo "Cleaning up processes..."\n\
    kill $HTTP_PID $SSH_PID $TUNNEL_PID 2>/dev/null\n\
    exit 0\n\
}\n\
trap cleanup SIGINT SIGTERM\n\
while true; do\n\
    if ! is_process_running $HTTP_PID; then\n\
        echo "HTTP server died, restarting..."\n\
        cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
        HTTP_PID=$!\n\
    fi\n\
    if ! is_process_running $SSH_PID; then\n\
        echo "SSH server died, restarting..."\n\
        /usr/sbin/sshd -D -d -e &\n\
        SSH_PID=$!\n\
        sleep 2\n\
    fi\n\
    if ! is_process_running $TUNNEL_PID; then\n\
        echo "Autossh tunnel died, restarting..."\n\
        autossh -M 0 -o "StrictHostKeyChecking=no" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -R render:2222:localhost:2222 serveo.net &\n\
        TUNNEL_PID=$!\n\
    fi\n\
    sleep 10\n\
done' > /start && chmod 755 /start

# Create log directory
RUN mkdir -p /var/log

# Health check
HEALTHCHECK --interval=30s --timeout=10s \
    CMD curl -fs http://localhost:${PORT:-8000}/ || exit 1

EXPOSE 8000 2222
CMD ["/start"]
