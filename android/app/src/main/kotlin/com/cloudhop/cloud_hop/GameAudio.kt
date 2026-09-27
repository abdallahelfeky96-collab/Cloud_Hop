package com.cloudhop.cloud_hop

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
import android.speech.tts.TextToSpeech
import android.os.Bundle
import android.os.SystemClock
import java.util.Locale
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import java.io.File
import java.util.concurrent.Executors

/** Short cues are preloaded once; music streams separately. All playback stays native. */
class GameAudio(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val pool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attributes).build()
    private val ids = mutableMapOf<String, Int>()
    private val ready = mutableSetOf<Int>()
    private val streams = java.util.ArrayDeque<Int>()
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var music: MediaPlayer? = null
    private var prepared = false
    private var enabled = false
    private var ambience = false
    private val effects = listOf("triple_flip", "jump", "land", "flip", "rocket", "spring_set", "spring", "fall", "start", "lose", "exit", "button")
    private var foreground = true
    private var voice = false
    private var focused = false
    private var focusRequested = false
    private var duck = false
    private var disposed = false
    private var loaded = false
    private var announcer: TextToSpeech? = null
    private var speechReady = false
    private var pendingAnnouncement = 0L
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (!disposed) {
            focused = change == AudioManager.AUDIOFOCUS_GAIN || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
            duck = change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
            applyPlayback()
        }
    }
    private val focusRequest = if (Build.VERSION.SDK_INT >= 26)
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(focusListener, handler).build() else null

    init {
        pool.setOnLoadCompleteListener { _, id, status ->
            if (!disposed && status == 0) ready.add(id)
        }
    }

    fun preload() {
        if (loaded || disposed) return
        loaded = true
        announcer = TextToSpeech(context) { status ->
            handler.post {
                if (!disposed && status == TextToSpeech.SUCCESS) {
                    val engine = announcer ?: return@post
                    engine.setLanguage(Locale.US)
                    val offline = engine.voices?.firstOrNull {
                        it.locale.language == "en" && !it.isNetworkConnectionRequired
                    }
                    if (offline != null) {
                        engine.voice = offline
                        engine.setAudioAttributes(attributes)
                        engine.setSpeechRate(.95f)
                        speechReady = true
                        if (pendingAnnouncement > SystemClock.uptimeMillis()) speakChallenge()
                    }
                    pendingAnnouncement = 0L
                }
            }
        }
        worker.execute {
            try {
                val files = (effects + "gameplay").associateWith { name ->
                    val key = FlutterInjector.instance().flutterLoader()
                        .getLookupKeyForAsset("assets/audio/$name.wav")
                    val file = File(context.cacheDir, "cloud-hop-audio-v1-$name.wav")
                    context.assets.open(key).use { input -> file.outputStream().use { input.copyTo(it) } }
                    file
                }
                handler.post {
                    if (!disposed) {
                      try {
                        for (name in effects)
                            ids[name] = pool.load(files.getValue(name).absolutePath, 1)
                        val player = MediaPlayer()
                        music = player
                        player.setAudioAttributes(attributes)
                        player.setDataSource(files.getValue("gameplay").absolutePath)
                        player.isLooping = true
                        player.setOnPreparedListener {
                            if (!disposed) { prepared = true; applyPlayback() }
                        }
                        player.setOnErrorListener { _, what, extra ->
                            Log.w("CloudHopAudio", "Music error $what/$extra")
                            prepared = false
                            true
                        }
                        player.prepareAsync()
                      } catch (error: Exception) {
                        prepared = false
                        music?.release()
                        music = null
                        Log.w("CloudHopAudio", "Could not prepare audio", error)
                      }
                    }
                }
            } catch (error: Exception) {
                Log.w("CloudHopAudio", "Audio assets unavailable", error)
            }
        }
    }

    fun configure(play: Boolean, allowed: Boolean, voiceActive: Boolean) {
        if (disposed) return
        val entering = allowed && !enabled
        val voiceEnded = voice && !voiceActive
        enabled = allowed
        ambience = play
        voice = voiceActive
        if (!enabled) abandonFocus()
        else if (foreground && !voice && (entering || voiceEnded)) requestFocus()
        // Do not compete with LiveKit for focus when voice connects.
        applyPlayback()
    }

    fun cue(name: String) {
        if (disposed || !enabled || !foreground || !focused) return
        if (name == "exit") { pendingAnnouncement = 0L; announcer?.stop() }
        if (name == "challenge_voice") {
            if (speechReady) speakChallenge()
            else pendingAnnouncement = SystemClock.uptimeMillis() + 3000L
            return
        }
        val id = ids[name] ?: return
        if (!ready.contains(id)) return // Never replay a stale cue after loading.
        val gain = (when (name) { "jump" -> .45f; "land" -> .40f; "button" -> .55f; else -> .72f }) * if (duck || voice) .35f else 1f
        val stream = pool.play(id, gain, gain, 1, 0, 1f)
        if (stream != 0) streams.addLast(stream)
        while (streams.size > 4) pool.stop(streams.removeFirst())
    }

    private fun speakChallenge() {
        if (!disposed && enabled && foreground && focused && speechReady) {
            val params = Bundle()
            params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, if (voice || duck) .25f else .75f)
            announcer?.speak("Let's see who will touch the sky.", TextToSpeech.QUEUE_FLUSH, params, "cloud-hop-challenge")
        }
    }

    fun setForeground(value: Boolean) {
        foreground = value
        if (!foreground) abandonFocus()
        else if (enabled && !voice) requestFocus()
        applyPlayback()
    }

    @Suppress("DEPRECATION")
    private fun requestFocus() {
        focusRequested = true
        focused = (if (Build.VERSION.SDK_INT >= 26) manager.requestAudioFocus(focusRequest!!)
            else manager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (focusRequested) {
            if (Build.VERSION.SDK_INT >= 26) manager.abandonAudioFocusRequest(focusRequest!!)
            else manager.abandonAudioFocus(focusListener)
        }
        focused = false
        focusRequested = false
    }

    private fun applyPlayback() {
        if (disposed) return
        val audible = enabled && foreground && focused
        if (!audible) { pendingAnnouncement = 0L; announcer?.stop() }
        if (!audible) while (!streams.isEmpty()) pool.stop(streams.removeFirst())
        if (prepared) {
            val player = music ?: return
            val volume = if (duck || voice) .16f else .70f
            player.setVolume(volume, volume)
            if (audible && ambience && !player.isPlaying) player.start()
            else if ((!audible || !ambience) && player.isPlaying) player.pause()
        }
    }

    fun release() {
        if (disposed) return
        abandonFocus()
        disposed = true
        worker.shutdown()
        announcer?.stop()
        announcer?.shutdown()
        announcer = null
        pool.release()
        music?.release()
        music = null
        ready.clear()
    }
}

