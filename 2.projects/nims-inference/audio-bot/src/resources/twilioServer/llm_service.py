import aiohttp
import logging
import json
from typing import List, Dict
import time
from datetime import datetime
from config import NIM_URL, NIM_MODEL, PIZZA_SIZES, PIZZA_TOPPINGS, CRUST_TYPES

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

logger.info(f"NIM URL: {NIM_URL}")
logger.info(f"NIM Model: {NIM_MODEL}")

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

role_prompt = role_prompt.format(tool_json=json.dumps(tools[0]["function"], indent=2))
logger.debug(f"Formatted role prompt: {role_prompt}")

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
        
        logger.debug(f"Payload being sent to NIM endpoint: {json.dumps(payload, indent=2)}")
        
        try:
            async with session.post(NIM_URL, json=payload, headers=headers) as response:
                logger.debug(f"Response status: {response.status}")
                logger.debug(f"Response headers: {response.headers}")
                if response.status == 200:
                    data = await response.json()
                    end_time = time.time()
                    logger.info(f"NIM endpoint call completed in {end_time - start_time:.2f} seconds")
                    logger.debug(f"Response data: {json.dumps(data, indent=2)}")
                    return data
                else:
                    logger.error(f"Error calling NIM endpoint: {response.status}")
                    response_text = await response.text()
                    logger.error(f"Response content: {response_text}")
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

    logger.debug(f"Raw LLM response: {json.dumps(response_data, indent=2)}")

    if 'choices' in response_data and len(response_data['choices']) > 0:
        full_response = response_data['choices'][0]['message']['content']
        logger.info(f"Full LLM response content: '{full_response}'")
        
        if '<function=' in full_response:
            logger.debug("Function call detected in the response")
            start_index = full_response.index('<function=')
            end_index = full_response.index('</function>') + 11
            function_call = full_response[start_index:end_index]
            
            logger.debug(f"Extracted function call: {function_call}")
            

            function_name = function_call.split('=')[1].split('>')[0]
            parameters = json.loads(function_call.split('>')[1].split('</function>')[0])
            
            logger.debug(f"Function name: {function_name}")
            logger.debug(f"Function parameters: {parameters}")
            

            if function_name == 'process_pizza_order':
                result = process_pizza_order(**parameters)
                logger.debug(f"Function call result: {result}")
                
            full_response = full_response[:start_index] + full_response[end_index:]
            logger.debug(f"Response after removing function call: {full_response}")
        
        end_time = time.time()
        logger.info(f"LLM response generation completed in {end_time - start_time:.2f} seconds")
        return full_response
    else:
        logger.warning("Unexpected response format from NIM endpoint")
        return "I'm sorry, I couldn't generate a response. Could you please try again?"

