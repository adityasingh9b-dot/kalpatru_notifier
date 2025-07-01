import eel
import speech_recognition as sr
import pyttsx3
import time

def speak(text):
	engine = pyttsx3.init()
	voices = engine.getProperty('voices')
	engine.setProperty('voice', voices[20].id)
	engine.setProperty('rate', 150)
	eel.DisplayMessage(text)
	engine.say(text)
	engine.runAndWait()


def notifyFrontendReady():
    print("✅ Frontend is ready (from JS notify)")
    
@eel.expose
def on_frontend_ready():
    print("✅ JS frontend called 'on_frontend_ready'")

@eel.expose
def takecommand():
	r = sr.Recognizer()
	with sr.Microphone() as source:
		print(" Listening... ")
		eel.DisplayMessage(" Listening... ")
		r.pause_threshold = 1
		r.adjust_for_ambient_noise(source)
	
		audio = r.listen(source, 10, 6)
	
	try:
		print('Recognizing...')
		eel.DisplayMessage('Recognizing...')
		query = r.recognize_google(audio, language='en-in')
		print(f"{query}")
		eel.DisplayMessage(query)
		time.sleep(2)
		

		
	except Exception as e:
		return" Unable to Listen! "
	
	return query.lower()

@eel.expose
def allCommands(message=1):

	if message == 1:
		query = takecommand()
	else:
		query = message

	if query == " Unable to Listen! ":
		speak("Sorry, I didn't catch that.")
		return

	# YouTube command has higher priority
	if "on youtube" in query:
		from engine.features import PlayYoutube
		PlayYoutube(query)

	elif "open" in query:
		from engine.features import openCommand
		openCommand(query)

	else:
		speak("Sorry, I couldn't understand the command.")
		print("Not Found")

	eel.ShowHood()





























