import time
import re
from datetime import datetime
import boto3
from typing import Dict, List
import os
from pathlib import Path
import requests

class LogMetricsPublisher:
    def __init__(self):
        # Get region from instance metadata
        token_response = requests.put(
            "http://169.254.169.254/latest/api/token", 
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
        )
        token = token_response.text
        region = requests.get(
            "http://169.254.169.254/latest/meta-data/placement/region",
            headers={"X-aws-ec2-metadata-token": token}
        ).text
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        # Get EC2 instance ID for metric dimensions
        self.instance_id = self._get_instance_id()
        # Use fixed ASG name for metrics
        self.asg_name = 'sglang-workers'
        
        # Update patterns to match new log format
        self.patterns = {
            'prefill': r'Prefill batch\. #new-seq: (\d+), #new-token: (\d+), #cached-token: (\d+)',
            'decode': r'Decode batch\. #running-req: (\d+), #token: (\d+).*gen throughput \(token/s\): ([\d.]+)',
        }

        # Track decode sequence metrics
        self.current_decode_tokens = 0
        self.current_throughputs = []
        
    def _get_instance_id(self) -> str:
        """Get EC2 instance ID from metadata service"""
        try:
            token_response = requests.put(
                "http://169.254.169.254/latest/api/token",
                headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
            )
            token = token_response.text
            
            instance_id = requests.get(
                "http://169.254.169.254/latest/meta-data/instance-id",
                headers={"X-aws-ec2-metadata-token": token}
            ).text
            return instance_id
        except:
            return "unknown"

    def publish_metrics(self, metrics: List[Dict]) -> None:
        """Publish metrics to CloudWatch"""
        try:
            # Publish metrics with instance ID dimension
            self.cloudwatch.put_metric_data(
                Namespace='SGLang/Workers',
                MetricData=[{
                    'MetricName': metric['name'],
                    'Value': metric['value'],
                    'Unit': metric['unit'],
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': self.instance_id},
                        {'Name': 'AutoScalingGroupName', 'Value': 'sglang-workers'}
                    ],
                    'StorageResolution': 1
                } for metric in metrics]
            )
            
            # Publish metrics without instance ID dimension for aggregation
            self.cloudwatch.put_metric_data(
                Namespace='SGLang/Workers',
                MetricData=[{
                    'MetricName': metric['name'],
                    'Value': metric['value'],
                    'Unit': metric['unit'],
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {'Name': 'AutoScalingGroupName', 'Value': 'sglang-workers'}
                    ],
                    'StorageResolution': 1
                } for metric in metrics]
            )
        except Exception as e:
            print(f"Error publishing metrics to CloudWatch: {e}")

    def parse_line(self, line: str) -> List[Dict]:
        """Parse a log line and extract metrics"""
        metrics = []
        
        decode_match = re.search(self.patterns['decode'], line)
        if decode_match:
            # Update running totals for decode sequence
            self.current_decode_tokens = int(decode_match.group(2))
            self.current_throughputs.append(float(decode_match.group(3)))
            return []  # Don't publish metrics yet
            
        # If we get here, it's not a decode line, so publish accumulated decode metrics if we have any
        if self.current_decode_tokens > 0:
            metrics.extend([
                {
                    'name': 'TokensProcessed',
                    'value': self.current_decode_tokens,
                    'unit': 'Count'
                },
                {
                    'name': 'GenerationThroughput',
                    'value': sum(self.current_throughputs) / len(self.current_throughputs),
                    'unit': 'Count/Second'
                }
            ])
            # Reset tracking variables
            self.current_decode_tokens = 0
            self.current_throughputs = []

        # Check for prefill metrics
        prefill_match = re.search(self.patterns['prefill'], line)
        if prefill_match:
            metrics.extend([
                {
                    'name': 'NewSequences',
                    'value': int(prefill_match.group(1)),
                    'unit': 'Count'
                },
                {
                    'name': 'NewTokens',
                    'value': int(prefill_match.group(2)),
                    'unit': 'Count'
                },
                {
                    'name': 'CachedTokens',
                    'value': int(prefill_match.group(3)),
                    'unit': 'Count'
                }
            ])
        
        return metrics

def monitor_logs():
    log_path = Path("/opt/sglang/logs/sglang.log")
    publisher = LogMetricsPublisher()
    
    # Create log file if it doesn't exist
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.touch(exist_ok=True)
    
    # Open file in read mode and seek to end
    with open(log_path, 'r') as f:
        f.seek(0, 2)  # Seek to end of file
        
        while True:
            lines = f.readlines()  # Read all available lines
            if lines:
                for line in lines:
                    metrics = publisher.parse_line(line.strip())
                    if metrics:
                        publisher.publish_metrics(metrics)
            else:
                time.sleep(0.1)  # Sleep briefly when no new lines

if __name__ == "__main__":
    monitor_logs()