from riva.client import ASRService, SpeechSynthesisService, Auth
from config import RIVA_ASR_SERVICE_ADDRESS, RIVA_TTS_SERVICE_ADDRESS

asr_auth = Auth(uri=f"{RIVA_ASR_SERVICE_ADDRESS}", use_ssl=True)
tts_auth = Auth(uri=f"{RIVA_TTS_SERVICE_ADDRESS}", use_ssl=True)
asr_service = ASRService(asr_auth)
tts_service = SpeechSynthesisService(tts_auth)