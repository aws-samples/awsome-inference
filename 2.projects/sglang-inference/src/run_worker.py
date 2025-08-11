#!/opt/sglang/venv/bin/python
import time
import subprocess
import requests
import argparse
from typing import Optional
import os

def find_available_port():
    import socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]

def launch_worker(host: str, port: int, model_name: str, gpu_id: int, extra_args: list[str] = None) -> subprocess.Popen:
    """Launch a worker server on specified GPU."""
    # Create log directory if it doesn't exist
    os.makedirs("/opt/sglang/logs", exist_ok=True)
    
    # Open log file in append mode
    log_file = open("/opt/sglang/logs/sglang.log", "a")
    command = [
        "/opt/sglang/venv/bin/python",
        "-m",
        "sglang.launch_server",
        "--model-path",
        model_name,
        "--host",
        host,
        "--port",
        str(port),
    ]

    # Add any extra arguments
    if extra_args:
        command.extend(extra_args)
    
    # Get current environment and update it
    env = os.environ.copy()
    
    # Redirect both stdout and stderr to the log file
    return subprocess.Popen(
        command,
        stdout=log_file,
        stderr=log_file,
        bufsize=1,  # Line buffered
        env=env
    )

def wait_for_healthy(url: str, timeout: float = 600) -> bool:
    """Wait for server to become healthy."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(f"{url}/health")
            if response.status_code == 200:
                print(f"Server at {url} is healthy")
                return True
        except requests.RequestException:
            pass
        time.sleep(2)
    return False

def main():
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--gpu-id", type=int, default=0)
    parser.add_argument("--model", type=str, default="unsloth/Llama-3.2-1B") 
    parser.add_argument("--router-url", type=str, required=True)
    
    # Parse known args first to get required ones
    known_args, unknown_args = parser.parse_known_args()

    # Get EC2 private IP from metadata service using IMDSv2
    try:
        # Get token first
        token_response = requests.put(
            "http://169.254.169.254/latest/api/token",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
        )
        token = token_response.text

        # Use token to get private IP
        ec2_private_ip = requests.get(
            "http://169.254.169.254/latest/meta-data/local-ipv4",
            headers={"X-aws-ec2-metadata-token": token}
        ).text
    except:
        print("Failed to get EC2 private IP, falling back to 0.0.0.0")
        ec2_private_ip = "0.0.0.0"

    # Start worker
    worker_port = "7999"
    worker_url = f"http://{ec2_private_ip}:{worker_port}"
    print(f"Starting worker at {worker_url} on GPU {known_args.gpu_id}")
    
    worker_process: Optional[subprocess.Popen] = None
    
    worker_process = launch_worker(ec2_private_ip, worker_port, known_args.model, known_args.gpu_id, unknown_args)

    # Wait for worker to be healthy
    if not wait_for_healthy(worker_url):
        print("Worker failed to start")
        return

    # Register with router
    max_retries = 100
    retry_delay = 5  # seconds
    for attempt in range(max_retries):
        try:
            response = requests.post(f"{known_args.router_url}/add_worker?url={worker_url}")
            if response.status_code == 200:
                print(f"Successfully registered with router at {known_args.router_url}")
                break
            else:
                print(f"Failed to register with router (attempt {attempt + 1}/{max_retries}): {response.status_code} - {response.text}")
                if attempt == max_retries - 1:  # Last attempt
                    print("Max retries exceeded. Giving up.")
                    return
        except requests.RequestException as e:
            print(f"Error connecting to router (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt == max_retries - 1:  # Last attempt
                print("Max retries exceeded. Giving up.")
                return
        
        print(f"Retrying in {retry_delay} seconds...")
        time.sleep(retry_delay)

if __name__ == "__main__":
    main()
