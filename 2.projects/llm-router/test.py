import os
from litellm import completion

os.environ["AWS_ACCESS_KEY_ID"] = ""
os.environ["AWS_SECRET_ACCESS_KEY"] = ""
os.environ["AWS_REGION_NAME"] = ""

response = completion(
  model="bedrock/anthropic.claude-3-sonnet-20240229-v1:0",
  messages=[{ "content": "Hello, how are you?","role": "user"}]
)

import pdb;pdb.set_trace()
