import audioop
from riva_services import tts_service
from riva.client.proto.riva_audio_pb2 import AudioEncoding
from config import AVAILABLE_VOICES
import logging
import asyncio

logger = logging.getLogger(__name__)

async def generate_tts_response(text, language_code="en-US", voice_name=None):
    try:
        if language_code not in AVAILABLE_VOICES:
            raise ValueError(f"No voices available for language code: {language_code}")

        logger.info(f"Using voice: {voice_name}")
        logger.info(f"Using text: {text}")
        logger.info(f"Using language code: {language_code}")

        sample_rate_hz = 8000 
        
        responses = tts_service.synthesize_online(
            text,
            voice_name=voice_name,
            encoding=AudioEncoding.LINEAR_PCM, 
            language_code=language_code,
            sample_rate_hz=sample_rate_hz,
        )
        
        for response in responses:
            mulaw_audio = audioop.lin2ulaw(response.audio, 2)
            yield mulaw_audio
            await asyncio.sleep(0.01)

    except Exception as e:
        logger.exception(f"Error generating TTS response: {str(e)}")
        yield b''  