import asyncio
import base64
from tts_generator import generate_tts_response
import logging
import time

logger = logging.getLogger(__name__)

class TTSStreamer:
    def __init__(self, websocket):
        self.websocket = websocket
        self.is_speaking = False
        self.tts_start_time = None

    async def send_mark(self, stream_sid, mark_name):
        await self.websocket.send_json({
            "event": "mark",
            "streamSid": stream_sid,
            "mark": {
                "name": mark_name
            }
        })
        logger.info(f"Sent '{mark_name}' Mark message")

    async def stream_tts(self, tts_stream, stream_sid):
        try:
            await self.send_mark(stream_sid, "bot_speaking_start")
            self.tts_start_time = time.time()

            async for audio_chunk in tts_stream:
                if not self.is_speaking:
                    logger.info("TTS audio stream interrupted")
                    break
                base64_audio = base64.b64encode(audio_chunk).decode('utf-8')
                await self.websocket.send_json({
                    "event": "media",
                    "streamSid": stream_sid,
                    "media": {
                        "payload": base64_audio
                    }
                })
                await asyncio.sleep(0.01)  


            await self.send_mark(stream_sid, "bot_speaking_end")
            
            logger.info("Finished streaming TTS audio")
        except Exception as e:
            logger.exception(f"Error in stream_tts: {str(e)}")

    async def send_tts_response(self, text, stream_sid):
        logger.info(f"Generating TTS for: {text}")
        tts_stream = generate_tts_response(text, language_code="en-US", voice_name="English-US.Female-1")
        
        self.is_speaking = True
        
        await self.stream_tts(tts_stream, stream_sid)

    async def handle_mark(self, mark_data):
        logger.info(f"Received mark message: {mark_data}")
        mark_name = mark_data.get('name')
        
        if mark_name == 'bot_speaking_start':
            self.tts_start_time = time.time()
            logger.info("Bot started speaking")
        elif mark_name == 'bot_speaking_end':
            if self.tts_start_time is not None:
                tts_end_time = time.time()
                tts_duration = tts_end_time - self.tts_start_time
                logger.info(f"TTS duration: {tts_duration:.2f} seconds")
                logger.info(f"Completed sending TTS response to caller")
                self.tts_start_time = None
                self.is_speaking = False
