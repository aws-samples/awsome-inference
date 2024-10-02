import os


RIVA_ASR_SERVICE_ADDRESS = os.environ.get('RIVA_ASR_SERVICE_ADDRESS', 'nim.nebulex.dev:50051')
RIVA_TTS_SERVICE_ADDRESS = os.environ.get('RIVA_TTS_SERVICE_ADDRESS', 'nim.nebulex.dev:50051')
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN")

CHUNK_SIZE = 8000  
BYTES_PER_SAMPLE = 2 
CHUNK_BYTES = CHUNK_SIZE * BYTES_PER_SAMPLE

AVAILABLE_VOICES = {
    "en-US": [
        "English-US.Female-1",
        "English-US.Male-1",
        "English-US.Female-Neutral",
        "English-US.Male-Neutral",
        "English-US.Female-Angry",
        "English-US.Male-Angry",
        "English-US.Female-Calm",
        "English-US.Male-Calm",
        "English-US.Female-Fearful",
        "English-US.Female-Happy",
        "English-US.Male-Happy",
        "English-US.Female-Sad"
    ]
}

# NIM and Pizza ordering configuration
NIM_LLM_SERVICE_ADDRESS = os.environ.get("NIM_LLM_SERVICE_ADDRESS", "nim.nebulex.dev")
NIM_URL = f"https://{NIM_LLM_SERVICE_ADDRESS}/v1/chat/completions"
NIM_MODEL = "meta/llama-3.1-8b-instruct"

PIZZA_SIZES = ["small", "medium", "large"]
PIZZA_TOPPINGS = ["cheese", "pepperoni", "mushrooms", "onions", "sausage", "olives", "bell peppers"]
CRUST_TYPES = ["thin", "regular", "thick", "stuffed"]

