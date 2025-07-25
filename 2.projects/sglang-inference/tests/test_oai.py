import openai
import random
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime
import pytz
import os

# Read sample text
with open('sample_text.txt', 'r') as f:
    text = f.read()
    words = text.split()

base_url = os.getenv('SGLANG_ROUTER_URL', 'http://localhost:8000') + '/v1'
client = openai.Client(base_url=base_url, api_key="None")

# Initialize lists to store metrics
timestamps = []
completion_tokens = []
prompt_tokens = []
request_counts = []

# Send multiple requests with random text samples
num_requests = 3*28
for i in range(num_requests):
    try:
        # Sample random text for each request
        start_idx = random.randint(0, max(0, len(words) - 100))
        sample = ' '.join(words[start_idx:start_idx + 100])
        
        response = client.chat.completions.create(
            model=os.getenv('MODEL_NAME', 'meta-llama/Meta-Llama-3.1-8B-Instruct'),
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": f"Please analyze and discuss the meaning of this passage: {sample}"},
            ],
            temperature=0,
            max_tokens=256,
        )

        # Log metrics
        timestamps.append(datetime.now(pytz.timezone('US/Pacific')))
        completion_tokens.append(response.usage.completion_tokens)
        prompt_tokens.append(response.usage.prompt_tokens)
        request_counts.append(1)

        print(f"\nRequest {i+1}/{num_requests}")
        print(f"Response: {response}")

    except Exception as e:
        print(f"\nError occurred: {e}")
        continue

    # Create visualization after each request
    df = pd.DataFrame({
        'timestamp': timestamps,
        'completion_tokens': completion_tokens,
        'prompt_tokens': prompt_tokens,
        'requests': request_counts
    })
    
    # Resample by minute and sum
    df_resampled = df.set_index('timestamp').resample('1min').sum()
    
    # Create the plot
    plt.figure(figsize=(12, 6))
    plt.plot(df_resampled.index, df_resampled.completion_tokens, label='Completion Tokens')
    plt.plot(df_resampled.index, df_resampled.prompt_tokens, label='Prompt Tokens')
    plt.plot(df_resampled.index, df_resampled.requests, label='Number of Requests')
    
    plt.title('API Usage Metrics Over Time (PST)')
    plt.xlabel('Time')
    plt.ylabel('Count')
    plt.legend()
    plt.xticks(rotation=45)
    plt.tight_layout()
    
    # Save the plot
    plt.savefig('api_metrics.png')
    plt.close()