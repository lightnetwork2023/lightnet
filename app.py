from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error

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

if __name__ == '__main__':
    app.run(debug=True, port=5000) 