# say.py OUT.wav TEXT  — vowelled text in, wav out (vowels as written)
import sys, soundfile as sf
from tts_arabic import tts
wave = tts(sys.argv[2], speaker=1, pace=0.9, vowelizer=None, model_id="fastpitch")
sf.write(sys.argv[1], wave, 22050)
