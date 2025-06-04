import requests
import json

def test_api_endpoints():
    base_url = 'http://lightnet.lightnetwork.pro:5000'
    endpoints = [
        '/vouchers',
        '/payments',
        '/active_sessions'
    ]
    
    print(f"Testing API endpoints at {base_url}")
    print("-" * 50)
    
    for endpoint in endpoints:
        try:
            print(f"\nTesting endpoint: {endpoint}")
            response = requests.get(f"{base_url}{endpoint}")
            
            print(f"Status Code: {response.status_code}")
            if response.status_code == 200:
                data = response.json()
                print(f"Response Data: {json.dumps(data, indent=2)}")
            else:
                print(f"Error Response: {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"Error connecting to {endpoint}: {str(e)}")
            
    print("\nTesting user info endpoint with a test username")
    try:
        test_username = "test_user"
        response = requests.get(f"{base_url}/get_user_info?username={test_username}")
        print(f"Status Code: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Response Data: {json.dumps(data, indent=2)}")
        else:
            print(f"Error Response: {response.text}")
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to get_user_info: {str(e)}")

if __name__ == "__main__":
    test_api_endpoints() 