from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
from datetime import datetime
import random
import string

app = Flask(__name__)
CORS(app)

# Database configuration
db_config = {
    'host': 'localhost',
    'user': 'your_username',
    'password': 'your_password',
    'database': 'your_database'
}

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

if __name__ == '__main__':
    app.run(debug=True, port=5000) 