import openai
import random
import multiprocessing as mp
# import boto3
import time
from datetime import datetime
import os
import requests
import httpx
import asyncio
from concurrent.futures import ThreadPoolExecutor
import concurrent.futures

# Initialize CloudWatch client
region = os.getenv('AWS_REGION', 'us-west-2')
# instance_id = "i-0b70add5aa9fb02bd"  # This should be obtained dynamically
# cloudwatch = boto3.client('cloudwatch', region_name=region)

# Read sample text
with open('sample_text.txt', 'r') as f:
    text = f.read()

def make_request(_):
    try:
        # Create client inside the worker process
        base_url = os.getenv('SGLANG_ROUTER_URL', 'http://localhost:8000') + '/v1'
        client = openai.Client(
            base_url=base_url,
            api_key="None"
        )
        
        start_time = time.time()
        
        # Sample random number of characters between 100 and 10000
        num_chars = random.randint(100, 10000)
        
        # Sample random text
        start_idx = random.randint(0, max(0, len(text) - num_chars))
        sample = text[start_idx:start_idx + num_chars]
        
        response = client.chat.completions.create(
            model=os.getenv('MODEL_NAME', 'meta-llama/Meta-Llama-3.1-8B-Instruct'),
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": f"Please analyze and discuss the meaning of this passage: {sample}"},
            ],
            temperature=0,
            max_tokens=256,
        )
        
        end_time = time.time()
        latency = end_time - start_time
        
        # Create metrics data
        metric_data = [
            {
                'MetricName': 'ClientNewSequences',
                'Value': 1,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
            },
            {
                'MetricName': 'ClientNewTokens', 
                'Value': response.usage.prompt_tokens,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
            },
            {
                'MetricName': 'ClientTokensProcessed',
                'Value': response.usage.completion_tokens,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
            },
            {
                'MetricName': 'ClientGenerationThroughput',
                'Value': response.usage.completion_tokens / latency,
                'Unit': 'Count/Second',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
            },
            {
                'MetricName': 'ClientLatency',
                'Value': latency,
                'Unit': 'Seconds',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
            }
        ]
        
        # Send metrics to CloudWatch
        # cloudwatch.put_metric_data(
        #     Namespace='SGLang/Workers',
        #     MetricData=metric_data
        # )
        
        print(f"Request completed in {latency:.2f}s")
        print(f"Response - prompt tokens: {response.usage.prompt_tokens}, completion tokens: {response.usage.completion_tokens}")
            
    except Exception as e:
        print(f"Error occurred: {e}")

def get_worker_count(elapsed_minutes, max_workers):
    return max_workers
    # Start with 1 worker for first minute
    if elapsed_minutes <= 1:
        return 1
    # Ramp up phase (1-10 minutes)
    elif elapsed_minutes <= 10:
        return 1 + int(((elapsed_minutes - 1) / 9) * (max_workers - 1))
    # Peak phase (10-14 minutes) 
    elif elapsed_minutes <= 14:
        return max_workers
    # Ramp down phase (14-24 minutes)
    elif elapsed_minutes <= 24:
        return int(((24 - elapsed_minutes) / 10) * max_workers)
    else:
        return 0

def main():
    max_workers = os.cpu_count() or 1
    start_time = time.time()
    print(f"Starting stress test with max {max_workers} workers")
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = set()
        while True:
            elapsed_minutes = (time.time() - start_time) / 60
            if elapsed_minutes >= 24:  # Total test duration of 24 minutes
                break
                
            target_workers = get_worker_count(elapsed_minutes, max_workers)
            current_workers = len(futures)
            
            # Add workers if needed
            if current_workers < target_workers:
                futures.add(executor.submit(make_request, None))
            # Remove workers if needed    
            elif current_workers > target_workers:
                if futures:
                    futures.pop()
                    
            # Wait for any completed futures and remove them
            done, futures = concurrent.futures.wait(
                futures,
                timeout=0.1,
                return_when=concurrent.futures.FIRST_COMPLETED
            )
            
            # Submit new requests to maintain target worker count
            while len(futures) < target_workers:
                futures.add(executor.submit(make_request, None))
                
            print(f"Current workers: {len(futures)}, Target: {target_workers}")
            time.sleep(1)  # Small delay to prevent tight loop

if __name__ == "__main__":
    main()