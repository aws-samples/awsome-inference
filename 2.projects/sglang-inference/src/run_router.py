import time
import subprocess
import requests
import argparse
from typing import Optional
import boto3
import json
import os

def get_asg_instance_ips() -> list[str]:
    """Get private IPs of all instances in the ASG."""
    # Get region from environment variable or use instance metadata
    region = os.getenv('AWS_REGION')
    if not region:
        # Try to get region from instance metadata
        try:
            import urllib.request
            token = urllib.request.urlopen(
                urllib.request.Request(
                    "http://169.254.169.254/latest/api/token",
                    headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
                    method="PUT"
                )
            ).read().decode()
            region = urllib.request.urlopen(
                urllib.request.Request(
                    "http://169.254.169.254/latest/meta-data/placement/region",
                    headers={"X-aws-ec2-metadata-token": token}
                )
            ).read().decode()
        except:
            region = "us-west-2"  # Fallback default
    
    ec2 = boto3.client('ec2', region_name=region)
    autoscaling = boto3.client('autoscaling', region_name=region)
    
    # Get ASG name by looking for Workers ASG pattern
    response = autoscaling.describe_auto_scaling_groups()
    asg_name = None
    for asg in response['AutoScalingGroups']:
        # Look for ASG names containing "Workers" (matches CDK-generated pattern)
        if 'Workers' in asg['AutoScalingGroupName'] and 'ASG' in asg['AutoScalingGroupName']:
            asg_name = asg['AutoScalingGroupName']
            break
    
    if not asg_name:
        return []
        
    # Get instance IDs from ASG
    response = autoscaling.describe_auto_scaling_groups(
        AutoScalingGroupNames=[asg_name]
    )
    
    instance_ids = []
    if response['AutoScalingGroups']:
        instance_ids = [
            instance['InstanceId'] 
            for instance in response['AutoScalingGroups'][0]['Instances']
            if instance['LifecycleState'] == 'InService'
        ]
    
    if not instance_ids:
        return []
        
    # Get private IPs of instances
    response = ec2.describe_instances(
        InstanceIds=instance_ids
    )
    
    private_ips = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            private_ips.append(instance['PrivateIpAddress'])
            
    return [f"http://{ip}:7999" for ip in private_ips]  # Assuming workers run on port 8001

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

def launch_router(host: str, port: int, worker_urls: list[str]) -> subprocess.Popen:
    """Launch the router process."""
    # Create log directory if it doesn't exist
    os.makedirs("/opt/sglang/logs", exist_ok=True)
    
    # Open log file in append mode
    log_file = open("/opt/sglang/logs/sglang.log", "a")
    
    command = [
        "python3",
        "-m", 
        "sglang_router.launch_router",
        "--host",
        host,
        "--port",
        str(port),
        "--worker-urls",
        " ".join(worker_urls)
    ]
    # Redirect both stdout and stderr to the log file
    return subprocess.Popen(
        command,
        stdout=log_file,
        stderr=log_file,
        bufsize=1  # Line buffered
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", type=str, default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    # Use 0.0.0.0 for the router URL
    router_url = f"http://0.0.0.0:{args.port}"
    print(f"Starting router at {router_url}")
    
    router_process: Optional[subprocess.Popen] = None
    
    try:
        while True:
            # Get worker IPs
            worker_urls = get_asg_instance_ips()
            print(f"Found worker URLs: {worker_urls}")
            
            # Launch router
            router_process = launch_router(args.host, args.port, worker_urls)
            
            # Wait for process to exit
            router_process.wait()
            
            # If we get here, process exited - restart after delay
            print("Router process exited, restarting in 5 seconds...")
            time.sleep(5)

    except KeyboardInterrupt:
        print("\nShutdown requested...")

    finally:
        # Cleanup
        print("Cleaning up...")
        if router_process and router_process.poll() is None:
            router_process.terminate()
            try:
                router_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                router_process.kill()

if __name__ == "__main__":
    main()
