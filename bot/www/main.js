$(document).ready(function () {
	eel.notifyFrontendReady();

	eel.expose(playAssistantSound);
	function playAssistantSound() {
		var audio = new Audio("assets/audio/sound.mpga");
		audio.play();
	}

	eel.expose(allCommands);
	function allCommands() {
		console.log("🎤 Listening started...");
	}

	$('.text').textillate({
		loop: true,
		sync: true,
		in: {
			effect: "bounceIn",
		},
		out: {
			effect: "bounceOut",
		},
	});

	var siriWave = new SiriWave({
		container: document.getElementById("siri-container"),
		width: 800,
		height: 500,
		style: "ios9",
		amplitude: 1,
		speed: 0.3,
		autostart: true,
	});

	$('.siri-message').textillate({
		loop: true,
		sync: true,
		in: {
			effect: "fadeInUp",
			sync: true
		},
		out: {
			effect: "fadeOutUp",
			sync: true
		}
	});

	$("#MicBtn").click(function () {
		eel.playAssistantSound();
		$("#Oval").attr("hidden", true);
		$("#SiriWave").attr("hidden", false);
		eel.allCommands()();
	});

	function doc_keyUp(e) {
		if (e.key === 'j' && e.metaKey) {
			eel.playAssistantSound();
			$("#Oval").attr("hidden", true);
			$("#SiriWave").attr("hidden", false);
			eel.allCommands()();
		}
	}

	document.addEventListener('keyup', doc_keyUp, false);

	eel.on_frontend_ready();
});





























