
from flask import Flask, request, jsonify
import socket
import subprocess
import re
from flask_cors import CORS
import mysql.connector
import random
import string
import json
import requests
import logging
import urllib.parse
import uuid
import os
import threading
import firebase_admin
from firebase_admin import credentials, firestore, auth as firebase_auth

# Import MikroTik authentication helper
try:
    from mikrotik_auth_helper import authenticate_user_via_mikrotik
    MIKROTIK_AUTH_AVAILABLE = True
except ImportError:
    MIKROTIK_AUTH_AVAILABLE = False

# Configure logging
logging.basicConfig(
    filename='/var/log/flask_callback.log',
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
from datetime import datetime, timedelta
from decimal import Decimal 

app = Flask(__name__)
# CORS enabled for direct port 5000 access (hotspot pages)
# Nginx also adds CORS for domain access, but it's safe
CORS(app)

# Initialize Firebase Admin SDK
try:
    cred = credentials.Certificate('/root/lightnetwork-firebase-key.json')
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    logging.info("Firebase Admin SDK initialized successfully")
except Exception as e:
    logging.error(f"Failed to initialize Firebase Admin SDK: {e}")
    db = None

# Technician single-user generation (see /generateoneuser)
TECHNICIAN_ONE_USER_MAX_PER_DAY = 10
TECHNICIAN_ONE_USER_SPEED = '10M/10M'
TECHNICIAN_ONE_USER_LOCATION = 'general'
# duration_key -> session timeout in seconds (3 hours, 1 day)
TECHNICIAN_ONE_USER_DURATIONS_SEC = {
    '3h': 3 * 3600,
    '1d': 24 * 3600,
}

@app.after_request
def add_csp_header(response):
    csp_policy = (
        "default-src 'self' http://lightnet.lightnetwork.pro:5000; "  # Add domain here
        "connect-src *; " 
#        "connect-src 'self' http://lightnet.lightnetwork.pro:5000; "
        "script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline'"
    )
    response.headers["Content-Security-Policy"] = csp_policy
    return response

# MySQL connection details
db_config = {
    'user': 'radius',
    'password': 'ROCKY221122',
    'host': 'localhost',
    'database': 'radius'
}



#   AZAMPAY START

FIREBASE_LOCATION_FUNCTION_URL = 'https://us-central1-lightnet-d2de9.cloudfunctions.net/storeUserLocation'
FIREBASE_PAYMENT_FUNCTION_URL = 'https://storepaymentdata-3vxbatgzgq-uc.a.run.app'

AZAM_CLIENT_ID = 'c7b6bda0-9a3f-47fb-b365-1110dfc37089'
AZAM_CLIENT_SECRET = 'EsOPLBAfwnLGCQUHOqjMaTqXm/nPv4A8o0WndaEZ4yJ9oJYLkVgPHeQvKPKA2exyvWEAnFL0fBipGq1Qbll6ePoPNfYdsIxYGd5g9UhyK1l8ytGnS3XQj6GUjCfo0J35sb0wgdFwpruktQ2a9SXdKMkuaCtjHPesNHCqPtoy9fUZmabAh7Igi5ZSA2UlTP8WQjaXmaoYEn8aJ1AQxCIEcaIo+DijH7w4hsCmoVWQTHnfpuYDrz3ndpE0eAPRfP381UBxNPuuedtckpTILuGtvRPKgxMAdQh/Lf38tlNnedsSOXm1aZZFa3Vgm8N+Epk338gspvc1syAmOmnUtAFCQqShiUrgiA8SZqzYerMvGWAteprO+B89l2PdL2LXjYcbVyyyGiptCoKEsCaHIRgitNydEMYsEfHhlygEvMCuBqMzWrPlJgugeGD0GlhNW1gR9iq2GLQzRHYwfrSJeFBo1oQb0frIS7tBHy5WisaDJtJalOWOmEy5UuLAVSg8PHVXJ94yOEA9mdg9x4HV0x+bA5JSi0+29tVC59HPly+N9BvsYVRIGWsqW82Ki3OOpZuRtc7O4/YfhrNplTxBBCv6+SDqF5bCKJpNwXKV9t9peAFe39Jy18DMnZ8WnmYMKh4FP2YQUfE4XWnoXhPuRswSw6eRevNiYIYEZbP6YsLPlNY='

# Token caching
ACCESS_TOKEN = None
TOKEN_EXPIRY = None

def resolve_azampay_ip():
    """
    Manually resolve AzamPay IP using external DNS when system DNS fails
    """
    hostname = 'authenticator.azampay.co.tz'
    
    # Try system DNS first
    try:
        ip = socket.gethostbyname(hostname)
        print(f"[DNS] System resolved: {hostname} -> {ip}")
        return None  # Return None if system DNS works (use hostname)
    except socket.gaierror:
        print(f"[DNS] System DNS failed for {hostname}")
    
    # Try manual DNS resolution using nslookup
    dns_servers = ['8.8.8.8', '1.1.1.1', '208.67.222.222']
    
    for dns_server in dns_servers:
        try:
            result = subprocess.run(
                ['nslookup', hostname, dns_server], 
                capture_output=True, 
                text=True, 
                timeout=10
            )
            
            if result.returncode == 0:
                # Extract IP from nslookup output
                lines = result.stdout.split('\n')
                for line in lines:
                    if 'Address:' in line and dns_server not in line:
                        ip_match = re.search(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b', line)
                        if ip_match:
                            ip = ip_match.group()
                            print(f"[DNS] Manual resolved via {dns_server}: {hostname} -> {ip}")
                            return ip
        except Exception as e:
            print(f"[DNS] Failed with {dns_server}: {e}")
            continue
    
    print(f"[DNS] All resolution attempts failed")
    return None

def get_access_token():
    global ACCESS_TOKEN, TOKEN_EXPIRY
    
        
    # Prepare headers to match Postman exactly (UNCHANGED)
    headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'LightNet-Server/1.0'
    }
    
    # Prepare payload (UNCHANGED)
    payload = {
        'appName': 'lightnet',
        'clientId': AZAM_CLIENT_ID,
        'clientSecret': AZAM_CLIENT_SECRET
    }
    
    print(f"[TOKEN] Requesting new access token...")
    
    # Try original URL first
    urls_to_try = ['https://authenticator.azampay.co.tz/AppRegistration/GenerateToken']
    
    # Add IP-based URL as fallback if DNS resolution provides an IP
    resolved_ip = resolve_azampay_ip()
    if resolved_ip:
        ip_url = f'https://{resolved_ip}/AppRegistration/GenerateToken'
        urls_to_try.append(ip_url)
        # Add Host header for IP-based requests
        headers['Host'] = 'authenticator.azampay.co.tz'
    
    # Try each URL
    for attempt, url in enumerate(urls_to_try):
        try:
            print(f"[TOKEN] Attempt {attempt + 1}: {url}")
            
            # Use exact same request structure as original (UNCHANGED)
            response = requests.post(
                url,
                data=json.dumps(payload),  # Same as original
                headers=headers,           # Same as original  
                timeout=30,
                verify=True
            )
            
            print(f"[TOKEN] Status: {response.status_code}")
            
            if response.status_code == 200:
                response_data = response.json()
                ACCESS_TOKEN = response_data['data']['accessToken']
                
                # Parse expiry time from response (UNCHANGED)
                if 'expire' in response_data['data']:
                    expire_str = response_data['data']['expire']
                    try:
                        TOKEN_EXPIRY = datetime.fromisoformat(expire_str.replace('Z', '+00:00'))
                    except ValueError:
                        TOKEN_EXPIRY = datetime.now() + timedelta(hours=1)
                else:
                    TOKEN_EXPIRY = datetime.now() + timedelta(hours=1)
                
                print(f"[TOKEN] ? Success: {ACCESS_TOKEN[:20]}...")
                return ACCESS_TOKEN
            else:
                print(f"[TOKEN] ? Failed: {response.status_code} - {response.text}")
                
        except requests.exceptions.ConnectionError as e:
            error_str = str(e).lower()
            if "name resolution" in error_str:
                print(f"[TOKEN] ? DNS error with {url}: {str(e)}")
                continue  # Try next URL
            else:
                print(f"[TOKEN] ? Connection error: {str(e)}")
                if attempt == len(urls_to_try) - 1:  # Last attempt
                    raise
        except requests.exceptions.RequestException as e:
            print(f"[TOKEN] ? Request error: {str(e)}")
            if attempt == len(urls_to_try) - 1:  # Last attempt
                raise
        except Exception as e:
            print(f"[TOKEN] ? Unexpected error: {str(e)}")
            if attempt == len(urls_to_try) - 1:  # Last attempt
                raise
    
    # If we get here, all attempts failed
    raise Exception("All token generation attempts failed")

def convert_decimals(obj):
    """
    Recursively convert Decimal objects to float for JSON serialization.
    Handles dicts, lists, and individual values.
    """
    if isinstance(obj, list):
        return [convert_decimals(item) for item in obj]
    elif isinstance(obj, dict):
        return {key: convert_decimals(value) for key, value in obj.items()}
    elif isinstance(obj, Decimal):
        return float(obj)
    else:
        return obj

def _async_firestore_sync(payment_data):
    """
    Background worker - runs in separate thread.
    Fire-and-forget - no retries, logs only.
    Main callback has already returned by the time this runs.
    """
    try:
        response = requests.post(
            FIREBASE_PAYMENT_FUNCTION_URL,
            json=payment_data,
            timeout=2  # Short timeout - don't wait long
        )
        if response.status_code == 200:
            print(f"? Firestore: {payment_data.get('location')} - TZS {payment_data.get('amount')}")
        else:
            print(f"?? Firestore sync failed: {response.status_code}")
    except:
        pass  # Silent failure - don't care

def sync_to_firestore(payment_data):
    """
    Fire-and-forget: Start background sync, return IMMEDIATELY.
    Does NOT block. Does NOT wait. Does NOT retry.
    Callback continues instantly.
    """
    threading.Thread(
        target=_async_firestore_sync,
        args=(payment_data,),
        daemon=True
    ).start()
    # Returns here immediately - thread runs in background

@app.route('/make-payment', methods=['POST'])
def make_payment():
    try:
        # Generate voucher
        voucher_code = str(random.randint(100000000000, 999999999999))
        data = request.json
        location = data['location']
        duration_seconds = data['durationSeconds']
        mac_address = data['mac_address']
        nas_ip = data.get('nas_ip')  # Handle gracefully - may not exist

        # Get access token
        try:
            token = get_access_token()
        except Exception as e:
            return jsonify({
                'success': False,
                'error': 'Payment service unavailable',
                'details': str(e)
            }), 503

        # Prepare payload
        payload = {
            'accountNumber': data['phone'],
            'amount': data['amount'],
            'currency': 'TZS',
            'externalId': str(uuid.uuid4()),
            'provider': data['provider'],
            'additionalProperties': {
                'voucher': voucher_code,
                'duration': duration_seconds,
                'location': location,
                'mac_address': mac_address
            }
        }
        
        # Add nas_ip only if provided
        if nas_ip:
            payload['additionalProperties']['nas_ip'] = nas_ip

        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}',
            'X-API-Key': 'none'
        }

        # Make payment request
        response = requests.post(
           'https://checkout.azampay.co.tz/azampay/mno/checkout',
            json=payload,
            headers=headers,
            timeout=15
        )

        response.raise_for_status()

        return jsonify({
            'success': True,
            'voucherCode': voucher_code,
            'message': 'Payment initiated - use voucher now'
        })

    except requests.exceptions.RequestException as e:
        if 'voucher_code' in locals():
            delete_voucher(voucher_code)
        return jsonify({'success': False, 'error': str(e)}), 500
        
    except Exception as e:
        if 'voucher_code' in locals():
            delete_voucher(voucher_code)
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/get-all-macs-active', methods=['GET'])
def get_all_macs_active():
    """
    Fetch all active sessions from radacct where acctstoptime IS NULL.

    Location is matched using MAC address: vouchers.mac_address = radacct.callingstationid.

    Returns JSON array with fields:
    - mac_address: callingstationid
    - ip_address: framedipaddress (fallbacks handled via COALESCE)
    - location: derived from the most recent voucher for that MAC when available, otherwise 'Unknown'
    - created_at: acctstarttime of the latest active session per MAC
    """
    try:
        print("Connecting to database for fetching active RADIUS sessions...")
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)

        query = """
            /* Latest active session per normalized MAC, plus most recent voucher per normalized MAC */
            SELECT 
                r.callingstationid AS mac_address,
                COALESCE(r.framedipaddress, r.nasipaddress) AS ip_address,
                COALESCE(v.location, 'Unknown') AS location,
                r.acctstarttime AS created_at
            FROM radacct r
            /* Choose the latest active session for each normalized MAC */
            INNER JOIN (
                SELECT 
                    LOWER(REPLACE(REPLACE(REPLACE(callingstationid, ':', ''), '-', ''), '.', '')) AS norm_mac,
                    MAX(acctstarttime) AS max_start
                FROM radacct
                WHERE acctstoptime IS NULL 
                  AND callingstationid IS NOT NULL
                  AND callingstationid <> ''
                GROUP BY norm_mac
            ) la 
              ON la.norm_mac = LOWER(REPLACE(REPLACE(REPLACE(r.callingstationid, ':', ''), '-', ''), '.', ''))
             AND la.max_start = r.acctstarttime
            /* Choose a single, most recent voucher per normalized MAC */
            LEFT JOIN (
                SELECT vv.location,
                       LOWER(REPLACE(REPLACE(REPLACE(vv.mac_address, ':', ''), '-', ''), '.', '')) AS norm_mac
                FROM vouchers vv
                INNER JOIN (
                    SELECT 
                        LOWER(REPLACE(REPLACE(REPLACE(mac_address, ':', ''), '-', ''), '.', '')) AS norm_mac,
                        MAX(COALESCE(updated_at, created_at, first_login_time)) AS max_ts
                    FROM vouchers
                    WHERE mac_address IS NOT NULL AND mac_address <> ''
                    GROUP BY norm_mac
                ) vm 
                  ON vm.norm_mac = LOWER(REPLACE(REPLACE(REPLACE(vv.mac_address, ':', ''), '-', ''), '.', ''))
                 AND COALESCE(vv.updated_at, vv.created_at, vv.first_login_time) = vm.max_ts
            ) v 
              ON v.norm_mac = LOWER(REPLACE(REPLACE(REPLACE(r.callingstationid, ':', ''), '-', ''), '.', ''))
            WHERE r.acctstoptime IS NULL
            ORDER BY r.acctstarttime DESC
        """

        cursor.execute(query)
        active_sessions = cursor.fetchall()

        print(f"? Found {len(active_sessions)} active RADIUS session(s) in radacct.")

        return jsonify(active_sessions), 200

    except Exception as e:
        print(f"? Error while fetching active sessions: {str(e)}")
        return jsonify({"error": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn.is_connected():
            conn.close()
            print("Database connection closed.")

@app.route('/get-all-macs', methods=['GET'])
def get_all_macs():
    """
    Fetches all records from the all_macs table and returns them as JSON.
    """
    try:
        print("Connecting to database for fetching all MACs...")
        conn = mysql.connector.connect(**db_config)
        # Using dictionary=True makes the result easy to convert to JSON
        cursor = conn.cursor(dictionary=True)

        print("Executing SELECT query on all_macs table...")
        cursor.execute("SELECT mac_address, ip_address, location, created_at FROM all_macs")
        
        # Fetch all rows from the query result
        all_macs = cursor.fetchall()
        
        print(f"? Found {len(all_macs)} records in the database.")
        
        # Return the list of devices as a JSON response
        return jsonify(all_macs), 200

    except Exception as e:
        print(f"???? Error while fetching MACs: {str(e)}")
        return jsonify({"error": str(e)}), 500
    finally:
        # Ensure the connection is always closed
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn.is_connected():
            conn.close()
            print("Database connection closed.")


@app.route('/store-mac-snapshot', methods=['POST'])
def store_mac_snapshot():
    try:
        # Get the JSON data from the request body
        data = request.get_json()
        if not data:
            print("? Received empty POST request body")
            return jsonify({"error": "Empty request body"}), 400

        # Extract the lists AND the new location field from the JSON data
        macs = data.get('macs', [])
        ips = data.get('ips', [])
        location = data.get('location', 'Unknown Location') # Get the location

        # The validation logic remains the same
        if not macs or not ips or len(macs) != len(ips):
            print("? Invalid or mismatched MAC/IP parameters in JSON")
            return jsonify({"error": "Invalid or mismatched MAC/IP parameters"}), 400

        print("Connecting to database...")
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        # --- THIS IS THE CRITICAL CHANGE ---
        # Clear only the old data for the specific location sending the update.
        # This prevents one router from deleting the data of another router.
        print(f"Clearing old data for location: {location}...")
        cursor.execute("DELETE FROM all_macs WHERE location = %s", (location,))
        print(f"?? Cleared old data for {location}")

        # The INSERT logic is already correct and will now work as intended.
        for i in range(len(macs)):
            mac = macs[i]
            ip = ips[i]
            if not mac:
                print(f"? Skipping entry with missing MAC: IP={ip}")
                continue
            
            # This INSERT statement correctly includes the location
            cursor.execute(
                "INSERT INTO all_macs (mac_address, ip_address, location) VALUES (%s, %s, %s)",
                (mac, ip, location)
            )
            print(f"? Stored MAC: {mac}, IP: {ip}, Location: {location}")

        conn.commit()
        print(f"? Committed {len(macs)} MAC addresses to database for location: {location}")
        return jsonify({"status": "Stored OK", "count": len(macs), "location": location}), 200

    except Exception as e:
        print(f"???? Error: {str(e)}")
        if 'conn' in locals() and conn.is_connected():
            conn.rollback() # Rollback any partial changes
        return jsonify({"error": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn.is_connected():
            conn.close()
            print("Database connection closed.")

@app.route('/store-mac-active', methods=['POST'])
def store_mac_active():
    try:
        # Get the JSON data from the request body
        data = request.get_json()
        if not data:
            print("? Received empty POST request body")
            return jsonify({"error": "Empty request body"}), 400

        # Extract the lists and the location field from the JSON data
        macs = data.get('macs', [])
        ips = data.get('ips', [])
        location = data.get('location', 'Unknown Location') # Get the location

        # The validation logic remains the same
        if not macs or not ips or len(macs) != len(ips):
            print("? Invalid or mismatched MAC/IP parameters in JSON")
            return jsonify({"error": "Invalid or mismatched MAC/IP parameters"}), 400

        print("Connecting to database...")
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        # --- THIS IS THE CRITICAL CHANGE ---
        # Clear only the old data for the specific location sending the update.
        print(f"Clearing old active data for location: {location}...")
        cursor.execute("DELETE FROM active_macs WHERE location = %s", (location,))
        print(f"?? Cleared old active data for {location}")

        # The INSERT logic is already correct and will now work as intended.
        for i in range(len(macs)):
            mac = macs[i]
            ip = ips[i]
            if not mac:
                print(f"? Skipping entry with missing MAC: IP={ip}")
                continue
            
            # This INSERT statement correctly includes the location
            cursor.execute(
                "INSERT INTO active_macs (mac_address, ip_address, location) VALUES (%s, %s, %s)",
                (mac, ip, location)
            )
            print(f"? Stored MAC: {mac}, IP: {ip}, Location: {location}")

        conn.commit()
        print(f"? Committed {len(macs)} active MAC addresses to database for location: {location}")
        return jsonify({"status": "Stored OK", "count": len(macs), "location": location}), 200

    except Exception as e:
        print(f"???? Error: {str(e)}")
        if 'conn' in locals() and conn.is_connected():
            conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'conn' in locals() and conn.is_connected():
            conn.close()
            print("Database connection closed.")


@app.route('/get_vouchers_by_name', methods=['GET'])
def get_vouchers_by_name():
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)  # Fetch results as dictionaries

        # SQL query to fetch all vouchers where name is not null
        query = """
            SELECT id, username, location, speed_limit, session_timeout, 
                   mac_address, first_login_time, expire_time, used, 
                   created_at, updated_at,name 
            FROM vouchers 
            WHERE name IS NOT NULL
        """
        
        cursor.execute(query)
        vouchers = cursor.fetchall()
        
        if not vouchers:
            return jsonify(convert_decimals({"message": "No vouchers found with name specified"})), 404
            
        return jsonify({"vouchers": vouchers, "count": len(vouchers), "message": f"Found {len(vouchers)} vouchers with name specified"})

    except mysql.connector.Error as err:
        app.logger.error(f"DB Error during fetch: {str(err)}")
        return jsonify({"error": f"Database error occurred: {str(err)}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()
            print("Database connection closed.")


def is_unifi_location(location):
    """Check if location uses UniFi controller by querying unifi_access_points table"""
    if not location:
        return False
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT COUNT(*) FROM unifi_access_points WHERE LOWER(location) = LOWER(%s)",
            (location,)
        )
        count = cursor.fetchone()[0]
        cursor.close()
        conn.close()
        return count > 0
    except Exception as e:
        # On error, default to False (MikroTik)
        print(f"Error checking UniFi location: {e}")
        return False



@app.route('/register_unifi_ap', methods=['POST'])
def register_unifi_ap():
    """Register a UniFi Access Point to the database"""
    try:
        data = request.json
        
        # Validate required fields
        ap_mac = data.get('mac_address', '').strip()
        location = data.get('location', '').strip()
        ap_name = data.get('device_name', '').strip()
        notes = data.get('notes', '').strip()
        
        if not ap_mac:
            return jsonify({'success': False, 'error': 'MAC address is required'}), 400
        
        if not location:
            return jsonify({'success': False, 'error': 'Location is required'}), 400
            
        # Normalize MAC address to colon format
        ap_mac_clean = ap_mac.upper().replace('-', ':').replace('.', ':')
        
        # Insert or update the AP in database
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        # Check if AP already exists
        cursor.execute(
            "SELECT id FROM unifi_access_points WHERE ap_mac = %s",
            (ap_mac_clean,)
        )
        existing = cursor.fetchone()
        
        if existing:
            # Update existing AP
            cursor.execute(
                """UPDATE unifi_access_points 
                   SET location = %s, ap_name = %s, notes = %s, updated_at = NOW()
                   WHERE ap_mac = %s""",
                (location, ap_name, notes, ap_mac_clean)
            )
            action = 'updated'
        else:
            # Insert new AP
            cursor.execute(
                """INSERT INTO unifi_access_points (ap_mac, location, ap_name, notes)
                   VALUES (%s, %s, %s, %s)""",
                (ap_mac_clean, location, ap_name, notes)
            )
            action = 'registered'
        
        conn.commit()
        cursor.close()
        conn.close()
        
        app.logger.info(f"UniFi AP {action}: {ap_mac_clean} -> {location} ({ap_name})")
        
        return jsonify({
            'success': True,
            'message': f'UniFi AP {action} successfully',
            'ap_mac': ap_mac_clean,
            'location': location,
            'ap_name': ap_name,
            'action': action
        }), 200
        
    except mysql.connector.Error as db_err:
        app.logger.error(f"Database error registering AP: {str(db_err)}")
        return jsonify({'success': False, 'error': f'Database error: {str(db_err)}'}), 500
        
    except Exception as e:
        app.logger.error(f"Error registering AP: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500



@app.route('/get_unifi_aps', methods=['GET'])
def get_unifi_aps():
    """Get all UniFi Access Points from database"""
    try:
        # Optional filter by location
        location_filter = request.args.get('location')
        
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        
        if location_filter:
            cursor.execute(
                """SELECT id, ap_mac, location, ap_name, notes, 
                          created_at, updated_at 
                   FROM unifi_access_points 
                   WHERE location = %s
                   ORDER BY location, ap_name""",
                (location_filter,)
            )
        else:
            cursor.execute(
                """SELECT id, ap_mac, location, ap_name, notes, 
                          created_at, updated_at 
                   FROM unifi_access_points 
                   ORDER BY location, ap_name"""
            )
        
        aps = cursor.fetchall()
        cursor.close()
        conn.close()
        
        # Convert datetime objects to strings
        for ap in aps:
            if ap.get('created_at'):
                ap['created_at'] = ap['created_at'].strftime('%Y-%m-%d %H:%M:%S')
            if ap.get('updated_at'):
                ap['updated_at'] = ap['updated_at'].strftime('%Y-%m-%d %H:%M:%S')
        
        return jsonify({
            'success': True,
            'count': len(aps),
            'access_points': aps
        }), 200
        
    except mysql.connector.Error as db_err:
        app.logger.error(f"Database error fetching APs: {str(db_err)}")
        return jsonify({'success': False, 'error': f'Database error: {str(db_err)}'}), 500
        
    except Exception as e:
        app.logger.error(f"Error fetching APs: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500




@app.route('/register_simcard', methods=['POST'])
def register_simcard():
    """Register or update a SIM card in the database"""
    try:
        data = request.json
        
        # Validate required fields
        customer_name = data.get('customer_name', '').strip()
        phone_number = data.get('phone_number', '').strip()
        speed_limit = data.get('speed_limit', '').strip()
        
        if not customer_name:
            return jsonify({'success': False, 'error': 'Customer name is required'}), 400
        
        if not phone_number:
            return jsonify({'success': False, 'error': 'Phone number is required'}), 400
            
        if not speed_limit:
            return jsonify({'success': False, 'error': 'Speed limit is required'}), 400
        
        # Optional fields
        card_number = data.get('card_number', '').strip() or None
        location = data.get('location', '').strip() or None
        sim_type = data.get('sim_type', 'customer').strip()
        status = data.get('status', 'active').strip()
        date_given = data.get('date_given_to_customer', '').strip() or None
        assigned_by = data.get('assigned_by', '').strip() or None
        notes = data.get('notes', '').strip() or None
        
        # Validate sim_type
        if sim_type not in ['office', 'customer']:
            return jsonify({'success': False, 'error': 'sim_type must be office or customer'}), 400
        
        # Validate status
        if status not in ['active', 'inactive', 'suspended']:
            return jsonify({'success': False, 'error': 'status must be active, inactive, or suspended'}), 400
        
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        # Check if SIM card with this phone number already exists
        cursor.execute(
            "SELECT id FROM simcards WHERE phone_number = %s",
            (phone_number,)
        )
        existing = cursor.fetchone()
        
        if existing:
            # Update existing SIM card
            cursor.execute(
                """UPDATE simcards 
                   SET customer_name = %s, speed_limit = %s, card_number = %s,
                       location = %s, sim_type = %s, status = %s,
                       date_given_to_customer = %s, assigned_by = %s, notes = %s,
                       updated_at = NOW()
                   WHERE phone_number = %s""",
                (customer_name, speed_limit, card_number, location, sim_type,
                 status, date_given, assigned_by, notes, phone_number)
            )
            action = 'updated'
            sim_id = existing[0]
        else:
            # Insert new SIM card
            cursor.execute(
                """INSERT INTO simcards 
                   (customer_name, phone_number, speed_limit, card_number, location,
                    sim_type, status, date_given_to_customer, assigned_by, notes)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (customer_name, phone_number, speed_limit, card_number, location,
                 sim_type, status, date_given, assigned_by, notes)
            )
            action = 'registered'
            sim_id = cursor.lastrowid
        
        conn.commit()
        cursor.close()
        conn.close()
        
        app.logger.info(f"SIM card {action}: {phone_number} for {customer_name}")
        
        return jsonify({
            'success': True,
            'message': f'SIM card {action} successfully',
            'id': sim_id,
            'phone_number': phone_number,
            'customer_name': customer_name,
            'action': action
        }), 200
        
    except mysql.connector.Error as db_err:
        app.logger.error(f"Database error registering SIM card: {str(db_err)}")
        return jsonify({'success': False, 'error': f'Database error: {str(db_err)}'}), 500
        
    except Exception as e:
        app.logger.error(f"Error registering SIM card: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/get_simcards', methods=['GET'])
def get_simcards():
    """Get SIM cards from database with optional filters"""
    try:
        # Optional filters
        sim_type = request.args.get('sim_type')
        status = request.args.get('status')
        location = request.args.get('location')
        customer_name = request.args.get('customer_name')
        phone_number = request.args.get('phone_number')
        
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        
        # Build query with filters
        query = """SELECT id, customer_name, phone_number, speed_limit, card_number,
                           location, sim_type, status, registered_date,
                           date_given_to_customer, assigned_by, notes,
                           created_at, updated_at
                    FROM simcards WHERE 1=1"""
        params = []
        
        if sim_type:
            query += " AND sim_type = %s"
            params.append(sim_type)
        
        if status:
            query += " AND status = %s"
            params.append(status)
        
        if location:
            query += " AND location = %s"
            params.append(location)
        
        if customer_name:
            query += " AND customer_name LIKE %s"
            params.append(f"%{customer_name}%")
        
        if phone_number:
            query += " AND phone_number = %s"
            params.append(phone_number)
        
        query += " ORDER BY registered_date DESC"
        
        cursor.execute(query, params)
        simcards = cursor.fetchall()
        cursor.close()
        conn.close()
        
        # Convert datetime objects to strings
        for sim in simcards:
            if sim.get('registered_date'):
                sim['registered_date'] = sim['registered_date'].strftime('%Y-%m-%d %H:%M:%S')
            if sim.get('date_given_to_customer'):
                sim['date_given_to_customer'] = sim['date_given_to_customer'].strftime('%Y-%m-%d')
            if sim.get('created_at'):
                sim['created_at'] = sim['created_at'].strftime('%Y-%m-%d %H:%M:%S')
            if sim.get('updated_at'):
                sim['updated_at'] = sim['updated_at'].strftime('%Y-%m-%d %H:%M:%S')
        
        return jsonify({
            'success': True,
            'count': len(simcards),
            'simcards': simcards
        }), 200
        
    except mysql.connector.Error as db_err:
        app.logger.error(f"Database error fetching SIM cards: {str(db_err)}")
        return jsonify({'success': False, 'error': f'Database error: {str(db_err)}'}), 500
        
    except Exception as e:
        app.logger.error(f"Error fetching SIM cards: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/callback', methods=['POST'])
def callback():
    try:
        # Extract full callback data
        callback_data = request.json
        additional_properties = callback_data.get('additionalProperties', {})
        
        if not additional_properties:
            callback_data['additionalProperties'] = {'location': 'unifi'}
            additional_properties = callback_data['additionalProperties']

        # Extract location to determine the flow
        location = additional_properties.get('location')
        if location is None:
            additional_properties['location'] = 'unifi'
            location = 'unifi'

        # If location is 'unifi', forward the payload to the external URL
        if location == 'unifi':
            try:
                response = requests.post(
                    'https://radius.lightnetwork.pro/payment_callback.php',
                    json=callback_data,
                    timeout=10
                )
                response.raise_for_status()
            except requests.RequestException as e:
                try:
                    response = requests.post(
                        'https://radius.lightnetwork.pro/payment_callback.php',
                        data={'data': json.dumps(callback_data)},
                        timeout=10
                    )
                    response.raise_for_status()
                except requests.RequestException:
                    payload = {'callback_data': json.dumps(callback_data)}
                    response = requests.post(
                        'https://radius.lightnetwork.pro/payment_callback.php',
                        data=payload,
                        headers={'Content-Type': 'application/x-www-form-urlencoded'},
                        timeout=10
                    )
                    response.raise_for_status()
            return jsonify({'success': True, 'message': 'Payload forwarded to external service'}), 200

        # Handle HOME_USER payments (home internet customers)
        if location == 'HOME_USER':
            status = callback_data.get('transactionstatus', '').lower()
            if status == 'success':
                customer_id = additional_properties.get('quantity')  # Customer ID passed as quantity
                amount = float(callback_data.get('amount', 0))
                phone = callback_data.get('msisdn', callback_data.get('accountNumber', ''))
                provider = callback_data.get('operator', 'Mobile Money')
                
                if not customer_id:
                    return jsonify({'success': False, 'error': 'Missing customer ID'}), 400
                
                try:
                    # Store payment via Cloud Function
                    payment_response = requests.post(
                        'https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment',
                        json={
                            'customerId': customer_id,
                            'amount': amount,
                            'phone': phone,
                            'provider': provider,
                            'reference': f'{provider}-{phone}',
                            'createdByName': 'Home Customer'
                        },
                        timeout=10
                    )
                    payment_response.raise_for_status()
                    
                    app.logger.info(f"Home customer payment recorded: {customer_id} - TZS {amount}")
                    return jsonify({'success': True, 'message': 'Home customer payment recorded'}), 200
                    
                except requests.RequestException as e:
                    app.logger.error(f"Failed to store home customer payment: {str(e)}")
                    return jsonify({'success': False, 'error': 'Failed to record payment'}), 500
            else:
                return jsonify({'success': False, 'error': 'Payment failed'}), 400

        # Check for quantity (bulk user generation)
        quantity = additional_properties.get('quantity')
        if quantity is not None:
            try:
                quantity = int(quantity)
                if quantity > 0:
                    status = callback_data.get('transactionstatus', '').lower()
                    if status == 'success':
                        days = additional_properties.get('days')
                        try:
                            days = int(days) if days else 1
                            if days <= 0:
                                days = 1
                        except (ValueError, TypeError):
                            days = 1
                            
                        # Call generate_users function
                        response = requests.post(
                            'http://localhost:5000/generate_users',
                            json={
                                'num_users': quantity,
                                'num_days': days,
                                'location': location,
                                'speed_limit': '15M/15M'
                            },
                            timeout=10
                        )
                        response.raise_for_status()

                        # Store payment record
                        amount = float(callback_data.get('amount', 100))
                        duration_seconds = additional_properties.get('duration', 0)
                        conn = mysql.connector.connect(**db_config)
                        cursor = conn.cursor()
                        cursor.execute(
                            '''
                            INSERT INTO payments (location, amount, duration, username, phone)
                            VALUES (%s, %s, %s, %s, %s)
                            ''',
                            (location, amount, duration_seconds, '12345678', '12345678')
                        )
                        conn.commit()
                        cursor.close()
                        conn.close()

                        # Fire-and-forget: Sync to Firestore (returns instantly)
                        sync_to_firestore({
                            'location': location,
                            'amount': float(amount),
                            'duration': int(duration_seconds),
                            'phone': '12345678',
                            'payment_method': 'Mobile Money',
                            'created_by': 'system',
                            'payment_type': 'bulk_users'
                        })

                        return jsonify({'success': True, 'message': f'Generated {quantity} users with 15M/15M speed limit for {days} days'}), 200
            except ValueError:
                return jsonify({'success': False, 'error': 'Invalid quantity value'}), 400
            except requests.RequestException as e:
                return jsonify({'success': False, 'error': 'User generation failed'}), 500
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)}), 500

        # Process voucher logic
        voucher = additional_properties.get('voucher')
        amount = float(callback_data.get('amount', 100))
        duration = additional_properties.get('duration')
        mac_address = additional_properties.get('mac_address')
        nas_ip = additional_properties.get('nas_ip')  # Handle gracefully
        status = callback_data.get('transactionstatus', '').lower()
        phone = callback_data.get('msisdn', '0750549026')

        # Ensure voucher and duration are present
        if not voucher:
            return jsonify({'success': False, 'error': 'Missing voucher'}), 400

        if not duration:
            return jsonify({'success': False, 'error': 'Missing duration'}), 400

        # Check payment status
        if status != 'success':
            return jsonify({'success': False, 'error': 'Payment failed'}), 400

        # Store the voucher in the database
        if not store_voucher(voucher, duration, location, amount, phone, mac_address):
            return jsonify({'success': False, 'error': 'Voucher creation failed'}), 500

        # Route to appropriate authorization based on location
        app.logger.info(f"CALLBACK DEBUG: location={location}, mac_address={mac_address}, duration={duration}")
        if location and is_unifi_location(location):
            app.logger.info(f"ROUTING TO UNIFI: {mac_address}")
            # UniFi location - call PHP endpoint
            if mac_address:
                try:
                    unifi_url = 'http://127.0.0.1:8000/authorize-mac.php'
                    minutes = int(duration) // 60 if duration else 1440
                    # Pass speed_limit parameter to avoid database query in PHP
                    params = {'mac': mac_address, 'minutes': minutes}
                    # Speed limit is hardcoded as 15M/15M in store_voucher
                    params['speed_limit'] = '15M/15M'
                    response = requests.get(unifi_url, params=params, timeout=10)
                    if response.status_code == 200:
                        result = response.json()
                        if result.get('success'):
                            app.logger.info(f"UniFi authorization successful for {mac_address}")
                        else:
                            app.logger.warning(f"UniFi authorization failed: {result.get('error')}")
                except Exception as e:
                    app.logger.error(f"UniFi authorization error: {str(e)}")
        else:
            # Other locations - use MikroTik
            if mac_address and nas_ip and MIKROTIK_AUTH_AVAILABLE:
                try:
                    auth_result = authenticate_user_via_mikrotik(mac_address, nas_ip)
                    if auth_result['success']:
                        app.logger.info(f"MikroTik authentication successful for {mac_address}")
                    else:
                        app.logger.warning(f"MikroTik authentication failed: {auth_result['error']}")
                except Exception as e:
                    app.logger.error(f"MikroTik authentication error: {str(e)}")

        return jsonify({'success': True}), 200

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


def store_voucher(voucher, seconds, location, amount, phone, mac_address):
    try:
        
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        print("Database connected successfully!")
        current_time = datetime.now()
        expire_time = current_time + timedelta(seconds=int(seconds))
        print(f"Inserting voucher: {voucher}, duration: {seconds}, mac_address: {mac_address}, first_login_time: {current_time}, expire_time: {expire_time}")
        cursor.execute('''
            INSERT INTO radcheck (username, attribute, op, value)
            VALUES (%s, 'Cleartext-Password', ':=', %s)
        ''', (voucher, 'ROCKY221122'))
        cursor.execute('''
            INSERT INTO radreply (username, attribute, op, value)
            VALUES (%s, 'Mikrotik-Rate-Limit', ':=', %s)
        ''', (voucher, '15M/15M'))
        cursor.execute('''
            INSERT INTO vouchers (username, location, speed_limit, session_timeout, first_login_time, expire_time, used, mac_address)
            VALUES (%s, %s, %s, %s, %s, %s, 1, %s)
        ''', (voucher, location, '15M/15M', seconds, current_time, expire_time, mac_address))
        cursor.execute('''
            INSERT INTO payments (location, amount, duration, username, phone)
            VALUES (%s, %s, %s, %s, %s)
        ''', (location, amount, seconds, voucher, phone))
        conn.commit()
        print("Voucher stored successfully!")
        
        # Fire-and-forget: Sync to Firestore (returns instantly)
        sync_to_firestore({
            'voucher': voucher,
            'location': location,
            'amount': float(amount),
            'duration': int(seconds),
            'phone': phone,
            'mac_address': mac_address,
            'payment_method': 'Mobile Money',
            'created_by': 'system',
            'payment_type': 'voucher'
        })
        
        return True
    except mysql.connector.Error as e:
        print(f"DB Error: {str(e)}")
        return False
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")

def activate_voucher(voucher):
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        # Delete the X-Status row for the given voucher
        cursor.execute('''
            DELETE FROM radreply
            WHERE username = %s AND attribute = 'X-Status'
        ''', (voucher,))

        conn.commit()
        return cursor.rowcount > 0  # Returns True if a row was deleted
    except mysql.connector.Error as e:
        app.logger.error(f"DB Error: {e}")
        return False
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
  

def delete_voucher(voucher):
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        cursor.execute('DELETE FROM radcheck WHERE username = %s', (voucher,))
        cursor.execute('DELETE FROM radreply WHERE username = %s', (voucher,))
        conn.commit()
        return True
    except mysql.connector.Error as e:
        app.logger.error(f"DB Error: {e}")
        return False
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()

# END OF AZAM

# Fetch Session Timeout from radreply
@app.route('/get_session_timeout', methods=['GET'])
def get_session_timeout():
    username = request.args.get('username')

    if not username:
        return jsonify({"error": "Username is required"}), 400

    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)

        query = """
        SELECT value FROM radreply
        WHERE username = %s AND attribute = 'Session-Timeout';
        """
        cursor.execute(query, (username,))
        result = cursor.fetchone()

        session_timeout = int(result['value']) if result else 0
        return jsonify({"session_timeout": session_timeout})

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

@app.route('/fetch_superagent_recent_vouchers', methods=['GET'])
def fetch_superagent_recent_vouchers():
    try:
        # Get locations parameter for superagents
        locations = request.args.get('locations')  # Comma-separated locations for superagents
        search_term = request.args.get('search', '').strip()  # Optional search parameter
        
        if not locations:
            return jsonify(convert_decimals({"error": "Locations parameter is required"})), 400
        
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Calculate time 24 hours ago
        time_threshold = datetime.now() - timedelta(hours=24)
        
        # Handle multiple locations for superagents
        location_list = [loc.strip() for loc in locations.split(',') if loc.strip()]
        if not location_list:
            return jsonify(convert_decimals({"error": "Valid locations required"})), 400
            
        # Build location filter
        location_placeholders = ','.join(['%s'] * len(location_list))
        location_filter = f"AND location IN ({location_placeholders})"
        
        # Build search filter if search term provided
        search_filter = ""
        search_params = []
        if search_term:
            search_filter = "AND (username LIKE %s OR mac_address LIKE %s)"
            search_params = [f"%{search_term}%", f"%{search_term}%"]
        
        query = f"""
            SELECT id, username, location, speed_limit, session_timeout, 
                   mac_address, first_login_time, expire_time, used, 
                   created_at, updated_at 
            FROM vouchers 
            WHERE first_login_time >= %s 
            {location_filter}
            {search_filter}
            ORDER BY first_login_time DESC
        """
        
        params = [time_threshold] + location_list + search_params
        cursor.execute(query, params)
        vouchers = cursor.fetchall()
        
        search_info = f" matching '{search_term}'" if search_term else ""
        location_info = f" across locations: {', '.join(location_list)}"
        
        return jsonify({
            "vouchers": vouchers,
            "count": len(vouchers),
            "locations": location_list,
            "search_term": search_term,
            "message": f"Found {len(vouchers)} recent logins{search_info}{location_info}"
        })
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()



# Fetch user information from radcheck
@app.route('/get_user_info', methods=['GET'])
def get_user_info():
    username = request.args.get('username')

    if not username:
        return jsonify({"error": "Username is required"}), 400

    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)

        query = """
        SELECT id, username, location, speed_limit, session_timeout, mac_address, 
               first_login_time, expire_time, used, created_at, updated_at 
        FROM vouchers 
        WHERE username = %s
        """
        cursor.execute(query, (username,))
        voucher_info = cursor.fetchone()

        if not voucher_info:
            return jsonify({"error": "Voucher not found"}), 404

        return jsonify({"voucher_info": voucher_info})

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

@app.route('/fetch_recent_vouchers', methods=['GET'])
def fetch_recent_vouchers():
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Calculate time 24 hours ago
        time_threshold = datetime.now() - timedelta(hours=24)
        
        query = """
            SELECT id, username, location, speed_limit, session_timeout, 
                   mac_address, first_login_time, expire_time, used, 
                   created_at, updated_at 
            FROM vouchers 
            WHERE first_login_time >= %s
        """
        cursor.execute(query, (time_threshold,))
        vouchers = cursor.fetchall()
        
        return jsonify({
            "vouchers": vouchers,
            "count": len(vouchers),
            "message": f"Found {len(vouchers)} vouchers with first login within last 24 hours"
        })
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

@app.route('/fetch_recent_payments', methods=['GET'])
def fetch_recent_payments():
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Calculate time 24 hours ago
        time_threshold = datetime.now() - timedelta(hours=24)
        
        query = """
            SELECT id, location, amount, duration, username, phone, timestamp
            FROM payments 
            WHERE timestamp >= %s
        """
        cursor.execute(query, (time_threshold,))
        payments = cursor.fetchall()

        # Convert Decimal to float for JSON serialization
        for payment in payments:
            if 'amount' in payment and isinstance(payment['amount'], Decimal):
                payment['amount'] = float(payment['amount'])
            if 'duration' in payment and isinstance(payment['duration'], Decimal):
                payment['duration'] = float(payment['duration'])
        
        # Calculate total amount
        total_amount = sum(payment['amount'] for payment in payments) if payments else 0
        print(f"Total amount for recent payments (last 24h): {total_amount}")  # Added print statement

        return jsonify({
            "payments": payments,
            "count": len(payments),
            "total_amount": float(total_amount) if isinstance(total_amount, Decimal) else total_amount,
            "message": f"Found {len(payments)} payments within last 24 hours with a total amount of {total_amount} TZS"
        })
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/fetch_vouchers_today', methods=['GET'])
def fetch_vouchers_today():
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Get start of current day (midnight)
        today_midnight = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        
        query = """
            SELECT id, username, location, speed_limit, session_timeout, 
                   mac_address, first_login_time, expire_time, used, 
                   created_at, updated_at 
            FROM vouchers 
            WHERE first_login_time >= %s
        """
        cursor.execute(query, (today_midnight,))
        vouchers = cursor.fetchall()
        
        return jsonify({
            "vouchers": vouchers,
            "count": len(vouchers),
            "message": f"Found {len(vouchers)} vouchers with first login today"
        })
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

@app.route('/fetch_payments_today', methods=['GET'])
def fetch_payments_today():
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Get start of current day (midnight)
        today_midnight = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        
        # Query to fetch payments and calculate total amount
        query = """
            SELECT id, location, amount, duration, username, phone, timestamp
            FROM payments 
            WHERE timestamp >= %s
        """
        cursor.execute(query, (today_midnight,))
        payments = cursor.fetchall()

        # Calculate total amount, handling decimal values
        total_amount = sum(float(payment['amount']) if payment['amount'] is not None else 0.0 for payment in payments) if payments else 0.0
        print(f"Total amount for today's payments: {total_amount}")  # Added print statement

        return jsonify(convert_decimals({
            "payments": payments,
            "count": len(payments),
            "total_amount": total_amount,
            "message": f"Found {len(payments)} payments made today with a total amount of {total_amount} TZS"
        }))
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/fetch_payments_summary', methods=['GET'])
def fetch_payments_summary():
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        
        now = datetime.now()
        
        # Today
        today = now.date()
        cursor.execute("""
            SELECT SUM(amount) as total_today 
            FROM payments 
            WHERE DATE(timestamp) = %s
        """, (today,))
        result_today = cursor.fetchone()
        total_today = result_today['total_today'] if result_today['total_today'] else 0.0

        # Last 24 hours
        last_24_hours = now - timedelta(hours=24)
        cursor.execute("""
            SELECT SUM(amount) as total_last_24 
            FROM payments 
            WHERE timestamp >= %s
        """, (last_24_hours,))
        result_last_24 = cursor.fetchone()
        total_last_24 = result_last_24['total_last_24'] if result_last_24['total_last_24'] else 0.0

        # Last month
        last_month = now.replace(day=1) - timedelta(days=1)
        start_of_last_month = last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end_of_last_month = last_month.replace(hour=23, minute=59, second=59, microsecond=0)
        cursor.execute("""
            SELECT SUM(amount) as total_last_month 
            FROM payments 
            WHERE timestamp >= %s AND timestamp <= %s
        """, (start_of_last_month, end_of_last_month))
        result_last_month = cursor.fetchone()
        total_last_month = result_last_month['total_last_month'] if result_last_month['total_last_month'] else 0.0

        # This month
        start_of_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        cursor.execute("""
            SELECT SUM(amount) as total_this_month 
            FROM payments 
            WHERE timestamp >= %s AND timestamp < %s
        """, (start_of_month, now))
        result_this_month = cursor.fetchone()
        total_this_month = result_this_month['total_this_month'] if result_this_month['total_this_month'] else 0.0

        # This year
        start_of_year = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        cursor.execute("""
            SELECT SUM(amount) as total_year 
            FROM payments 
            WHERE timestamp >= %s
        """, (start_of_year,))
        result_year = cursor.fetchone()
        total_year = result_year['total_year'] if result_year['total_year'] else 0.0

        # Daily average for this month
        days_in_month = (now - start_of_month).days + 1  # Number of days elapsed, including today
        daily_average_this_month = total_this_month / days_in_month if days_in_month > 0 else 0.0

        print(f"Payment summary - Today: {total_today}, Last 24h: {total_last_24}, Last Month: {total_last_month}, This Month: {total_this_month}, Daily Avg This Month: {daily_average_this_month}, This Year: {total_year}")
        return jsonify(convert_decimals({
            "success": True,
            "summary": {
                "today": total_today,
                "last_24_hours": total_last_24,
                "last_month": total_last_month,
                "this_month": total_this_month,
                "daily_average_this_month": daily_average_this_month,
                "this_year": total_year
            },
            "message": f"Payment summary for {now.strftime('%Y-%m-%d %H:%M:%S')} retrieved"
        })), 200

    except mysql.connector.Error as err:
        print(f"DB Error during fetch: {str(err)}")
        return jsonify(convert_decimals({"success": False, "error": "Database error occurred"})), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")

@app.route('/fetch_agent_payments_summary', methods=['GET'])
def fetch_agent_payments_summary():
    try:
        # Get location parameter for agents or locations parameter for superagents
        location = request.args.get('location')
        locations = request.args.get('locations')  # Comma-separated locations for superagents
        
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)
        
        now = datetime.now()
        
        # Base WHERE clause for location filtering
        location_filter = ""
        location_params = []
        
        if locations:
            # Handle multiple locations for superagents
            location_list = [loc.strip() for loc in locations.split(',') if loc.strip()]
            if location_list:
                placeholders = ','.join(['%s'] * len(location_list))
                location_filter = f" AND location IN ({placeholders})"
                location_params = location_list
        elif location:
            # Handle single location for agents
            location_filter = " AND location = %s"
            location_params = [location]
        
        # Today
        today = now.date()
        cursor.execute(f"""
            SELECT SUM(amount) as total_today 
            FROM payments 
            WHERE DATE(timestamp) = %s 
              AND phone <> '12345678' {location_filter}
        """, [today] + location_params)
        result_today = cursor.fetchone()
        total_today = result_today['total_today'] if result_today['total_today'] else 0.0

        # Last 24 hours
        last_24_hours = now - timedelta(hours=24)
        cursor.execute(f"""
            SELECT SUM(amount) as total_last_24 
            FROM payments 
            WHERE timestamp >= %s 
              AND phone <> '12345678' {location_filter}
        """, [last_24_hours] + location_params)
        result_last_24 = cursor.fetchone()
        total_last_24 = result_last_24['total_last_24'] if result_last_24['total_last_24'] else 0.0

        # Last month
        last_month = now.replace(day=1) - timedelta(days=1)
        start_of_last_month = last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end_of_last_month = last_month.replace(hour=23, minute=59, second=59, microsecond=0)
        cursor.execute(f"""
            SELECT SUM(amount) as total_last_month 
            FROM payments 
            WHERE timestamp >= %s AND timestamp <= %s 
              AND phone <> '12345678' {location_filter}
        """, [start_of_last_month, end_of_last_month] + location_params)
        result_last_month = cursor.fetchone()
        total_last_month = result_last_month['total_last_month'] if result_last_month['total_last_month'] else 0.0

        # This month
        start_of_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        cursor.execute(f"""
            SELECT SUM(amount) as total_this_month 
            FROM payments 
            WHERE timestamp >= %s AND timestamp < %s 
              AND phone <> '12345678' {location_filter}
        """, [start_of_month, now] + location_params)
        result_this_month = cursor.fetchone()
        total_this_month = result_this_month['total_this_month'] if result_this_month['total_this_month'] else 0.0

        # This year
        start_of_year = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        cursor.execute(f"""
            SELECT SUM(amount) as total_year 
            FROM payments 
            WHERE timestamp >= %s 
              AND phone <> '12345678' {location_filter}
        """, [start_of_year] + location_params)
        result_year = cursor.fetchone()
        total_year = result_year['total_year'] if result_year['total_year'] else 0.0

        # Daily average for this month
        days_in_month = (now - start_of_month).days + 1  # Number of days elapsed, including today
        daily_average_this_month = total_this_month / days_in_month if days_in_month > 0 else 0.0

        if locations:
            location_info = f" for locations '{locations}'"
        elif location:
            location_info = f" for location '{location}'"
        else:
            location_info = ""
            
        print(f"Agent payment summary{location_info} - Today: {total_today}, Last 24h: {total_last_24}, Last Month: {total_last_month}, This Month: {total_this_month}, Daily Avg This Month: {daily_average_this_month}, This Year: {total_year}")
        return jsonify(convert_decimals({
            "success": True,
            "summary": {
                "today": total_today,
                "last_24_hours": total_last_24,
                "last_month": total_last_month,
                "this_month": total_this_month,
                "daily_average_this_month": daily_average_this_month,
                "this_year": total_year
            },
            "location": location,
            "locations": locations,
            "message": f"Agent payment summary{location_info} for {now.strftime('%Y-%m-%d %H:%M:%S')} retrieved"
        })), 200

    except mysql.connector.Error as err:
        print(f"DB Error during fetch: {str(err)}")
        return jsonify(convert_decimals({"success": False, "error": "Database error occurred"})), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")






@app.route('/fetch_payments_by_location', methods=['GET'])
def fetch_payments_by_location():
    try:
        # Optional: comma-separated locations for superagents
        locations = request.args.get('locations')
        period = request.args.get('period', 'last24h').lower().strip()

        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)

        now = datetime.now()
        where_clauses = []
        params = []

        # Time filter
        if period == 'today':
            where_clauses.append('DATE(timestamp) = %s')
            params.append(now.date())
        else:
            time_threshold = now - timedelta(hours=24)
            where_clauses.append('timestamp >= %s')
            params.append(time_threshold)

        # Exclude test payments
        where_clauses.append("phone <> '12345678'")

        # Locations filter
        location_list = []
        location_filter = ''
        if locations:
            location_list = [loc.strip() for loc in locations.split(',') if loc.strip()]
            if location_list:
                placeholders = ','.join(['%s'] * len(location_list))
                location_filter = f" AND location IN ({placeholders})"
                params += location_list

        where_sql = ' AND '.join(where_clauses)

        query = f"""
            SELECT location, COUNT(*) as count
            FROM payments
            WHERE {where_sql}{location_filter}
            GROUP BY location
            ORDER BY count DESC
        """

        cursor.execute(query, params)
        rows = cursor.fetchall() or []
        total_count = sum(row['count'] for row in rows) if rows else 0

        return jsonify({
            'success': True,
            'period': 'today' if period == 'today' else 'last24h',
            'counts': rows,
            'locations': location_list,
            'total_count': total_count,
            'message': f"Found {total_count} payments across {len(rows)} location(s)"
        }), 200

    except mysql.connector.Error as err:
        return jsonify({'success': False, 'error': f"MySQL Error: {err}"}), 500
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")





@app.route('/vouchers', methods=['GET'])
def get_vouchers():
    try:
        # Establish database connection
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)  # Fetch results as dictionaries
        
        # SQL query to fetch all vouchers
        query = """
            SELECT id, username, location, speed_limit, session_timeout, 
                   mac_address, first_login_time, expire_time, used, 
                   created_at, updated_at 
            FROM vouchers
        """
        
        cursor.execute(query)
        vouchers = cursor.fetchall()
        
        # If no vouchers found, return a 404 JSON response
        if not vouchers:
            return jsonify({"message": "No vouchers found"}), 404
            
        return jsonify({"vouchers": vouchers})
    
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if 'db_connection' in locals() and db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/valid_users', methods=['GET'])
def get_valid_users():
    location = request.args.get('location', None)  # Get location or set None

    try:
        # Establish database connection
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)  # Fetch results as dictionaries

        # SQL query to fetch users from 'location' table
        query = "SELECT username, speed_limit, session_timeout, location FROM location"
        params = []

        # Apply filter if location is provided
        if location:
            query += " WHERE location = %s"
            params.append(location)

        cursor.execute(query, params)
        users = cursor.fetchall()

        # If no users found, return a 404 JSON response
        if not users:
            return jsonify({"message": "No users found for this location"}), 404

        return jsonify({"users": users})

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/get-expire-time', methods=['GET'])
def get_expire_time():
    mac_address = request.args.get('mac', None)  # Get MAC address from query parameter

    # Validate MAC address
    if not mac_address:
        return jsonify({"error": "MAC address is required"}), 400

    try:
        # Establish database connection
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)

        # SQL query to fetch expire_time for the given MAC address
        query = "SELECT expire_time FROM vouchers WHERE mac_address = %s"
        params = [mac_address]

        cursor.execute(query, params)
        result = cursor.fetchone()

        # If no record is found, return a 404 JSON response
        if not result:
            return jsonify({"error": "MAC address not found"}), 404

        # Return expire_time in the response
        return jsonify({"expire_time": result['expire_time'].strftime('%Y-%m-%d %H:%M:%S')})

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

# Delete user from radcheck and radreply
@app.route('/delete_user', methods=['POST'])
def delete_user():
    username = request.json.get('username')

    if not username:
        return jsonify({"error": "Username is required"}), 400

    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor()

        cursor.execute("DELETE FROM radcheck WHERE username = %s", (username,))
        cursor.execute("DELETE FROM radreply WHERE username = %s", (username,))
        cursor.execute("DELETE FROM vouchers WHERE username = %s", (username,))
        db_connection.commit()

        return jsonify({"message": f"User {username} deleted successfully"})

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()


# Fetch all payments
@app.route('/payments', methods=['GET'])
def payments():
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)

        query = "SELECT * FROM payments;"
        cursor.execute(query)
        payments = cursor.fetchall()

        return jsonify(convert_decimals({"payments": payments}))

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/make-paymentagent', methods=['POST'])
def make_paymentagent():
    try:
        print("\n=== STARTING PAYMENT PROCESS ===")
        print("Received request data:", request.json)

        
        data = request.json
        location = data['location']
        days = data['days']

        duration_seconds = data['durationSeconds']
        print(f"Duration seconds: {duration_seconds}")

        # Get access token
        try:
            print("\n[1/4] Getting access token...")
            token = get_access_token()
            print("Token retrieval successful")
        except Exception as e:
            print("!! TOKEN ERROR !!", str(e))
            return jsonify({
                'success': False,
                'error': 'Payment service unavailable',
                'details': str(e)
            }), 503

      
        # Prepare payload
        print("\n[3/4] Preparing payment payload...")
        payload = {
            'accountNumber': data['phone'],
            'amount': data['amount'],
            'currency': 'TZS',
            'externalId': str(uuid.uuid4()),
            'provider': data['provider'],
            'additionalProperties': {
                'duration': duration_seconds,
                'days'    : days,
                'location': location,
                'quantity': data['quantity'],
            }
        }
        print("Payload (sanitized):", {**payload, 'additionalProperties': '...'})

        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}',
            'X-API-Key': 'none'
        }

        print("Headers:", headers)

        # Make payment request
        print("\n[4/4] Making payment request...")
        response = requests.post(
            'https://checkout.azampay.co.tz/azampay/mno/checkout',
            json=payload,
            headers=headers,
            timeout=15
        )

        print("\n=== PAYMENT RESPONSE ===")
        print("Status Code:", response.status_code)
        print("Headers:", dict(response.headers))
        print("Response Body:", response.text)

        response.raise_for_status()
        print("Payment request successful")

        return jsonify({
            'success': True,
            'message': 'Payment initiated - use voucher now'
        })

    except requests.exceptions.RequestException as e:
        print("\n!! REQUEST ERROR !!")
        print("Error Type:", type(e).__name__)
        print("Error Message:", str(e))
        if hasattr(e, 'response') and e.response:
            print("Response Status:", e.response.status_code)
            print("Response Body:", e.response.text)
        return jsonify({'success': False, 'error': str(e)}), 500

    except Exception as e:
        print("\n!! GENERAL ERROR !!")
        print("Error Type:", type(e).__name__)
        print("Error Message:", str(e))
        return jsonify({'success': False, 'error': str(e)}), 500



@app.route('/generate_users', methods=['POST'])
def generate_users():
    data = request.get_json()

    try:
        num_users = int(data.get('num_users', 0))
        num_days = float(data.get('num_days', 0))
        location = data.get('location')
        speed_limit = data.get('speed_limit')  # Get optional speed limit
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid input. Please provide numbers for num_users and num_days."}), 400

    if num_users <= 0 or num_days <= 0:
        return jsonify({"error": "num_users and num_days must be greater than zero."}), 400

    session_timeout_seconds = int(num_days * 24 * 60 * 60)

    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor()

        users_created = []

        for _ in range(num_users):
            username = ''.join(random.choices(string.digits, k=10))
            password = 'ROCKY221122'  # Warning: Hardcoded password for example

            # Insert credentials
            cursor.execute(
                "INSERT INTO radcheck (username, attribute, op, value) VALUES (%s, 'Cleartext-Password', ':=', %s)",
                (username, password)
            )

            # Insert session timeout
            # cursor.execute(
            #   "INSERT INTO radreply (username, attribute, op, value) VALUES (%s, 'Session-Timeout', ':=', %s)",
            #   (username, session_timeout_seconds)
            # )

           

            # Insert into location table with Mikrotik rate limit and session timeout
            cursor.execute(
               "INSERT INTO location (username, location, speed_limit, session_timeout) VALUES (%s, %s, %s, %s)",
               (username, location, speed_limit, session_timeout_seconds)
            )
               # Insert into vouchers table (this is your target)
            cursor.execute(
               "INSERT INTO vouchers (username, location, speed_limit, session_timeout, used) VALUES (%s, %s, %s, %s, 0)",
               (username, location, speed_limit, session_timeout_seconds)
            )

            # Insert speed limit if provided
            if speed_limit:
                cursor.execute(
                    "INSERT INTO radreply (username, attribute, op, value) VALUES (%s, 'Mikrotik-Rate-Limit', ':=', %s)",
                    (username, speed_limit)
                )

            users_created.append({
                "username": username,
                "password": password,
                "session_timeout": session_timeout_seconds,
                "speed_limit": speed_limit if speed_limit else "None"
            })

        db_connection.commit()
        return jsonify({
            "message": f"{num_users} users generated successfully.",
            "users": users_created
        }), 201

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
    finally:
        if db_connection and db_connection.is_connected():
            cursor.close()
            db_connection.close()


def _generateoneuser_decode_uid():
    """Return (uid, None) or (None, (jsonify_response, http_status))."""
    auth_header = request.headers.get('Authorization') or ''
    if not auth_header.startswith('Bearer '):
        return None, (jsonify({'error': 'Authorization: Bearer <Firebase ID token> is required'}), 401)
    token = auth_header.split(' ', 1)[1].strip()
    if not token:
        return None, (jsonify({'error': 'Empty bearer token'}), 401)
    try:
        decoded = firebase_auth.verify_id_token(token)
        return decoded['uid'], None
    except Exception as e:
        logging.warning('generateoneuser: invalid ID token: %s', e)
        return None, (jsonify({'error': 'Invalid or expired ID token'}), 401)


def _generateoneuser_require_technician(uid):
    """Return None if Firestore user has role technician; else (jsonify, http_status) error tuple."""
    if db is None:
        return (jsonify({'error': 'Firestore is not available'}), 503)
    doc = db.collection('users').document(uid).get()
    if not doc.exists:
        return (jsonify({'error': 'User profile not found in Firestore'}), 403)
    role = str((doc.to_dict() or {}).get('role', '')).strip().lower()
    if role != 'technician':
        return (jsonify({'error': 'Technician role required'}), 403)
    return None


@app.route('/generateoneuser', methods=['POST'])
def generateoneuser():
    """
    Technician-only: create exactly one RADIUS/voucher user per request.
    Fixed speed 10M/10M; location is always 'general'.
    Allowed duration_key: 3h, 1d (3 hours, 1 day).
    Requires Authorization: Bearer <Firebase ID token>; uid must have role 'technician' in Firestore users/{uid}.
    Writes audit trail to Firestore: technician_one_user_logs, technician_one_user_daily, technician_one_user_monthly.
    Enforces TECHNICIAN_ONE_USER_MAX_PER_DAY per technician (UTC calendar day).
    """
    if db is None:
        return jsonify({'error': 'Firestore is not available; technician audit disabled.'}), 503

    uid, err = _generateoneuser_decode_uid()
    if err is not None:
        return err
    role_err = _generateoneuser_require_technician(uid)
    if role_err is not None:
        return role_err

    data = request.get_json(silent=True) or {}
    duration_key = (data.get('duration_key') or '').strip().lower()
    location = TECHNICIAN_ONE_USER_LOCATION

    session_timeout = TECHNICIAN_ONE_USER_DURATIONS_SEC.get(duration_key)
    if session_timeout is None:
        return jsonify({
            'error': 'Invalid duration_key',
            'allowed': sorted(TECHNICIAN_ONE_USER_DURATIONS_SEC.keys()),
        }), 400

    day_str = datetime.utcnow().strftime('%Y-%m-%d')
    month_str = datetime.utcnow().strftime('%Y-%m')
    daily_doc_id = f'{uid}_{day_str}'
    daily_ref = db.collection('technician_one_user_daily').document(daily_doc_id)
    daily_snap = daily_ref.get()
    prev_daily = int((daily_snap.to_dict() or {}).get('count', 0))
    if prev_daily >= TECHNICIAN_ONE_USER_MAX_PER_DAY:
        return jsonify({
            'error': 'Daily generation limit reached',
            'limit': TECHNICIAN_ONE_USER_MAX_PER_DAY,
            'date': day_str,
            'count_today': prev_daily,
        }), 429

    username = ''.join(random.choices(string.digits, k=10))
    password = 'ROCKY221122'
    speed_limit = TECHNICIAN_ONE_USER_SPEED

    db_connection = None
    cursor = None
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor()
        cursor.execute(
            "INSERT INTO radcheck (username, attribute, op, value) VALUES (%s, 'Cleartext-Password', ':=', %s)",
            (username, password),
        )
        cursor.execute(
            "INSERT INTO location (username, location, speed_limit, session_timeout) VALUES (%s, %s, %s, %s)",
            (username, location, speed_limit, session_timeout),
        )
        cursor.execute(
            "INSERT INTO vouchers (username, location, speed_limit, session_timeout, used) VALUES (%s, %s, %s, %s, 0)",
            (username, location, speed_limit, session_timeout),
        )
        cursor.execute(
            "INSERT INTO radreply (username, attribute, op, value) VALUES (%s, 'Mikrotik-Rate-Limit', ':=', %s)",
            (username, speed_limit),
        )
        db_connection.commit()
    except mysql.connector.Error as err:
        if db_connection and db_connection.is_connected():
            db_connection.rollback()
        logging.exception('generateoneuser MySQL error: %s', err)
        return jsonify({'error': f'MySQL Error: {err}'}), 500
    finally:
        if cursor is not None:
            try:
                cursor.close()
            except Exception:
                pass
        if db_connection is not None and db_connection.is_connected():
            try:
                db_connection.close()
            except Exception:
                pass

    new_daily = prev_daily + 1
    month_doc_id = f'{uid}_{month_str}'
    month_ref = db.collection('technician_one_user_monthly').document(month_doc_id)
    month_snap = month_ref.get()
    prev_month = int((month_snap.to_dict() or {}).get('count', 0))
    new_month = prev_month + 1
    now_ts = datetime.utcnow()

    batch = db.batch()
    batch.set(daily_ref, {
        'count': new_daily,
        'technician_uid': uid,
        'date': day_str,
        'last_username': username,
        'last_duration_key': duration_key,
        'last_location': location,
        'updated_at': now_ts,
    }, merge=True)
    batch.set(month_ref, {
        'count': new_month,
        'technician_uid': uid,
        'month': month_str,
        'updated_at': now_ts,
    }, merge=True)
    log_ref = db.collection('technician_one_user_logs').document()
    batch.set(log_ref, {
        'technician_uid': uid,
        'username': username,
        'location': location,
        'duration_key': duration_key,
        'session_timeout_seconds': session_timeout,
        'speed_limit': speed_limit,
        'day': day_str,
        'month': month_str,
        'created_at': now_ts,
    })
    try:
        batch.commit()
    except Exception as e:
        logging.exception('generateoneuser Firestore audit failed (user was created in MySQL): %s', e)
        return jsonify({
            'success': True,
            'warning': 'User created but Firestore audit write failed; reconcile manually.',
            'user': {
                'username': username,
                'session_timeout': session_timeout,
                'speed_limit': speed_limit,
                'duration_key': duration_key,
                'location': location,
            },
        }), 201

    logging.info(
        'generateoneuser: uid=%s username=%s location=%s duration=%s day_count=%s month_count=%s',
        uid, username, location, duration_key, new_daily, new_month,
    )

    return jsonify({
        'success': True,
        'message': 'One user generated successfully.',
        'user': {
            'username': username,
            'session_timeout': session_timeout,
            'speed_limit': speed_limit,
            'duration_key': duration_key,
            'location': location,
        },
        'daily_count_today': new_daily,
        'daily_limit': TECHNICIAN_ONE_USER_MAX_PER_DAY,
        'month_key': month_str,
        'monthly_count': new_month,
    }), 201


@app.route('/insert_voucher', methods=['POST'])
def insert_voucher():
    try:
        data = request.json
        mac_address = data.get('mac_address')
        name = data.get('name', 'DefaultName')
        expire_time_str = data.get('expire_time')
        current_time = datetime.now()

        if not mac_address:
            return jsonify({'success': False, 'error': 'mac_address is required'}), 400

        # Generate random 8-digit username
        username = ''.join(random.choices(string.digits, k=8))

        # Use provided expire_time or default to December 31, 2030
        if expire_time_str:
            try:
                # Parse the ISO8601 string from the client
                expire_time = datetime.fromisoformat(expire_time_str.replace('Z', '+00:00'))
            except ValueError:
                return jsonify({'success': False, 'error': 'Invalid expire_time format. Use ISO8601 format.'}), 400
        else:
            # Fallback to 2030 if no expire_time provided
            expire_time = datetime(2030, 12, 31, 23, 59, 59)

        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO vouchers (username, location, speed_limit, session_timeout, first_login_time, used, created_at, updated_at, mac_address, expire_time, name)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ''', (
            username,
            "agent",
            "20M/20M",
            86400,
            current_time,
            1,
            current_time,
            None,  # Changed updated_at back to None as per original intent
            mac_address,
            expire_time,
            name
        ))

        conn.commit()
        print(f"Inserted voucher with username: {username}, mac_address: {mac_address}, expire_time: {expire_time}, name: {name}")
        return jsonify({'success': True, 'message': 'Voucher inserted successfully', 'username': username}), 201

    except ValueError as e:
        return jsonify({'success': False, 'error': f'Invalid data format: {str(e)}'}), 400
    except mysql.connector.Error as e:
        print(f"DB Error during insert: {str(e)}")
        return jsonify({'success': False, 'error': 'Database error occurred'}), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")


@app.route('/delete_voucher_by_username', methods=['POST'])
def delete_voucher_by_username():
    try:
        data = request.json
        username = data.get('username')

        if not username:
            return jsonify({'success': False, 'error': 'username is required'}), 400

        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        cursor.execute('DELETE FROM vouchers WHERE username = %s', (username,))
        conn.commit()
        if cursor.rowcount > 0:
            print(f"Deleted voucher with username: {username}")
            return jsonify({'success': True, 'message': f'Voucher with username {username} deleted'}), 200
        else:
            print(f"No voucher found with username: {username}")
            return jsonify({'success': False, 'error': 'No voucher found'}), 404

    except mysql.connector.Error as e:
        print(f"DB Error during delete: {str(e)}")
        return jsonify({'success': False, 'error': 'Database error occurred'}), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")

@app.route('/update_voucher', methods=['POST'])
def update_voucher():
    try:
        data = request.json
        username = data.get('username')  # Identifier to find the record
        new_mac_address = data.get('new_mac_address')  # Optional
        name = data.get('name')  # Optional

        if not username:
            return jsonify({'success': False, 'error': 'username is required'}), 400

        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()

        # Build the UPDATE query dynamically based on provided fields
        update_fields = []
        update_values = []
        if new_mac_address is not None:  # Explicitly check for None to allow empty string or omission
            update_fields.append("mac_address = %s")
            update_values.append(new_mac_address)
        if name is not None:  # Explicitly check for None to allow empty string or omission
            update_fields.append("name = %s")
            update_values.append(name)
        update_fields.append("updated_at = %s")
        update_values.append(datetime.now())

        if not update_fields[:-1]:  # Check if no updatable fields (excluding updated_at)
            return jsonify({'success': False, 'error': 'At least one of new_mac_address or name must be provided'}), 400

        query = f"""
            UPDATE vouchers 
            SET {', '.join(update_fields)}
            WHERE username = %s
        """
        update_values.append(username)

        cursor.execute(query, tuple(update_values))

        conn.commit()
        if cursor.rowcount > 0:
            updated_fields = []
            if new_mac_address is not None:
                updated_fields.append(f"new_mac_address: {new_mac_address}")
            if name is not None:
                updated_fields.append(f"new_name: {name}")
            print(f"Updated voucher with username: {username}, {', '.join(updated_fields)}")
            return jsonify({'success': True, 'message': f'Voucher with username {username} updated'}), 200
        else:
            print(f"No voucher found with username: {username}")
            return jsonify({'success': False, 'error': 'No voucher found'}), 404

    except mysql.connector.Error as e:
        print(f"DB Error during update: {str(e)}")  # Changed to print for consistency
        return jsonify({'success': False, 'error': 'Database error occurred'}), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")




@app.route('/update_voucher_settings', methods=['POST'])
def update_voucher_settings():
    """
    Update speed_limit and/or expire_time for a voucher.
    Identifies voucher by username or mac_address.
    Also updates radreply table if speed_limit is changed.
    """
    try:
        data = request.json
        username = data.get('username')
        mac_address = data.get('mac_address')
        speed_limit = data.get('speed_limit')  # Optional
        expire_time_str = data.get('expire_time')  # Optional, ISO8601 format

        # Need at least one identifier
        if not username and not mac_address:
            return jsonify(convert_decimals({'success': False, 'error': 'Either username or mac_address is required'})), 400

        # Need at least one field to update
        if speed_limit is None and expire_time_str is None:
            return jsonify(convert_decimals({'success': False, 'error': 'At least one of speed_limit or expire_time must be provided'})), 400

        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)

        # Find the voucher first
        if username:
            cursor.execute("SELECT username, mac_address, speed_limit FROM vouchers WHERE username = %s", (username,))
        else:
            cursor.execute("SELECT username, mac_address, speed_limit FROM vouchers WHERE mac_address = %s", (mac_address,))
        
        voucher = cursor.fetchone()
        if not voucher:
            return jsonify(convert_decimals({'success': False, 'error': 'Voucher not found'})), 404

        voucher_username = voucher['username']
        old_speed_limit = voucher['speed_limit']

        # Build UPDATE query for vouchers table
        update_fields = []
        update_values = []
        
        if speed_limit is not None:
            update_fields.append("speed_limit = %s")
            update_values.append(speed_limit)
        
        if expire_time_str is not None:
            try:
                # Parse ISO8601 format
                expire_time = datetime.fromisoformat(expire_time_str.replace('Z', '+00:00'))
                update_fields.append("expire_time = %s")
                update_values.append(expire_time)
            except ValueError:
                return jsonify(convert_decimals({'success': False, 'error': 'Invalid expire_time format. Use ISO8601 format.'})), 400
        
        update_fields.append("updated_at = %s")
        update_values.append(datetime.now())
        update_values.append(voucher_username)

        # Update vouchers table
        query = f"""
            UPDATE vouchers 
            SET {', '.join(update_fields)}
            WHERE username = %s
        """
        cursor.execute(query, tuple(update_values))

        # Update radreply table if speed_limit changed
        if speed_limit is not None and speed_limit != old_speed_limit:
            # Delete old speed limit entry
            cursor.execute(
                "DELETE FROM radreply WHERE username = %s AND attribute = 'Mikrotik-Rate-Limit'",
                (voucher_username,)
            )
            # Insert new speed limit
            cursor.execute(
                "INSERT INTO radreply (username, attribute, op, value) VALUES (%s, 'Mikrotik-Rate-Limit', ':=', %s)",
                (voucher_username, speed_limit)
            )

        conn.commit()
        
        updated_fields = []
        if speed_limit is not None:
            updated_fields.append(f"speed_limit: {speed_limit}")
        if expire_time_str is not None:
            updated_fields.append(f"expire_time: {expire_time_str}")
        
        print(f"Updated voucher settings for username: {voucher_username}, {', '.join(updated_fields)}")
        return jsonify(convert_decimals({
            'success': True, 
            'message': 'Voucher settings updated successfully',
            'username': voucher_username,
            'updated_fields': updated_fields
        })), 200

    except mysql.connector.Error as e:
        print(f"DB Error during update_voucher_settings: {str(e)}")
        return jsonify(convert_decimals({'success': False, 'error': 'Database error occurred'})), 500
    finally:
        if 'conn' in locals() and conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")

@app.route('/search_payments', methods=['GET'])
def search_payments():
    phone = request.args.get('phone')
    
    if not phone:
        return jsonify(convert_decimals({"error": "Phone number is required"})), 400
    
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Search for payments with exact phone number match
        query = """
            SELECT id, location, amount, duration, username, phone, timestamp
            FROM payments 
            WHERE phone = %s
            ORDER BY timestamp DESC
        """
        cursor.execute(query, (phone,))
        payments = cursor.fetchall()
        
        return jsonify(convert_decimals({
            "payments": payments,
            "count": len(payments),
            "search_term": phone,
            "message": f"Found {len(payments)} payments matching phone number '{phone}'"
        }))
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

@app.route('/fetch_technician_payments_summary', methods=['GET'])
def fetch_technician_payments_summary():
    try:
        # Accept single location or comma-separated multiple locations
        location = request.args.get('location')
        locations = request.args.get('locations')  # Comma-separated string

        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)

        now = datetime.now()

        # Build location filter
        location_filter = ""
        location_params = []
        if locations:
            loc_list = [loc.strip() for loc in locations.split(',') if loc.strip()]
            if loc_list:
                placeholders = ','.join(['%s'] * len(loc_list))
                location_filter = f" AND location IN ({placeholders})"
                location_params = loc_list
        elif location:
            location_filter = " AND location = %s"
            location_params = [location]

        # Today (includes test phone 12345678)
        today = now.date()
        cursor.execute(f"""
            SELECT SUM(amount) as total_today 
            FROM payments 
            WHERE DATE(timestamp) = %s {location_filter}
        """, [today] + location_params)
        row_today = cursor.fetchone()
        total_today = row_today['total_today'] if row_today and row_today['total_today'] else 0.0

        # Last 24 hours
        last_24_hours = now - timedelta(hours=24)
        cursor.execute(f"""
            SELECT SUM(amount) as total_last_24 
            FROM payments 
            WHERE timestamp >= %s {location_filter}
        """, [last_24_hours] + location_params)
        row_last24 = cursor.fetchone()
        total_last_24 = row_last24['total_last_24'] if row_last24 and row_last24['total_last_24'] else 0.0

        # Last month
        last_month = now.replace(day=1) - timedelta(days=1)
        start_of_last_month = last_month.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end_of_last_month = last_month.replace(hour=23, minute=59, second=59, microsecond=0)
        cursor.execute(f"""
            SELECT SUM(amount) as total_last_month 
            FROM payments 
            WHERE timestamp >= %s AND timestamp <= %s {location_filter}
        """, [start_of_last_month, end_of_last_month] + location_params)
        row_last_month = cursor.fetchone()
        total_last_month = row_last_month['total_last_month'] if row_last_month and row_last_month['total_last_month'] else 0.0

        # This month
        start_of_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        cursor.execute(f"""
            SELECT SUM(amount) as total_this_month 
            FROM payments 
            WHERE timestamp >= %s AND timestamp < %s {location_filter}
        """, [start_of_month, now] + location_params)
        row_this_month = cursor.fetchone()
        total_this_month = row_this_month['total_this_month'] if row_this_month and row_this_month['total_this_month'] else 0.0

        # This year
        start_of_year = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        cursor.execute(f"""
            SELECT SUM(amount) as total_year 
            FROM payments 
            WHERE timestamp >= %s {location_filter}
        """, [start_of_year] + location_params)
        row_year = cursor.fetchone()
        total_year = row_year['total_year'] if row_year and row_year['total_year'] else 0.0

        # Daily average for this month
        days_in_month = (now - start_of_month).days + 1
        daily_average_this_month = total_this_month / days_in_month if days_in_month > 0 else 0.0

        return jsonify(convert_decimals({
            "success": True,
            "summary": {
                "today": total_today,
                "last_24_hours": total_last_24,
                "last_month": total_last_month,
                "this_month": total_this_month,
                "daily_average_this_month": daily_average_this_month,
                "this_year": total_year
            },
            "location": location,
            "locations": locations,
            "message": "Technician payments summary (includes test phone)"
        })), 200

    except mysql.connector.Error as err:
        print(f"DB Error during fetch: {str(err)}")
        return jsonify(convert_decimals({"success": False, "error": "Database error occurred"})), 500
    finally:
        if conn.is_connected():
            cursor.close()
            conn.close()
            print("Database connection closed.")

@app.route('/get_voucher_by_phone', methods=['GET'])
def get_voucher_by_phone():
    phone = request.args.get('phone')

    if not phone:
        return jsonify(convert_decimals({"error": "Phone number is required"})), 400

    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)

        # Query to get the latest voucher (username) for the given phone number
        query = """
            SELECT username
            FROM payments
            WHERE phone = %s
            ORDER BY timestamp DESC
            LIMIT 1
        """
        cursor.execute(query, (phone,))
        result = cursor.fetchone()

        if not result or not result.get('username'):
            return jsonify(convert_decimals({"error": "No voucher found for this phone number"})), 404

        voucher_code = result['username']
        return jsonify(convert_decimals({"voucher_code": voucher_code}))

    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500

    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()

@app.route('/location_data', methods=['GET'])
def get_location_data():
    location = request.args.get('location')
    
    if not location:
        return jsonify({"error": "Location parameter is required"}), 400
    
    try:
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Query to get all data from location table for a specific location
        query = """
            SELECT username, location, speed_limit, session_timeout
            FROM location 
            WHERE location = %s
            ORDER BY username ASC
        """
        cursor.execute(query, (location,))
        location_data = cursor.fetchall()
        
        return jsonify({
            "data": location_data,
            "count": len(location_data),
            "location": location,
            "message": f"Found {len(location_data)} records for location '{location}'"
        })
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
        
    finally:
        if db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/fetch_superagent_payments', methods=['GET'])
def fetch_superagent_payments():
    try:
        # Get locations parameter for superagents
        locations = request.args.getlist('locations')
        
        if not locations:
            return jsonify(convert_decimals({"error": "Locations parameter is required"})), 400
        
        db_connection = mysql.connector.connect(**db_config)
        cursor = db_connection.cursor(dictionary=True)
        
        # Get time threshold for recent payments (last 24 hours)
        time_threshold = datetime.now() - timedelta(hours=24)
        
        # Build query for multiple locations
        location_placeholders = ','.join(['%s'] * len(locations))
        query = f"""
            SELECT id, location, amount, duration, username, phone, timestamp
            FROM payments 
            WHERE timestamp >= %s AND location IN ({location_placeholders})
            AND phone <> '12345678'
            ORDER BY timestamp DESC
        """
        
        cursor.execute(query, [time_threshold] + locations)
        payments = cursor.fetchall()

        # Convert Decimal to float for JSON serialization
        for payment in payments:
            if 'amount' in payment and isinstance(payment['amount'], Decimal):
                payment['amount'] = float(payment['amount'])
            if 'duration' in payment and isinstance(payment['duration'], Decimal):
                payment['duration'] = float(payment['duration'])

        # Calculate total amount
        total_amount = sum(float(payment['amount']) if payment['amount'] is not None else 0.0 for payment in payments) if payments else 0.0

        return jsonify({
            "payments": payments,
            "count": len(payments),
            "total_amount": total_amount,
            "locations": locations,
            "message": f"Found {len(payments)} payments within last 24 hours across {len(locations)} locations with a total amount of {total_amount} TZS"
        })
        
    except mysql.connector.Error as err:
        return jsonify({"error": f"MySQL Error: {err}"}), 500
    except Exception as e:
        return jsonify({"error": f"Error: {str(e)}"}), 500
    finally:
        if 'db_connection' in locals() and db_connection.is_connected():
            cursor.close()
            db_connection.close()


@app.route('/check_mikrotik_status', methods=['POST'])
def check_mikrotik_status():
    """Check status of all MikroTik devices and update Firestore"""
    try:
        if db is None:
            return jsonify({'error': 'Firestore not initialized'}), 500

        # Get all MikroTik devices from Firestore
        devices_ref = db.collection('mikrotik_devices')
        devices = devices_ref.stream()

        checked_count = 0
        online_count = 0
        offline_count = 0
        results = []

        for device_doc in devices:
            device_data = device_doc.to_dict()
            device_id = device_doc.id
            ip_address = device_data.get('ipAddress', '')
            device_name = device_data.get('name', 'Unknown')

            if not ip_address:
                logging.warning(f"Device {device_name} has no IP address")
                continue

            # Ping the device (2 packets)
            try:
                result = subprocess.run(
                    ['ping', '-c', '2', '-W', '2', ip_address],
                    capture_output=True,
                    timeout=5
                )
                is_online = result.returncode == 0

                # Update Firestore
                update_data = {
                    'status': 'online' if is_online else 'offline',
                    'lastChecked': firestore.SERVER_TIMESTAMP,
                }
                
                if is_online:
                    update_data['lastSeen'] = firestore.SERVER_TIMESTAMP
                    online_count += 1
                else:
                    offline_count += 1

                devices_ref.document(device_id).update(update_data)
                checked_count += 1

                results.append({
                    'id': device_id,
                    'name': device_name,
                    'ip': ip_address,
                    'status': 'online' if is_online else 'offline'
                })

                logging.info(f"Checked {device_name} ({ip_address}): {'online' if is_online else 'offline'}")

            except subprocess.TimeoutExpired:
                # Device timeout - mark as offline
                devices_ref.document(device_id).update({
                    'status': 'offline',
                    'lastChecked': firestore.SERVER_TIMESTAMP,
                })
                offline_count += 1
                checked_count += 1
                results.append({
                    'id': device_id,
                    'name': device_name,
                    'ip': ip_address,
                    'status': 'offline'
                })
                logging.warning(f"Device {device_name} ({ip_address}) timed out")

            except Exception as e:
                logging.error(f"Error checking {device_name} ({ip_address}): {e}")

        return jsonify({
            'success': True,
            'checked': checked_count,
            'online': online_count,
            'offline': offline_count,
            'results': results,
            'message': f'Checked {checked_count} devices: {online_count} online, {offline_count} offline'
        })

    except Exception as e:
        logging.error(f"Error in check_mikrotik_status: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/check_single_mikrotik', methods=['POST'])
def check_single_mikrotik():
    """Check status of a single MikroTik device"""
    try:
        if db is None:
            return jsonify({'error': 'Firestore not initialized'}), 500

        data = request.json
        device_id = data.get('deviceId')
        ip_address = data.get('ipAddress')

        if not device_id or not ip_address:
            return jsonify({'error': 'deviceId and ipAddress are required'}), 400

        # Ping the device
        result = subprocess.run(
            ['ping', '-c', '2', '-W', '2', ip_address],
            capture_output=True,
            timeout=5
        )
        is_online = result.returncode == 0

        # Update Firestore
        update_data = {
            'status': 'online' if is_online else 'offline',
            'lastChecked': firestore.SERVER_TIMESTAMP,
        }
        
        if is_online:
            update_data['lastSeen'] = firestore.SERVER_TIMESTAMP

        db.collection('mikrotik_devices').document(device_id).update(update_data)

        return jsonify({
            'success': True,
            'deviceId': device_id,
            'ipAddress': ip_address,
            'status': 'online' if is_online else 'offline',
            'message': f'Device is {"online" if is_online else "offline"}'
        })

    except subprocess.TimeoutExpired:
        db.collection('mikrotik_devices').document(device_id).update({
            'status': 'offline',
            'lastChecked': firestore.SERVER_TIMESTAMP,
        })
        return jsonify({
            'success': True,
            'deviceId': device_id,
            'ipAddress': ip_address,
            'status': 'offline',
            'message': 'Device timed out'
        })

    except Exception as e:
        logging.error(f"Error in check_single_mikrotik: {e}")
        return jsonify({'error': str(e)}), 500




if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False) # Add debug=True for development
 
