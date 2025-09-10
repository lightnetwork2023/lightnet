#!/usr/bin/env python3
import mysql.connector
from datetime import datetime

# MySQL connection details
mysql_config = {
    'user': 'radius',            # MySQL username
    'password': 'ROCKY221122',  # MySQL password
    'host': 'localhost',         # MySQL host
    'database': 'radius'         # RADIUS database
}

try:
    # Connect to MySQL
    db_connection = mysql.connector.connect(**mysql_config)
    cursor = db_connection.cursor(dictionary=True)

    # First, clean up all completed sessions from radacct (regardless of username)
    print("Cleaning up all completed sessions from radacct...")
    cursor.execute("DELETE FROM radacct WHERE acctstoptime IS NOT NULL")
    deleted_sessions = cursor.rowcount
    print(f"Deleted {deleted_sessions} completed sessions from radacct.")
    
    # Commit the global cleanup
    db_connection.commit()

    # Query to find sessions where allowed time has been exceeded
    query = """
        SELECT username, expire_time
        FROM vouchers
        WHERE expire_time <= NOW();
    """

    cursor.execute(query)
    expired_vouchers = cursor.fetchall()

    if not expired_vouchers:
        print("No vouchers have expired.")
    else:
        for voucher in expired_vouchers:
            username = voucher['username']
            expire_time = voucher['expire_time']

            print(f"Deleting user {username}, expired at {expire_time}")

            # Delete from radcheck
            cursor.execute("DELETE FROM radcheck WHERE username = %s", (username,))
            
            # Delete from radreply
            cursor.execute("DELETE FROM radreply WHERE username = %s", (username,))
            
            # Delete from radpostauth
            cursor.execute("DELETE FROM radpostauth WHERE username = %s", (username,))
                   
            # Delete from active sessions
            cursor.execute("DELETE FROM active_sessions WHERE username = %s", (username,))

            # Delete from vouchers
            cursor.execute("DELETE FROM vouchers WHERE username = %s", (username,))
            
            # Commit deletions
            db_connection.commit()

            print(f"User {username} removed from radcheck, radreply, radpostauth, active_sessions, and vouchers.")

except mysql.connector.Error as mysql_err:
    print(f"MySQL Error: {mysql_err}")

except Exception as e:
    print(f"General Error: {e}")

finally:
    # Ensure MySQL connection is closed
    if db_connection.is_connected():
        cursor.close()
        db_connection.close()
