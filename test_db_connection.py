import mysql.connector
from mysql.connector import Error

def test_database_connection():
    # Database configuration
    db_config = {
        'host': 'localhost',
        'user': 'your_username',
        'password': 'your_password',
        'database': 'your_database'
    }
    
    try:
        # Establish database connection
        connection = mysql.connector.connect(**db_config)
        
        if connection.is_connected():
            db_info = connection.get_server_info()
            print(f"Connected to MySQL Server version {db_info}")
            
            cursor = connection.cursor()
            cursor.execute("SELECT DATABASE();")
            database = cursor.fetchone()
            print(f"Connected to database: {database[0]}")
            
            # Check if vouchers table exists
            cursor.execute("SHOW TABLES LIKE 'vouchers';")
            if cursor.fetchone():
                print("Vouchers table exists")
                
                # Check table structure
                cursor.execute("DESCRIBE vouchers;")
                columns = cursor.fetchall()
                print("\nTable structure:")
                for column in columns:
                    print(column)
            else:
                print("Vouchers table does not exist")
                
    except Error as e:
        print(f"Error while connecting to MySQL: {e}")
        
    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()
            print("MySQL connection is closed")

if __name__ == "__main__":
    test_database_connection() 