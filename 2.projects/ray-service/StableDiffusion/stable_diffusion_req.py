import requests

# TODO: Set your prompt here
prompt = "baby dancing"
input = "%20".join(prompt.split(" "))
resp = requests.get(f"http://127.0.0.1:8000/imagine?prompt={input}")

print("Write the response to `output.png`.")
with open("output.png", "wb") as f:
    f.write(resp.content)
