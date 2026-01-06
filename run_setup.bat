@echo off
echo ===== Setting up Flask Systemd Service =====
echo.
gcloud compute ssh lightnet-server --zone=africa-south1-a --command="chmod +x /tmp/setup_flask_service.sh"
gcloud compute ssh lightnet-server --zone=africa-south1-a --command="sudo bash /tmp/setup_flask_service.sh"
echo.
echo ===== Setup Complete =====
pause
