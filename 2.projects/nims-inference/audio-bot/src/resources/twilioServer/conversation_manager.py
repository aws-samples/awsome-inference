import asyncio
import time
from llm_service import generate_llm_response
import logging

logger = logging.getLogger(__name__)

class ConversationManager:
    def __init__(self, websocket, tts_streamer):
        self.websocket = websocket
        self.tts_streamer = tts_streamer
        self.conversation_history = []
        self.transcript_count = 0
        self.SPEAKING_THRESHOLD = 3
        self.RESET_THRESHOLD_TIME = 0.5 
        self.last_transcript_time = None
        self.caller_speaking = False
        self.caller_speaking_start_time = None
        self.bot_speaking = False
        self.bot_speaking_start_time = None
        self.stream_sid = None
        self.audio_processor = None  

    def set_audio_processor(self, audio_processor):
        self.audio_processor = audio_processor

    def log_speaking_status(self):
        status = f"Bot: {'SPEAKING' if self.bot_speaking else 'silent'}, Caller: {'SPEAKING' if self.caller_speaking else 'silent'}"
        logger.info(f"Speaking status: {status}")

    async def process_results(self, stop_event):
        tts_task = None

        while not stop_event.is_set():
            try:
      
                if not self.audio_processor.result_queue.empty():
                    result = self.audio_processor.result_queue.get_nowait()
                    await self.websocket.send_json(result)

                    current_time = time.time()
                    if self.last_transcript_time and (current_time - self.last_transcript_time) > self.RESET_THRESHOLD_TIME:
                        self.transcript_count = 0
                        logger.info(f"Reset transcript count after {self.RESET_THRESHOLD_TIME} seconds of silence")

                    self.last_transcript_time = current_time
                    self.transcript_count += 1

                    if not self.caller_speaking and self.transcript_count >= self.SPEAKING_THRESHOLD:
                        self.caller_speaking = True
                        self.caller_speaking_start_time = time.time()
                        logger.info(f"Caller started speaking (after {self.SPEAKING_THRESHOLD} transcripts)")
                        self.log_speaking_status()

                    if result['is_final']:
                        llm_response = await self.handle_final_transcript(result)

                        if tts_task and not tts_task.done():
                            tts_task.cancel()
                        self.bot_speaking = True
                        self.bot_speaking_start_time = time.time()
                        logger.info("Bot started speaking")
                        self.log_speaking_status()
                        tts_task = asyncio.create_task(self.tts_streamer.send_tts_response(llm_response, self.stream_sid))
                        await tts_task


                await asyncio.sleep(0.01)  

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.exception(f"Error in process_results: {str(e)}")

        if tts_task and not tts_task.done():
            tts_task.cancel()

    async def handle_final_transcript(self, result):
        logger.info(f"Final transcript: {result['text']}")
        if self.caller_speaking:
            self.caller_speaking = False
            if self.caller_speaking_start_time:
                speaking_duration = time.time() - self.caller_speaking_start_time
                logger.info(f"Caller finished speaking. Duration: {speaking_duration:.2f} seconds")
            self.caller_speaking_start_time = None
            self.log_speaking_status()

        self.transcript_count = 0  

        if self.bot_speaking:
            logger.warning("Caller finished speaking while bot was still speaking")
   

        transcript = result["text"]
        self.conversation_history.append({"role": "user", "content": transcript})
        
        llm_response = await generate_llm_response(self.conversation_history)
        self.conversation_history.append({"role": "assistant", "content": llm_response})
        
        logger.info(f"LLM Response: {llm_response}")
        return llm_response

    def set_stream_sid(self, stream_sid):
        self.stream_sid = stream_sid

    def bot_finished_speaking(self):
        self.bot_speaking = False
        if self.bot_speaking_start_time is not None:
            duration = time.time() - self.bot_speaking_start_time
            logger.info(f"Bot finished speaking. Duration: {duration:.2f} seconds")
        else:
            logger.warning("Bot finished speaking, but start time was not set.")
        self.bot_speaking_start_time = None
        self.log_speaking_status()


    async def send_initial_greeting(self, greeting, stream_sid):
        self.bot_speaking = True
        self.bot_speaking_start_time = time.time()
        logger.info("Bot started speaking (initial greeting)")
        self.log_speaking_status()
        await self.tts_streamer.send_tts_response(greeting, stream_sid)