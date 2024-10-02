import json
import asyncio
import logging
import aiohttp
from typing import List, Dict
import time
from datetime import datetime
from config import NIM_URL, NIM_MODEL, PIZZA_SIZES, PIZZA_TOPPINGS, CRUST_TYPES

# Configure logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

logger.info(f"NIM URL: {NIM_URL}")
logger.info(f"NIM Model: {NIM_MODEL}")

# Define the single tool schema
tools = [
    {
        "type": "function",
        "function": {
            "name": "process_pizza_order",
            "description": "Process a pizza order with the given details",
            "parameters": {
                "type": "object",
                "properties": {
                    "size": {
                        "type": "string",
                        "description": "The size of the pizza",
                        "enum": PIZZA_SIZES
                    },
                    "toppings": {
                        "type": "array",
                        "items": {
                            "type": "string",
                            "enum": PIZZA_TOPPINGS
                        },
                        "description": "List of toppings for the pizza"
                    },
                    "crust": {
                        "type": "string",
                        "description": "The type of crust for the pizza",
                        "enum": CRUST_TYPES
                    }
                },
                "required": ["size", "toppings", "crust"]
            }
        }
    }
]

# System prompt
role_prompt = """Environment: pizza_ordering
Tools: process_pizza_order
Cutting Knowledge Date: December 2023
Today Date: [Current Date]

# Tool Instructions
- When you have gathered all necessary information for a pizza order, use the process_pizza_order function.

You have access to the following function:

Use the function 'process_pizza_order' to: Process a pizza order with the given details
{tool_json}

You must use the following function and the reply should contain the function call in the following format:
<{{start_tag}}={{function_name}}>{{parameters}}{{end_tag}}
where

start_tag => `<function`
parameters => a JSON dict with the function argument name as key and function argument value as value.
end_tag => `</function>`

Here is an example,
<function=process_pizza_order>{{"size": "medium", "toppings": ["cheese", "pepperoni"], "crust": "thin"}}</function>

Reminder:
- Function calls MUST follow the specified format
- Required parameters MUST be specified
- Only call one function at a time
- Put the entire function call reply on one line

You are a friendly, conversational AI assistant helping a caller order a pizza over the phone. 
Your task is to gather all necessary information for a pizza order, including size, toppings, and crust type.
Keep responses concise and natural. If the user doesn't provide all necessary details, ask for the missing information. Only ask one question at a time.
Don't mention the function or expose its usage to the user."""

# Format the role prompt with the tool JSON
role_prompt = role_prompt.format(tool_json=json.dumps(tools[0]["function"], indent=2))

def process_pizza_order(size: str, toppings: List[str], crust: str) -> Dict[str, bool]:
    logger.debug(f"Processing order: size={size}, toppings={toppings}, crust={crust}")
    result = {
        "size_valid": size.lower() in PIZZA_SIZES,
        "toppings_valid": all(topping.lower() in PIZZA_TOPPINGS for topping in toppings),
        "crust_valid": crust.lower() in CRUST_TYPES,
        "order_complete": True
    }
    logger.debug(f"Order processing result: {result}")
    return result

async def call_nim_endpoint(messages):
    start_time = time.time()
    logger.info("Calling NIM endpoint without streaming")
    async with aiohttp.ClientSession() as session:
        payload = {
            "model": NIM_MODEL,
            "messages": messages,
            "top_p": 0.9,
            "n": 1,
            "max_tokens": 300,
            "stream": False,
            "temperature": 0.7,
            "frequency_penalty": 1.0,
            "stop": ["\nHuman:", "\n\nHuman:"]
        }
        headers = {
            "accept": "application/json",
            "Content-Type": "application/json"
        }
        
        # Log the payload being sent
        logger.debug(f"Payload being sent to NIM endpoint: {json.dumps(payload, indent=2)}")
        
        try:
            async with session.post(NIM_URL, json=payload, headers=headers) as response:
                if response.status == 200:
                    data = await response.json()
                    end_time = time.time()
                    logger.info(f"NIM endpoint call completed in {end_time - start_time:.2f} seconds")
                    return data
                else:
                    logger.error(f"Error calling NIM endpoint: {response.status}")
                    response_content = await response.text()
                    logger.error(f"Response content: {response_content}")
                    logger.error(f"Response headers: {response.headers}")
                    return None
        except Exception as e:
            logger.exception(f"Exception when calling NIM endpoint: {str(e)}")
            return None
    
    end_time = time.time()
    logger.info(f"NIM endpoint call (including error handling) completed in {end_time - start_time:.2f} seconds")
    return None

async def generate_llm_response(conversation_history):
    start_time = time.time()
    logger.info(f"Starting LLM response generation")
    
    messages = [{"role": "system", "content": role_prompt}] + conversation_history
    logger.debug(f"Messages being sent to NIM: {json.dumps(messages, indent=2)}")
    
    response_data = await call_nim_endpoint(messages)
    
    if response_data is None:
        logger.warning("No data received from NIM endpoint")
        return "I'm sorry, I'm having trouble processing your request right now."

    # Log the raw response
    logger.info(f"Raw LLM response: {json.dumps(response_data, indent=2)}")

    if 'choices' in response_data and len(response_data['choices']) > 0:
        full_response = response_data['choices'][0]['message']['content']
        print(full_response)  # Print the full response
        logger.info(f"Full LLM response content: '{full_response}'")
        end_time = time.time()
        logger.info(f"LLM response generation completed in {end_time - start_time:.2f} seconds")
        return full_response
    else:
        logger.warning("Unexpected response format from NIM endpoint")
        return "I'm sorry, I couldn't generate a response. Could you please try again?"

async def main():
    print("Pizza Ordering System Test")
    print("Type 'exit' to quit the conversation")
    
    conversation_history = []
    
    while True:
        user_input = input("\nYou: ")
        if user_input.lower() == 'exit':
            logger.info("User requested to exit the conversation")
            break
        
        logger.info(f"User input: '{user_input}'")
        conversation_start_time = time.time()
        conversation_history.append({"role": "user", "content": user_input})
        response = await generate_llm_response(conversation_history)
        conversation_history.append({"role": "assistant", "content": response})
        conversation_end_time = time.time()
        logger.info(f"Full conversation turn completed in {conversation_end_time - conversation_start_time:.2f} seconds")

if __name__ == "__main__":
    logger.info("Starting Pizza Ordering System Test")
    asyncio.run(main())
    logger.info("Pizza Ordering System Test completed")