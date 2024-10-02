import asyncio
import json
import base64
from fastapi import WebSocket
import logging
from audio_processing import AudioProcessor
from tts_streaming import TTSStreamer
from conversation_manager import ConversationManager

logger = logging.getLogger(__name__)

async def handle_websocket_connection(websocket: WebSocket, initial_greeting: str):
    await websocket.accept()
    logger.info("WebSocket connection established")
    
    stop_event = asyncio.Event()
    tts_streamer = TTSStreamer(websocket)
    conversation_manager = ConversationManager(websocket, tts_streamer)
    audio_processor = AudioProcessor(conversation_manager)
    conversation_manager.set_audio_processor(audio_processor)
    
    stream_sid = None

    try:
        audio_processor.configure_stream()


        recognition_thread = audio_processor.start_recognition_thread(stop_event)


        process_results_task = asyncio.create_task(conversation_manager.process_results(stop_event))

        while not stop_event.is_set():
            try:
                message = await asyncio.wait_for(websocket.receive_text(), timeout=0.1)
                data = json.loads(message)
                logger.debug(f"Received WebSocket message: {data['event']}")
                
                if data['event'] == 'connected':
                    logger.info(f"Connected: {data}")
                
                elif data['event'] == 'start':
                    stream_sid = data['start']['streamSid']
                    logger.info(f"Call started. StreamSid: {stream_sid}")
                    conversation_manager.set_stream_sid(stream_sid)
                    
                    logger.info(f"Sending initial greeting: {initial_greeting}")
                    await conversation_manager.send_initial_greeting(initial_greeting, stream_sid)
                
                elif data['event'] == 'media':
                    mulaw_audio = base64.b64decode(data['media']['payload'])
                    audio_processor.process_audio(mulaw_audio)
                
                elif data['event'] == 'stop':
                    logger.info(f"Call ended. StreamSid: {stream_sid}")
                    break
                
                elif data['event'] == 'mark':
                    logger.info(f"Mark received: {data['mark']}")
                    if data['mark']['name'] in ['bot_speaking_start', 'bot_speaking_end']:
                        await tts_streamer.handle_mark(data['mark'])
                        if data['mark']['name'] == 'bot_speaking_end':
                            conversation_manager.bot_finished_speaking()
                
                elif data['event'] == 'dtmf':
                    logger.info(f"DTMF received: {data['dtmf']}")
                
            except asyncio.TimeoutError:
                continue

    except Exception as e:
        logger.exception(f"Error in WebSocket connection: {str(e)}")
    finally:
        stop_event.set()
        if 'recognition_thread' in locals() and recognition_thread:
            recognition_thread.join()
        if 'process_results_task' in locals() and process_results_task:
            await process_results_task
        await websocket.close()
        logger.info(f"WebSocket connection closed for StreamSid: {stream_sid}")