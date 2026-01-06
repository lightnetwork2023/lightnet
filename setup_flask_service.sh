#!/bin/bash
set -e

echo "Creating systemd service file..."
sudo tee /etc/systemd/system/flask-api.service > /dev/null <<'EOF'
[Unit]
Description=Flask API Service for LightNet
After=network.target mysql.service
Requires=mysql.service

[Service]
Type=simple
User=lightnetwork2023
WorkingDirectory=/home/lightnetwork2023
Environment="PATH=/usr/bin:/usr/local/bin"
ExecStart=/usr/bin/python3 /home/lightnetwork2023/app.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/flask-api.log
StandardError=append:/var/log/flask-api-error.log
StartLimitInterval=200
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 /etc/systemd/system/flask-api.service
sudo pkill -f app.py || true
sleep 2
sudo systemctl daemon-reload
sudo systemctl enable flask-api
sudo systemctl start flask-api
sudo systemctl status flask-api --no-pager

echo ""
echo "Setup complete! Flask is now managed by systemd."
echo "Commands: sudo systemctl [status|restart|stop|start] flask-api"
