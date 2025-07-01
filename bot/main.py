import time
import os
import eel

from engine.features import *
from engine.command import speak

def start():
	eel.init("www")
	playAssistantSound()
	os.system('firefox --new-window "http://localhost:8000/index.html" &')
	eel.start("index.html", mode=None, host='localhost', block=True)

