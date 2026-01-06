@echo off
echo ===== Verifying Systemd Service Setup =====
echo.
echo 1. Checking if service file exists...
gcloud compute ssh lightnet-server --zone=africa-south1-a --command="ls -la /etc/systemd/system/flask-api.service"
echo.
echo 2. Checking service status...
gcloud compute ssh lightnet-server --zone=africa-south1-a --command="sudo systemctl status flask-api --no-pager"
echo.
echo 3. Checking if service is enabled (auto-start on boot)...
gcloud compute ssh lightnet-server --zone=africa-south1-a --command="sudo systemctl is-enabled flask-api"
echo.
echo 4. Testing API endpoint...
curl http://34.35.97.197:5000/fetch_recent_payments
echo.
echo ===== Verification Complete =====
pause
