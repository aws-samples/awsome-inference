from fastapi import FastAPI, WebSocket, Request, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from twilio.twiml.voice_response import VoiceResponse, Connect
from twilio.request_validator import RequestValidator
from websocket_handler import handle_websocket_connection
import logging
from config import RIVA_ASR_SERVICE_ADDRESS, RIVA_TTS_SERVICE_ADDRESS, TWILIO_AUTH_TOKEN
from contextlib import asynccontextmanager
import urllib.parse
import json

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

validator = RequestValidator(TWILIO_AUTH_TOKEN)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"Starting server with Riva ASR service address: {RIVA_ASR_SERVICE_ADDRESS}")
    logger.info(f"Starting server with Riva TTS service address: {RIVA_TTS_SERVICE_ADDRESS}")
    yield

app = FastAPI(lifespan=lifespan)

@app.middleware("http")
async def validate_twilio_request(request: Request, call_next):
    if request.url.path in ["/answer", "/ws"]:

        twilio_signature = request.headers.get("X-Twilio-Signature")
        logger.info(f"Twilio signature: {twilio_signature}")
        

        url = str(request.url)
        https_url = url.replace("http://", "https://", 1)
        logger.info(f"Original URL: {url}")
        logger.info(f"HTTPS URL for validation: {https_url}")
        

        logger.info(f"Request method: {request.method}")
        logger.info(f"Content-Type: {request.headers.get('Content-Type')}")
        

        params = {}
        if request.method == "GET":
            params = dict(request.query_params)
        else:  # POST
            content_type = request.headers.get("Content-Type", "")
            if "application/x-www-form-urlencoded" in content_type:
                try:
                    form = await request.form()
                    params = dict(form)
                except Exception as e:
                    logger.error(f"Error parsing form data: {e}")
            elif "application/json" in content_type:
                try:
                    json_body = await request.json()
                    params = json_body
                except json.JSONDecodeError:
                    logger.error("Error decoding JSON body")
            else:
                body = await request.body()
                params = {"body": body.decode()}
        
        logger.info(f"Params before conversion: {params}")
        

        params = {k: str(v) for k, v in params.items()}
        
        logger.info(f"Params after conversion: {params}")
        

        if not validator.validate(https_url, params, twilio_signature):
            logger.warning(f"Invalid Twilio signature for request to {https_url}")
            raise HTTPException(status_code=403, detail="Invalid Twilio signature")
        
        logger.info(f"Valid Twilio signature for request to {https_url}")
    
    response = await call_next(request)
    return response

@app.get("/health")
async def health_check():
    return JSONResponse(content={"status": "healthy"}, status_code=200)

@app.post("/answer")
async def answer_call(request: Request):
    response = VoiceResponse()
    connect = Connect()
    connect.stream(url=f'wss://{request.headers["host"]}/ws')
    response.append(connect)
    logger.info(f"Sending TwiML response: {response}")
    return StreamingResponse(iter([str(response)]), media_type="application/xml")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    initial_greeting = "Welcome to our pizza ordering service! How can I help you order a delicious pizza today?"
    await handle_websocket_connection(websocket, initial_greeting)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=80)