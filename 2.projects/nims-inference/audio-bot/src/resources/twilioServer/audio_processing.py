import audioop
from queue import Queue
import threading
from riva_services import asr_service
from riva.client.proto.riva_asr_pb2 import StreamingRecognitionConfig, RecognitionConfig
from riva.client.proto.riva_audio_pb2 import AudioEncoding
import logging

logger = logging.getLogger(__name__)

class AudioProcessor:
    def __init__(self, conversation_manager):
        self.audio_queue = Queue()
        self.config = None
        self.conversation_manager = conversation_manager
        self.result_queue = Queue()

    def configure_stream(self):
        self.config = StreamingRecognitionConfig(
            config=RecognitionConfig(
                encoding=AudioEncoding.LINEAR_PCM,
                sample_rate_hertz=8000,
                audio_channel_count=1,
                language_code="en-US",
                max_alternatives=1,
                enable_automatic_punctuation=True,
                enable_word_time_offsets=True,
            ),
            interim_results=True,
        )

    def process_audio(self, mulaw_audio):
        pcm_audio = audioop.ulaw2lin(mulaw_audio, 2)
        self.audio_queue.put(pcm_audio)

    def audio_generator(self, stop_event):
        while not stop_event.is_set():
            if not self.audio_queue.empty():
                yield self.audio_queue.get()


    def recognition_thread_func(self, stop_event):
        responses = asr_service.streaming_response_generator(
            audio_chunks=self.audio_generator(stop_event),
            streaming_config=self.config
        )
        for response in responses:
            for result in response.results:
                is_final = result.is_final
                transcript = result.alternatives[0].transcript if result.alternatives else ""
                confidence = result.alternatives[0].confidence if result.alternatives else 0.0
                
                log_level = logging.INFO if is_final else logging.DEBUG
                logger.log(log_level, f"{'Final' if is_final else 'Interim'} transcript: {transcript}")
                
                self.result_queue.put({
                    "event": "transcription",
                    "is_final": is_final,
                    "text": transcript,
                    "confidence": confidence
                })

    def start_recognition_thread(self, stop_event):
        recognition_thread = threading.Thread(target=self.recognition_thread_func, args=(stop_event,))
        recognition_thread.start()
        return recognition_thread