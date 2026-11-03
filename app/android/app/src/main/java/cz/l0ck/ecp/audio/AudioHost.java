package cz.l0ck.ecp.audio;

import android.app.Application;
import android.content.Intent;
import android.os.PowerManager;
import android.media.AudioAttributes;
import android.media.MediaDataSource;
import android.media.MediaPlayer;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.SystemClock;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

import cz.l0ck.ecp.bramble.EcpService;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * Voice messages: records a short clip (Opus in Ogg at 8 kbit/s on Android 10+, HE-AAC on older
 * phones) and plays clips back from memory. The recording sits in the app's private cache only
 * while it runs; Dart takes the bytes and the file is deleted at once. Playback never writes a
 * file. Microphone permission is asked for by Dart (Permissions) before recording.
 */
public final class AudioHost implements MethodChannel.MethodCallHandler {

	public static final String CHANNEL = "cz.l0ck.ecp/audio";

	/** VoicePart codecs (ecp_core). */
	static final int OPUS = 1, AAC = 2;

	/** VoicePart.maxDuration. */
	static final int MAX_MS = 30_000;

	private final Application app;
	private MethodChannel channel;
	private MediaRecorder recorder;
	private File recording;
	private int codec;
	private long startedAt;
	private MediaPlayer player;
	private PowerManager.WakeLock proximity;

	public AudioHost(Application app) {
		this.app = app;
	}

	public void attach(BinaryMessenger messenger) {
		channel = new MethodChannel(messenger, CHANNEL);
		channel.setMethodCallHandler(this);
	}

	@Override
	public void onMethodCall(io.flutter.plugin.common.MethodCall call, MethodChannel.Result result) {
		try {
			switch (call.method) {
				case "start":
					result.success(start());
					break;
				case "stop":
					result.success(stop());
					break;
				case "cancel":
					cancel();
					result.success(null);
					break;
				case "level":
					result.success(recorder == null ? 0 : recorder.getMaxAmplitude());
					break;
				case "play":
					result.success(play(call.argument("data")));
					break;
				case "stopPlaying":
					stopPlaying();
					result.success(null);
					break;
				case "callAudio":
					callAudio(Boolean.TRUE.equals(call.argument("on")));
					result.success(null);
					break;
				default:
					result.notImplemented();
			}
		} catch (Exception e) {
			cancel();
			result.error("AUDIO", e.toString(), null);
		}
	}

	/** A call starts or ends: the service keeps the microphone through screen-off and lock,
	 *  and the proximity sensor darkens the screen at the ear (no taps by the cheek). */
	private void callAudio(boolean on) {
		Intent i = new Intent(app, EcpService.class).putExtra(EcpService.EXTRA_CALL, on);
		try {
			if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(i);
			else app.startService(i);
		} catch (RuntimeException e) {
			// Not allowed from the background (e.g. the call ended while locked): no harm
		}
		if (on && proximity == null) {
			PowerManager pm = app.getSystemService(PowerManager.class);
			if (pm != null && pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
				proximity = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "ecp:call");
				proximity.acquire(4 * 60 * 60 * 1000L);
			}
		} else if (!on && proximity != null) {
			if (proximity.isHeld()) proximity.release();
			proximity = null;
		}
	}

	private int start() throws IOException {
		cancel();
		stopPlaying();
		MediaRecorder r = Build.VERSION.SDK_INT >= 31 ? new MediaRecorder(app) : new MediaRecorder();
		r.setAudioSource(MediaRecorder.AudioSource.MIC);
		if (Build.VERSION.SDK_INT >= 29) {
			codec = OPUS;
			r.setOutputFormat(MediaRecorder.OutputFormat.OGG);
			r.setAudioEncoder(MediaRecorder.AudioEncoder.OPUS);
			r.setAudioEncodingBitRate(8000);
		} else {
			codec = AAC;
			r.setOutputFormat(MediaRecorder.OutputFormat.AAC_ADTS);
			r.setAudioEncoder(MediaRecorder.AudioEncoder.HE_AAC);
			r.setAudioEncodingBitRate(16000);
		}
		r.setAudioChannels(1);
		r.setAudioSamplingRate(16000);
		r.setMaxDuration(MAX_MS);
		r.setOnInfoListener((mr, what, extra) -> {
			if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED && channel != null) {
				channel.invokeMethod("limit", null); // Dart stops and sends what there is
			}
		});
		recording = File.createTempFile("voice", codec == OPUS ? ".ogg" : ".aac", app.getCacheDir());
		r.setOutputFile(recording.getAbsolutePath());
		r.prepare();
		r.start();
		recorder = r;
		startedAt = SystemClock.elapsedRealtime();
		return codec;
	}

	/** The clip: {data, codec, durationMs}; null when nothing was recording. */
	private Map<String, Object> stop() throws IOException {
		MediaRecorder r = recorder;
		File f = recording;
		if (r == null || f == null) return null;
		recorder = null;
		recording = null;
		long ms = Math.min(MAX_MS, SystemClock.elapsedRealtime() - startedAt);
		try {
			r.stop();
		} catch (RuntimeException tooShort) {
			// stop() right after start() has no data: an empty clip
			r.release();
			f.delete();
			return null;
		}
		r.release();
		byte[] data = Files.readAllBytes(f.toPath());
		f.delete();
		Map<String, Object> clip = new HashMap<>();
		clip.put("data", data);
		clip.put("codec", codec);
		clip.put("durationMs", (int) ms);
		return clip;
	}

	private void cancel() {
		if (recorder != null) {
			try {
				recorder.stop();
			} catch (RuntimeException ignored) {
			}
			recorder.release();
			recorder = null;
		}
		if (recording != null) {
			recording.delete();
			recording = null;
		}
	}

	/** Plays a clip from memory; Dart hears "played" when it ends. Returns its length in ms. */
	private int play(byte[] data) throws IOException {
		stopPlaying();
		MediaPlayer p = new MediaPlayer();
		p.setAudioAttributes(new AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_MEDIA)
				.setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
				.build());
		p.setDataSource(new MediaDataSource() {
			@Override
			public int readAt(long position, byte[] buffer, int offset, int size) {
				if (position >= data.length) return -1;
				int n = (int) Math.min(size, data.length - position);
				System.arraycopy(data, (int) position, buffer, offset, n);
				return n;
			}

			@Override
			public long getSize() {
				return data.length;
			}

			@Override
			public void close() {
			}
		});
		p.setOnCompletionListener(mp -> {
			stopPlaying();
			if (channel != null) channel.invokeMethod("played", null);
		});
		p.prepare();
		p.start();
		player = p;
		return p.getDuration();
	}

	private void stopPlaying() {
		if (player != null) {
			player.release();
			player = null;
		}
	}
}
