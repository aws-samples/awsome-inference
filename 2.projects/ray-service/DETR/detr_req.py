import requests

# TODO: Change this to your image path
image_path = "/your/image/path"

url = "http://127.0.0.1:8000"
files = {"image": open(image_path, "rb")}
response = requests.post(url, files=files)
print(response.text)