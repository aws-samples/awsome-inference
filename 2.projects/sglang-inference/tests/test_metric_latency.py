import openai
import time
import boto3
import datetime
from datetime import timedelta
import random
import os

def get_cloudwatch_metrics(cloudwatch, start_time, end_time):
    metrics = {}
    metric_names = [
        'NewTokens',
        'NewSequences', 
        'CachedTokens',
        'TokensProcessed',
        'RunningRequests'
    ]
    
    for metric_name in metric_names:
        response = cloudwatch.get_metric_statistics(
            Namespace='SGLang/Workers',
            MetricName=metric_name,
            Dimensions=[],
            StartTime=start_time,
            EndTime=end_time,
            Period=60,
            Statistics=['Sum']
        )
        
        if response['Datapoints']:
            metrics[metric_name] = response['Datapoints'][0]['Sum']
        else:
            metrics[metric_name] = 0
            
    return metrics

def main():
    # Initialize clients
    base_url = os.getenv('SGLANG_ROUTER_URL', 'http://localhost:8000') + '/v1'
    client = openai.Client(base_url=base_url, api_key="None")
    cloudwatch = boto3.client('cloudwatch')
    # Read sample text
    with open('sample_text.txt', 'r') as f:
        text = f.read()
        words = text.split()
    
    # Generate unique number of requests to send (between 50-100 to be recognizable)
    num_requests = random.randint(1, 5)
    print(f"Will send {num_requests} requests")
    
    # Record start time
    start_time = datetime.datetime.utcnow()
    request_timestamps = []
    
    # Send requests
    for i in range(num_requests):
        try:
            # Sample random text for each request
            start_idx = random.randint(0, max(0, len(words) - 100))
            sample = ' '.join(words[start_idx:start_idx + 100])
            
            timestamp = datetime.datetime.utcnow()
            response = client.chat.completions.create(
                model=os.getenv('MODEL_NAME', 'meta-llama/Meta-Llama-3.1-8B-Instruct'),
                messages=[
                    {"role": "system", "content": "You are a helpful assistant."},
                    {"role": "user", "content": f"Please analyze and discuss the meaning of this passage: {sample}"},
                ],
                temperature=0,
                max_tokens=256,
            )
            request_timestamps.append(timestamp)
            print(f"\rSent request {i+1}/{num_requests}", end="", flush=True)
        except Exception as e:
            print(f"\nError occurred: {e}")
            continue
    
    print("\nAll requests sent. Waiting for CloudWatch metrics to aggregate...")
    
    # Poll CloudWatch until we see our metrics
    while True:
        current_time = datetime.datetime.utcnow()
        metrics = get_cloudwatch_metrics(
            cloudwatch,
            start_time,
            current_time
        )
        
        # Check if we've seen activity in any of the metrics
        total_activity = sum(metrics.values())
        
        if total_activity > 0:
            end_time = datetime.datetime.utcnow()
            client_latency = (end_time - start_time).total_seconds()
            print(f"\nMetrics detected in CloudWatch!")
            print(f"Time to appear in CloudWatch: {client_latency:.2f} seconds")
            
            # Print all metric values
            for metric_name, value in metrics.items():
                print(f"{metric_name}: {value}")
            
            # Get the actual CloudWatch timestamp for RunningRequests
            response = cloudwatch.get_metric_statistics(
                Namespace='SGLang/Workers',
                MetricName='RunningRequests',
                Dimensions=[],
                StartTime=start_time,
                EndTime=end_time,
                Period=60,
                Statistics=['Sum']
            )
            
            if response['Datapoints']:
                cw_timestamp = response['Datapoints'][0]['Timestamp']
                # Convert first_request_time to timezone-aware datetime
                first_request_time = min(request_timestamps).replace(tzinfo=datetime.timezone.utc)
                cloudwatch_latency = (cw_timestamp - first_request_time).total_seconds()
                print(f"CloudWatch reported latency: {cloudwatch_latency:.2f} seconds")
            break
        
        time.sleep(5)  # Poll every 5 seconds
        print(f"\rCurrent metrics: " + ", ".join([f"{k}: {v}" for k,v in metrics.items()]), end="", flush=True)

if __name__ == "__main__":
    main()