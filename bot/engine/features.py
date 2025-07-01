frontend_ready = False

import pygame
import os
import time
from engine.config import ASSISTANT_NAME
import pywhatkit as kit
import re
from engine.command import speak
import webbrowser
import sqlite3
import subprocess
from engine.helper import extract_yt_term
import pvporcupine
import pyaudio
import struct
import pyautogui as autogui
import eel

conn = sqlite3.connect("engine/Jarvis.db")  
cursor = conn.cursor()

@eel.expose
def notifyFrontendReady():
	global frontend_ready
	frontend_ready = True
	print("✅ Frontend is ready!")

@eel.expose
def startHotwordAfterFrontend():
	import time
	from engine import features
	
	while not features.frontend_ready:
		print("⌛ Waiting for frontend to be ready...")
		time.sleep(1)
	
	print("🚀 Frontend is ready! Starting hotword detection...")
	features.hotword()


@eel.expose
def playAssistantSound():
	music_dir = os.path.join("www", "assets", "audio", "sound.mpga")
	pygame.mixer.init()
	pygame.mixer.music.load(music_dir)
	pygame.mixer.music.play()
	
	while pygame.mixer.music.get_busy():
		pygame.time.Clock().tick(10)

@eel.expose
def openCommand(query):
	from engine.command import speak

	print("🔍 Query received:", query)
	query = query.lower().strip()
	
	if ASSISTANT_NAME.lower() in query:
		query = query.replace(ASSISTANT_NAME.lower(), '')
		
	query = query.replace("open", "").strip()
	app_name = query.strip()
	print("🔍 App name to search:", app_name)

	if app_name != "":
		try:
			cursor.execute('SELECT path FROM sys_command WHERE name = ?', (app_name,))
			results = cursor.fetchall()
			print("📁 sys_command results:", results)

			if len(results) != 0:
				path_to_run = results[0][0]
				print("📂 Command to run:", path_to_run)
				speak("Opening " + query)
				try:
					subprocess.Popen(path_to_run.split())
				except Exception as e:
					print("❌ Failed to open app:", e)
					speak("Unable to open the app.")
					
			else:
				cursor.execute("SELECT path FROM web_command WHERE name = ?", (app_name,))
				results = cursor.fetchall()
				print("🌐 web_command results:", results)

				if len(results) != 0:
					web_url = results[0][0]
					print("🌍 Opening website:", web_url)
					speak("Opening " + query)
					webbrowser.open(web_url)
				else:
					speak("App not found in system or web commands.")
					
		except Exception as e:
			speak("Something went wrong!")
			print("❌ Main Error:", e)

def PlayYoutube(query):
	search_term = extract_yt_term(query)
	speak("Playing " + search_term + " on YouTube")
	kit.playonyt(search_term)

@eel.expose
def triggerMic():
	try:
		if eel._exposed_functions.get("playAssistantSound"):
			eel.playAssistantSound()
		else:
			print("⚠️ playAssistantSound not exposed in JS yet!")

		if eel._exposed_functions.get("allCommands"):
			eel.allCommands()()
		else:
			print("⚠️ allCommands not exposed in JS yet!")

	except Exception as e:
		print("🔥 JS call error:", e)

@eel.expose
def hotword():
	global frontend_ready
	porcupine=None
	paud=None
	audio_stream=None
	
	try:
		time.sleep(5)
		porcupine = pvporcupine.create(keywords=['jarvis', 'alexa'])
		paud = pyaudio.PyAudio()
		audio_stream = paud.open(rate=porcupine.sample_rate, channels=1, format=pyaudio.paInt16, input=True, frames_per_buffer=porcupine.frame_length)
		
		while True:
			keyword = audio_stream.read(porcupine.frame_length)
			keyword = struct.unpack_from("h"*porcupine.frame_length, keyword)
			keyword_index = porcupine.process(keyword)

			if keyword_index >= 0:
				print("HotWord Detected!!!")
				triggerMic()

	except Exception as e:
		print(" Error Occured !!! ", e)
	
	finally:
		if porcupine is not None:
			porcupine.delete()
		if audio_stream is not None:
			audio_stream.close()
		if paud is not None:
			paud.terminate()

	
	
	
	
	
	
	
	
	
	
